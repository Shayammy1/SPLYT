using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace NovaVM.Gui.Services.PowerShell;

public interface IPowerShellRunner
{
    Task<PowerShellResult> RunAsync(string scriptFileName, params (string Name, string Value)[] parameters);

    /// <summary>Comme RunAsync, mais invoque onProgress(step) pour chaque ligne
    /// {"progress":"..."} ecrite par le script AVANT son resultat final (voir
    /// Write-NovaProgress). Permet une barre de progression qui reflete
    /// l'avancement reel du script plutot qu'une simulation cote GUI.</summary>
    Task<PowerShellResult> RunWithProgressAsync(
        string scriptFileName, Action<string> onProgress, params (string Name, string Value)[] parameters);

    /// <summary>Lance le script dans un processus PowerShell ELEVE (invite UAC).
    /// Necessaire pour les operations DISM (Get-WindowsDriver/Add-WindowsDriver),
    /// qui exigent l'appartenance au groupe Administrateurs local, independamment
    /// des droits Hyper-V Administrateurs deja suffisants pour le reste de l'appli.
    /// Verb=runas est incompatible avec la redirection directe de flux .NET :
    /// le script eleve ecrit donc lui-meme sa sortie dans un fichier temporaire.
    /// Si onProgress est fourni, ce fichier est relu au fil de l'eau pendant
    /// l'execution pour rapporter les etapes reellement franchies (voir
    /// Write-NovaProgress) - la progression reste donc reelle, jamais simulee,
    /// meme dans ce mode.</summary>
    Task<PowerShellResult> RunElevatedAsync(
        string scriptFileName, Action<string>? onProgress, params (string Name, string Value)[] parameters);

    /// <summary>RunElevatedAsync sans suivi de progression.</summary>
    Task<PowerShellResult> RunElevatedAsync(string scriptFileName, params (string Name, string Value)[] parameters);

    /// <summary>Lance le script en lui transmettant nom d'utilisateur et mot de
    /// passe par l'ENTREE STANDARD (jamais en argument de ligne de commande,
    /// jamais journalises : un argument de processus est visible par n'importe
    /// quel autre processus du systeme via son interface, une ligne stdin ne
    /// l'est pas). Le script doit les lire avec [Console]::In.ReadLine() (nom
    /// puis mot de passe, dans cet ordre).</summary>
    Task<PowerShellResult> RunWithCredentialAsync(
        string scriptFileName, string username, string password, params (string Name, string Value)[] parameters);
}

/// <summary>
/// Lance les scripts de scripts/hyperv/ (copies a cote de l'executable au build,
/// voir NovaVM.Gui.csproj) via powershell.exe et parse leur sortie JSON.
///
/// -ExecutionPolicy Bypass n'est applique qu'a ce processus powershell.exe
/// ponctuel : il ne modifie ni la strategie d'execution de la machine, ni celle
/// de l'utilisateur. C'est la maniere standard, sans effet durable, de lancer
/// des scripts locaux non signes depuis une application.
/// </summary>
public sealed class PowerShellRunner : IPowerShellRunner
{
    private readonly string _scriptsRoot;

    public PowerShellRunner()
    {
        _scriptsRoot = Path.Combine(AppContext.BaseDirectory, "hyperv");
    }

    public Task<PowerShellResult> RunAsync(string scriptFileName, params (string Name, string Value)[] parameters) =>
        RunCoreAsync(scriptFileName, onProgress: null, parameters);

    public Task<PowerShellResult> RunWithProgressAsync(
        string scriptFileName, Action<string> onProgress, params (string Name, string Value)[] parameters) =>
        RunCoreAsync(scriptFileName, onProgress, parameters);

    private async Task<PowerShellResult> RunCoreAsync(
        string scriptFileName, Action<string>? onProgress, (string Name, string Value)[] parameters)
    {
        var scriptPath = Path.Combine(_scriptsRoot, scriptFileName);
        if (!File.Exists(scriptPath))
        {
            return PowerShellResult.Failed(
                $"Script introuvable : {scriptPath}. Le projet a-t-il ete recompile apres l'ajout de scripts/hyperv ?");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        foreach (var (name, value) in parameters)
        {
            startInfo.ArgumentList.Add("-" + name);
            startInfo.ArgumentList.Add(value);
        }

        using var process = new Process { StartInfo = startInfo };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) return;
            stdout.AppendLine(e.Data);
            if (onProgress is not null) TryReportProgress(e.Data, onProgress);
        };
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) stderr.AppendLine(e.Data); };

        try
        {
            process.Start();
        }
        catch (Exception ex)
        {
            return PowerShellResult.Failed($"Impossible de lancer powershell.exe : {ex.Message}");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();

        return PowerShellResult.Parse(stdout.ToString(), stderr.ToString(), process.ExitCode);
    }

    public async Task<PowerShellResult> RunWithCredentialAsync(
        string scriptFileName, string username, string password, params (string Name, string Value)[] parameters)
    {
        var scriptPath = Path.Combine(_scriptsRoot, scriptFileName);
        if (!File.Exists(scriptPath))
        {
            return PowerShellResult.Failed(
                $"Script introuvable : {scriptPath}. Le projet a-t-il ete recompile apres l'ajout de scripts/hyperv ?");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            // UTF-8 SANS BOM impose explicitement. Sans cette ligne, l'entree
            // standard prend l'encodage de la console ; quand SPLYT est lance
            // depuis un terminal en UTF-8 (chcp 65001, ou l'option "Beta :
            // utiliser UTF-8" de Windows 11), un BOM est ecrit en tete du flux.
            // Le script lit alors un nom d'utilisateur commencant par ce caractere
            // invisible, et PowerShell Direct repond "Les informations
            // d'identification ne sont pas valides" - un message qui envoie
            // chercher un probleme de mot de passe totalement imaginaire.
            StandardInputEncoding = new UTF8Encoding(false),
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        foreach (var (name, value) in parameters)
        {
            startInfo.ArgumentList.Add("-" + name);
            startInfo.ArgumentList.Add(value);
        }

        using var process = new Process { StartInfo = startInfo };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) stdout.AppendLine(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) stderr.AppendLine(e.Data); };

        try
        {
            process.Start();
        }
        catch (Exception ex)
        {
            return PowerShellResult.Failed($"Impossible de lancer powershell.exe : {ex.Message}");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        // Ecrit identifiant + mot de passe sur stdin, jamais sur la ligne de
        // commande du processus (visible par tout autre processus du systeme).
        await process.StandardInput.WriteLineAsync(username);
        await process.StandardInput.WriteLineAsync(password);
        process.StandardInput.Close();

        await process.WaitForExitAsync();

        return PowerShellResult.Parse(stdout.ToString(), stderr.ToString(), process.ExitCode);
    }

    public Task<PowerShellResult> RunElevatedAsync(
        string scriptFileName, params (string Name, string Value)[] parameters) =>
        RunElevatedAsync(scriptFileName, onProgress: null, parameters);

    public async Task<PowerShellResult> RunElevatedAsync(
        string scriptFileName, Action<string>? onProgress, params (string Name, string Value)[] parameters)
    {
        var scriptPath = Path.Combine(_scriptsRoot, scriptFileName);
        if (!File.Exists(scriptPath))
        {
            return PowerShellResult.Failed(
                $"Script introuvable : {scriptPath}. Le projet a-t-il ete recompile apres l'ajout de scripts/hyperv ?");
        }

        var outputFile = Path.Combine(Path.GetTempPath(), $"novavm_elevated_{Guid.NewGuid():N}.txt");

        var scriptCall = new StringBuilder();
        scriptCall.Append('&').Append(' ').Append(PsQuote(scriptPath));
        foreach (var (name, value) in parameters)
        {
            scriptCall.Append(" -").Append(name).Append(' ').Append(PsQuote(value));
        }
        scriptCall.Append(" *> ").Append(PsQuote(outputFile));

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = true,
            Verb = "runas",
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(scriptCall.ToString());

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return PowerShellResult.Failed("Impossible de lancer powershell.exe (eleve).");
            }

            if (onProgress is not null)
            {
                await FollowProgressFileAsync(outputFile, onProgress, process);
            }

            await process.WaitForExitAsync();
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            // ERROR_CANCELLED : l'utilisateur a refuse l'invite UAC.
            return PowerShellResult.Failed("Elevation refusee (invite administrateur annulee).");
        }
        catch (Exception ex)
        {
            return PowerShellResult.Failed($"Impossible de lancer powershell.exe eleve : {ex.Message}");
        }

        string output;
        try
        {
            output = File.Exists(outputFile) ? await File.ReadAllTextAsync(outputFile, Encoding.UTF8) : "";
        }
        finally
        {
            try { if (File.Exists(outputFile)) File.Delete(outputFile); } catch { /* best-effort */ }
        }

        return PowerShellResult.Parse(output, "", 0);
    }

    /// <summary>Suit le fichier de sortie d'un script ELEVE pendant son execution et
    /// rapporte chaque ligne de progression au fur et a mesure. En mode eleve les flux
    /// ne peuvent pas etre rediriges directement (Verb=runas), mais le fichier, lui,
    /// est ecrit en continu : le relire periodiquement donne une progression tout aussi
    /// reelle, juste avec un leger decalage.
    ///
    /// FileShare.ReadWrite est indispensable : le processus eleve garde le fichier
    /// ouvert en ecriture, une ouverture en lecture exclusive echouerait a chaque fois.</summary>
    private static async Task FollowProgressFileAsync(string path, Action<string> onProgress, Process process)
    {
        var lastPosition = 0L;
        var pending = new StringBuilder();

        while (!process.HasExited)
        {
            await Task.Delay(400);

            try
            {
                if (!File.Exists(path)) continue;

                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                if (stream.Length <= lastPosition) continue;

                stream.Seek(lastPosition, SeekOrigin.Begin);
                using var reader = new StreamReader(stream, Encoding.UTF8);
                var chunk = await reader.ReadToEndAsync();
                lastPosition = stream.Position;

                pending.Append(chunk);
                var text = pending.ToString();
                var lastNewline = text.LastIndexOf('\n');
                if (lastNewline < 0) continue;

                // Ne traite que les lignes COMPLETES : la derniere, potentiellement
                // coupee en plein milieu d'ecriture, est gardee pour le tour suivant.
                foreach (var line in text[..lastNewline].Split('\n'))
                {
                    TryReportProgress(line, onProgress);
                }
                pending.Clear();
                pending.Append(text[(lastNewline + 1)..]);
            }
            catch (IOException)
            {
                // Fichier momentanement verrouille : on reessaie au tour suivant.
            }
        }
    }

    /// <summary>Met entre quotes simples pour PowerShell, en doublant les quotes
    /// simples internes (echappement standard PowerShell : ' -> '').</summary>
    private static string PsQuote(string value) => "'" + value.Replace("'", "''") + "'";

    /// <summary>Reconnait une ligne {"progress":"..."} (voir Write-NovaProgress) et
    /// ignore silencieusement toute autre ligne (resultat final, diagnostics...).</summary>
    private static void TryReportProgress(string line, Action<string> onProgress)
    {
        var trimmed = line.Trim();
        if (trimmed.Length == 0 || trimmed[0] != '{') return;

        try
        {
            using var doc = JsonDocument.Parse(trimmed);
            if (doc.RootElement.TryGetProperty("progress", out var progressProp) &&
                progressProp.ValueKind == JsonValueKind.String)
            {
                var step = progressProp.GetString();
                if (!string.IsNullOrEmpty(step)) onProgress(step);
            }
        }
        catch (JsonException)
        {
            // Pas une ligne de progression valide : ignoree.
        }
    }
}
