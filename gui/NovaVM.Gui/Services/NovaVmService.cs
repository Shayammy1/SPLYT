using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using NovaVM.Gui.Models;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.Services;

/// <summary>
/// Couche "logique metier" : traduit des intentions (creer une VM, la demarrer...)
/// en appels aux scripts scripts/hyperv/*.ps1 via IPowerShellRunner, journalise
/// chaque operation dans LogService, et convertit les DTOs JSON en modeles
/// observables (Models/). La GUI (ViewModels) ne connait que cette classe : elle
/// ne sait pas que le backend est du PowerShell.
/// </summary>
public sealed class NovaVmService
{
    private readonly IPowerShellRunner _runner;
    private readonly LogService _log;

    public NovaVmService(IPowerShellRunner runner, LogService log)
    {
        _runner = runner;
        _log = log;
    }

    /// <summary>Chemin local ou l'ISO Windows 11 est mise en cache apres son premier
    /// telechargement (voir DownloadWindowsIsoAsync / Get-NovaVmWindowsIso.ps1) - doit
    /// rester synchronise avec le -OutputPath par defaut de ce script.</summary>
    public static readonly string DefaultWindowsIsoPath = @"C:\NovaVM\Downloads\Windows11.iso";

    /// <summary>Verification synchrone (pas de PowerShell necessaire, juste un fichier
    /// local) : permet a CreateVmDialogViewModel de preremplir directement le champ ISO
    /// des l'ouverture du formulaire si une image a deja ete telechargee auparavant.</summary>
    public bool IsWindowsIsoCached() => File.Exists(DefaultWindowsIsoPath);

    /// <summary>Telecharge l'ISO officielle de Windows 11 depuis les serveurs Microsoft
    /// (voir Get-NovaVmWindowsIso.ps1 pour le detail complet et les limites connues du
    /// procede) et la met en cache pour toutes les creations de VM suivantes. onProgress
    /// recoit le texte de progression brut (pourcentage + Go telecharges), pas un libelle
    /// d'etape fixe comme pour CreateVmAsync.</summary>
    public async Task<(WindowsIsoResultDto? Result, string? Error)> DownloadWindowsIsoAsync(Action<string>? onProgress = null)
    {
        var result = await RunAsyncCore("Get-NovaVmWindowsIso.ps1", "Telechargement de l'ISO Windows 11", silent: false, onProgress);
        if (!result.Success) return (null, result.Error ?? result.RawError);

        var dto = result.DeserializeData<WindowsIsoResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    public async Task<List<VirtualMachine>> GetVmsAsync()
    {
        var result = await RunAsync("Get-NovaVmList.ps1", "Liste des VMs");
        var dtos = result.DeserializeData<List<VirtualMachineDto>>() ?? new();
        return dtos.Select(VirtualMachine.FromDto).ToList();
    }

    /// <summary>onProgress, si fourni, est appele en temps reel pour chaque etape
    /// reellement franchie par New-NovaVm.ps1 (voir Write-NovaProgress) : permet
    /// a la GUI d'afficher une barre de progression fidele a l'avancement reel.
    /// Contrairement aux autres actions (RunForVmAsync), retourne le message
    /// d'erreur precis en cas d'echec (ex. "Une VM nommee 'X' existe deja.") au
    /// lieu de le laisser uniquement dans le Journal : l'utilisateur le voit
    /// immediatement dans le dialogue de creation.</summary>
    public async Task<(VirtualMachine? Vm, string? Error)> CreateVmAsync(
        string name, int cpu, long memoryMb, int diskSizeGb,
        string? gpuName, int gpuVramMb, string? isoPath, bool dynamicMemoryEnabled = false, Action<string>? onProgress = null)
    {
        var result = await RunAsyncCore("New-NovaVm.ps1", $"Creation de la VM '{name}'", silent: false, onProgress,
            ("Name", name),
            ("Cpu", cpu.ToString(CultureInfo.InvariantCulture)),
            ("MemoryMb", memoryMb.ToString(CultureInfo.InvariantCulture)),
            ("DiskSizeGb", diskSizeGb.ToString(CultureInfo.InvariantCulture)),
            ("GpuName", gpuName ?? ""),
            ("GpuVramMb", gpuVramMb.ToString(CultureInfo.InvariantCulture)),
            ("IsoPath", isoPath ?? ""),
            ("DynamicMemoryEnabled", dynamicMemoryEnabled ? "true" : "false"));

        if (!result.Success) return (null, result.Error ?? result.RawError);

        var dto = result.DeserializeData<VirtualMachineDto>();
        return dto is null
            ? (null, "Reponse invalide du script New-NovaVm.ps1.")
            : (VirtualMachine.FromDto(dto), null);
    }

    /// <summary>Demarre reellement la VM Hyper-V puis ouvre sa console d'affichage
    /// (vmconnect.exe) : c'est la ou le BIOS/UEFI et les messages de demarrage
    /// (ou "aucun peripherique amorcable") sont reellement visibles - on ne les
    /// simule jamais dans la GUI.</summary>
    public async Task<VirtualMachine?> StartVmAsync(string name)
    {
        var result = await RunAsyncCore(
            "Start-NovaVm.ps1", $"Demarrage de '{name}'", silent: false, onProgress: null, ("Name", name));
        if (!result.Success) return null;

        var dto = result.DeserializeData<VirtualMachineDto>();
        if (dto is null) return null;

        OpenVmConnectConsole(name, dto.NeedsBootKeyPress);
        return VirtualMachine.FromDto(dto);
    }

    /// <summary>needsBootKeyPress : voir ConvertTo-NovaVmDto - vrai seulement si un
    /// lecteur DVD est monte ET encore premier peripherique de demarrage (donc
    /// Windows Setup pas encore termine). Dans ce cas, une fois la console ouverte,
    /// SPLYT simule elle-meme un appui pour passer l'invite firmware "Press any key
    /// to boot from CD or DVD..." - voir SendBootKeyBurstAsync pour pourquoi ce
    /// n'est PAS fait via le clavier synthetique WMI (Msvm_Keyboard).</summary>
    private async void OpenVmConnectConsole(string vmName, bool needsBootKeyPress)
    {
        try
        {
            var vmconnectPath = Path.Combine(Environment.SystemDirectory, "vmconnect.exe");
            var startInfo = new ProcessStartInfo
            {
                FileName = vmconnectPath,
                UseShellExecute = false,
            };
            startInfo.ArgumentList.Add("localhost");
            startInfo.ArgumentList.Add(vmName);
            var process = Process.Start(startInfo);
            if (process is null) return;

            var hwnd = await ResizeConsoleWindowAsync(process);
            if (needsBootKeyPress && hwnd != IntPtr.Zero)
            {
                await SendBootKeyBurstAsync(hwnd);
            }
        }
        catch (Exception ex)
        {
            _log.Log(LogLevel.Warning, "vmconnect.exe",
                $"Impossible d'ouvrir automatiquement la console de '{vmName}'", ex.Message);
        }
    }

    // Taille "moyenne" ciblee pour la console vmconnect : assez grande pour voir
    // tout l'installeur Windows (bouton "Suivant" compris), mais pas plein ecran.
    private const int ConsoleWindowWidth = 1280;
    private const int ConsoleWindowHeight = 800;

    /// <summary>vmconnect s'ouvre par defaut dans une petite fenetre a taille fixe
    /// (ex. 210x308). Un redimensionnement direct (SetWindowPos/MoveWindow) depuis
    /// cette taille est imprevisible : vmconnect le "clampe" parfois a une taille
    /// arbitraire (verifie empiriquement). En revanche, agrandir la fenetre UNE
    /// FOIS (fiable, verifie) puis la redimensionner ENSUITE a la taille voulue
    /// fonctionne de maniere fiable et stable dans le temps. Resultat : une
    /// fenetre moyenne (1280x800), pas plein ecran, avec tout l'affichage visible.
    /// Retourne le handle de la fenetre (IntPtr.Zero si jamais trouvee) pour que
    /// l'appelant puisse y envoyer des touches ensuite (voir SendBootKeyBurstAsync).</summary>
    private static async Task<IntPtr> ResizeConsoleWindowAsync(Process process)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        var hwnd = IntPtr.Zero;
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                process.Refresh();
                hwnd = process.MainWindowHandle;
            }
            catch (InvalidOperationException)
            {
                return IntPtr.Zero; // Le processus s'est deja termine.
            }
            if (hwnd != IntPtr.Zero) break;
            await Task.Delay(200);
        }
        if (hwnd == IntPtr.Zero) return IntPtr.Zero;

        NativeWindow.ShowWindow(hwnd, NativeWindow.SW_MAXIMIZE);
        await Task.Delay(500);

        var (x, y) = NativeWindow.GetCenteredPosition(ConsoleWindowWidth, ConsoleWindowHeight);
        NativeWindow.MoveWindow(hwnd, x, y, ConsoleWindowWidth, ConsoleWindowHeight, true);
        return hwnd;
    }

    /// <summary>Simule un appui repete sur Espace DANS la fenetre vmconnect (comme le
    /// ferait un utilisateur), pour passer automatiquement l'invite firmware "Press
    /// any key to boot from CD or DVD...".
    ///
    /// Verifie empiriquement (capture d'ecran + logs de diagnostic) qu'une premiere
    /// approche - le clavier synthetique WMI (Msvm_Keyboard.TypeKey), independante
    /// de toute fenetre - fonctionnait sur une VM sans GPU-P mais PAS sur une VM
    /// avec un adaptateur GPU-P attache (Add-VMGpuPartitionAdapter) : les appels WMI
    /// reussissaient sans la moindre erreur, mais la touche n'atteignait jamais
    /// reellement l'invite de demarrage. Puisque GPU-P est la fonctionnalite phare
    /// de SPLYT, cette approche etait inutilisable pour l'usage reel. A l'inverse,
    /// un appui reellement recu par la fenetre vmconnect (confirme manuellement par
    /// l'utilisateur) fonctionne dans tous les cas, GPU-P ou non - d'ou SendInput
    /// cible sur cette fenetre plutot que WMI.</summary>
    private static async Task SendBootKeyBurstAsync(IntPtr hwnd)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            NativeWindow.SetForegroundWindow(hwnd);
            NativeWindow.keybd_event(NativeWindow.VK_SPACE, 0, 0, UIntPtr.Zero);
            NativeWindow.keybd_event(NativeWindow.VK_SPACE, 0, NativeWindow.KEYEVENTF_KEYUP, UIntPtr.Zero);
            await Task.Delay(250);
        }
    }

    /// <summary>P/Invoke minimal pour redimensionner la fenetre vmconnect.</summary>
    private static class NativeWindow
    {
        public const int SW_MAXIMIZE = 3;

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        // keybd_event (pas SendInput) : simple, suffisant pour simuler un appui sur
        // une touche sans modificateur, et cible - comme SendInput l'aurait fait -
        // la fenetre au premier plan (d'ou SetForegroundWindow juste avant).
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        public const byte VK_SPACE = 0x20;
        public const uint KEYEVENTF_KEYUP = 0x0002;

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int nIndex);

        private const int SM_CXSCREEN = 0;
        private const int SM_CYSCREEN = 1;

        public static (int X, int Y) GetCenteredPosition(int width, int height)
        {
            var screenW = GetSystemMetrics(SM_CXSCREEN);
            var screenH = GetSystemMetrics(SM_CYSCREEN);
            var x = Math.Max(0, (screenW - width) / 2);
            var y = Math.Max(0, (screenH - height) / 2);
            return (x, y);
        }
    }

    public Task<VirtualMachine?> StopVmAsync(string name) =>
        RunForVmAsync("Stop-NovaVm.ps1", $"Arret de '{name}'", ("Name", name), ("Force", "false"));

    public Task<VirtualMachine?> ForceStopVmAsync(string name) =>
        RunForVmAsync("Stop-NovaVm.ps1", $"Arret force de '{name}'", ("Name", name), ("Force", "true"));

    /// <summary>Arrete (normalement) toutes les VMs en cours d'execution - utilise a la
    /// fermeture de SPLYT. Best-effort : Hyper-V traite chaque arret independamment du
    /// processus SPLYT, donc pas besoin d'attendre la fin reelle avant de fermer la
    /// fenetre. Les echecs individuels (ex. service d'integration Arret absent) sont
    /// journalises mais n'empechent pas les autres VMs d'etre arretees.</summary>
    public async Task StopAllRunningVmsAsync()
    {
        var vms = await GetVmsAsync();
        var runningVmNames = vms.Where(v => v.State == VmState.Running).Select(v => v.Name).ToList();
        await Task.WhenAll(runningVmNames.Select(StopVmAsync));
    }

    public async Task<(bool Success, string? Error)> DeleteVmAsync(string name)
    {
        var result = await RunAsync("Remove-NovaVm.ps1", $"Suppression de '{name}'", ("Name", name));
        return (result.Success, result.Success ? null : (result.Error ?? result.RawError));
    }

    public Task<VirtualMachine?> SetResourcesAsync(string name, int cpu, long memoryMb, bool dynamicMemoryEnabled) =>
        RunForVmAsync("Set-NovaVmResources.ps1", $"Mise a jour des ressources de '{name}'",
            ("Name", name),
            ("Cpu", cpu.ToString(CultureInfo.InvariantCulture)),
            ("MemoryMb", memoryMb.ToString(CultureInfo.InvariantCulture)),
            ("DynamicMemoryEnabled", dynamicMemoryEnabled ? "true" : "false"));

    /// <summary>Configure un VRAI adaptateur GPU-P (Add/Set-VMGpuPartitionAdapter),
    /// pas une simple preference : voir Set-NovaVmGpuPartition.ps1. La VM doit
    /// etre eteinte. Retourne le message d'erreur precis en cas d'echec (ex.
    /// GPU non partitionnable, VM non eteinte) plutot que de le laisser
    /// uniquement dans le Journal.</summary>
    public async Task<(VirtualMachine? Vm, string? Error)> SetGpuPartitionAsync(string name, string? gpuName, int gpuVramMb)
    {
        var result = await RunAsync("Set-NovaVmGpuPartition.ps1", $"Mise a jour GPU-P de '{name}'",
            ("Name", name),
            ("GpuName", gpuName ?? ""),
            ("GpuVramMb", gpuVramMb.ToString(CultureInfo.InvariantCulture)));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<VirtualMachineDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (VirtualMachine.FromDto(dto), null);
    }

    /// <summary>Diagnostic GPU-P complet et honnete (compatibilite hote, adaptateur
    /// reellement attache) : voir Get-NovaVmGpuDiagnostics.ps1. Ne necessite pas
    /// d'elevation (ne verifie pas le pilote invite, voir InstallGpuDriverAsync).</summary>
    public async Task<GpuDiagnosticsDto?> GetGpuDiagnosticsAsync(string name)
    {
        var result = await RunAsync("Get-NovaVmGpuDiagnostics.ps1", $"Diagnostic GPU-P de '{name}'", ("Name", name));
        return result.DeserializeData<GpuDiagnosticsDto>();
    }

    /// <summary>Copie hors-ligne (DISM) le paquet de pilote du GPU hote configure
    /// en GPU-P sur cette VM dans son disque : voir Install-NovaVmGpuDriver.ps1.
    /// Necessite une elevation (invite UAC) independamment des droits Hyper-V
    /// Administrateurs deja suffisants pour le reste de l'appli : DISM l'exige.
    /// La VM doit etre eteinte (montage hors-ligne de son VHDX).</summary>
    public async Task<(GpuDriverInstallResultDto? Result, string? Error)> InstallGpuDriverAsync(
        string name, Action<string>? onProgress = null)
    {
        var result = await _runner.RunElevatedAsync("Install-NovaVmGpuDriver.ps1", onProgress, ("Name", name));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Install-NovaVmGpuDriver.ps1",
            $"Installation du pilote GPU-P pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<GpuDriverInstallResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>BIDOUILLE NON OFFICIELLE (contrairement a InstallGpuDriverAsync) : patche
    /// le pilote noyau NVIDIA fourni pour contourner sa detection d'hyperviseur, avant de
    /// l'enregistrer sur la VM avec le Mode test active - voir Install-NovaVmNvidiaPatchedDriver.ps1
    /// pour le detail complet, les limites connues et pourquoi ca peut echouer proprement
    /// (motif d'octets non trouve = pilote trop recent pour cette technique abandonnee).
    /// Necessite une elevation ; la VM doit etre eteinte ; executer d'abord InstallGpuDriverAsync
    /// (methode officielle) au moins une fois sur cette VM.</summary>
    public async Task<(NvidiaGpuPatchResultDto? Result, string? Error)> InstallNvidiaPatchedDriverAsync(
        string name, string driverInstallerPath)
    {
        var result = await _runner.RunElevatedAsync("Install-NovaVmNvidiaPatchedDriver.ps1",
            ("Name", name), ("DriverInstallerPath", driverInstallerPath));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Install-NovaVmNvidiaPatchedDriver.ps1",
            $"Patch du pilote NVIDIA pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<NvidiaGpuPatchResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Diagnostic honnete de la limitation de frequence d'affichage
    /// (vmconnect n'a pas de vrai signal a frequence variable) : voir
    /// Get-NovaVmDisplayDiagnostics.ps1.</summary>
    public async Task<DisplayDiagnosticsDto?> GetDisplayDiagnosticsAsync(string name)
    {
        var result = await RunAsync("Get-NovaVmDisplayDiagnostics.ps1", $"Diagnostic d'affichage de '{name}'", ("Name", name));
        return result.DeserializeData<DisplayDiagnosticsDto>();
    }

    /// <summary>Prepare Sunshine/Moonlight (streaming) pour depasser la limite
    /// des 60 Hz de vmconnect : voir Enable-NovaVmStreaming.ps1. La VM doit
    /// etre demarree (Copy-VMFile). Laisse des etapes manuelles obligatoires
    /// (identifiants de session invite, appariement securise) - jamais
    /// automatisees en pretendant le contraire.</summary>
    public async Task<(StreamingSetupResultDto? Result, string? Error)> EnableStreamingAsync(string name)
    {
        var result = await RunAsync("Enable-NovaVmStreaming.ps1", $"Preparation du streaming pour '{name}'", ("Name", name));
        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<StreamingSetupResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Installe Sunshine SILENCIEUSEMENT dans la VM via PowerShell
    /// Direct, avec les identifiants Windows de la VM (jamais stockes, transmis
    /// une seule fois par entree standard) : voir Install-NovaVmSunshineViaCredential.ps1
    /// et PowerShellRunner.RunWithCredentialAsync. C'est le maximum automatisable
    /// sans compromettre soit la securite Windows (installation = authentification
    /// requise), soit la protection anti-streaming-non-consenti de Sunshine
    /// (appariement par code PIN, jamais contourne).</summary>
    public async Task<(SunshineInstallResultDto? Result, string? Error)> InstallSunshineAutomaticallyAsync(
        string name, string username, string password)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Install-NovaVmSunshineViaCredential.ps1", username, password, ("Name", name));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Install-NovaVmSunshineViaCredential.ps1",
            $"Installation automatique de Sunshine pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<SunshineInstallResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Configure Sunshine pour la meilleure qualite possible et apparie
    /// automatiquement Moonlight avec lui (plus aucun code PIN a saisir) - voir
    /// Set-NovaVmStreamingQuality.ps1. Necessite les identifiants Windows de la VM :
    /// les reglages s'ecrivent a l'interieur de l'invite.</summary>
    public async Task<(StreamingQualityResultDto? Result, string? Error)> SetStreamingQualityAsync(
        string name, string username, string password)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Set-NovaVmStreamingQuality.ps1", username, password, ("Name", name));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Set-NovaVmStreamingQuality.ps1",
            $"Configuration du streaming pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<StreamingQualityResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Demarre la VM si necessaire, attend qu'elle soit joignable, puis ouvre
    /// Moonlight deja connecte avec les reglages de qualite - voir
    /// Start-NovaVmMoonlight.ps1. Ne demande aucun identifiant : tout se passe cote
    /// hote et via Hyper-V.</summary>
    public async Task<(MoonlightLaunchResultDto? Result, string? Error)> StartWithMoonlightAsync(
        string name, int fps, Action<string>? onProgress = null)
    {
        var result = await RunAsyncCore("Start-NovaVmMoonlight.ps1", $"Lancement de '{name}' avec Moonlight",
            silent: false, onProgress,
            ("Name", name), ("Fps", fps.ToString(CultureInfo.InvariantCulture)));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<MoonlightLaunchResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Attend que Windows ait fini de demarrer dans la VM et reponde
    /// (heartbeat Hyper-V) : Start-VM rend la main bien avant que PowerShell Direct
    /// soit utilisable. Voir Wait-NovaVmGuestReady.ps1.</summary>
    public async Task<bool> WaitForGuestReadyAsync(string name, Action<string>? onProgress = null)
    {
        var result = await RunAsyncCore("Wait-NovaVmGuestReady.ps1", $"Attente du demarrage de Windows dans '{name}'",
            silent: false, onProgress, ("Name", name));
        return result.Success;
    }

    public async Task<(EnhancedSessionFixResultDto? Result, string? Error)> FixEnhancedSessionAsync(
        string name, string username, string password)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Fix-NovaVmEnhancedSession.ps1", username, password, ("Name", name));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Fix-NovaVmEnhancedSession.ps1",
            $"Correction Session Amelioree (Windows Hello) pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<EnhancedSessionFixResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    public async Task<(VddDiagnosticsResultDto? Result, string? Error)> DiagnoseVddAsync(
        string name, string username, string password, bool disable, bool enable = false)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Repair-NovaVmVdd.ps1", username, password,
            ("Name", name), ("Disable", disable ? "true" : "false"), ("Enable", enable ? "true" : "false"));

        var actionLabel = disable ? " (avec desactivation)" : enable ? " (avec activation)" : "";
        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Repair-NovaVmVdd.ps1",
            $"Diagnostic VDD pour '{name}'" + actionLabel + " : " +
            (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<VddDiagnosticsResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Installe automatiquement VDD dans la VM (telechargement + NefCon +
    /// certificat de confiance) - voir Install-NovaVmVdd.ps1 pour le detail complet
    /// de la methode, reprise du script d'installation silencieuse officiel du projet.</summary>
    public async Task<(VddInstallResultDto? Result, string? Error)> InstallVddAsync(
        string name, string username, string password)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Install-NovaVmVdd.ps1", username, password, ("Name", name));

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Install-NovaVmVdd.ps1",
            $"Installation automatique de VDD pour '{name}' : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<VddInstallResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    /// <summary>Applique des optimisations Windows courantes (performances et/ou vie
    /// privee) a l'interieur de la VM - voir Optimize-NovaVmGaming.ps1 pour le detail
    /// complet de chaque reglage.</summary>
    public async Task<(GamingOptimizationResultDto? Result, string? Error)> OptimizeGamingAsync(
        string name, string username, string password, bool performance, bool privacy)
    {
        var result = await _runner.RunWithCredentialAsync(
            "Optimize-NovaVmGaming.ps1", username, password,
            ("Name", name), ("Performance", performance ? "true" : "false"), ("Privacy", privacy ? "true" : "false"));

        var actionLabel = performance && privacy ? " (performances + vie privee)" : performance ? " (performances)" : " (vie privee)";
        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Optimize-NovaVmGaming.ps1",
            $"Optimisations gaming pour '{name}'" + actionLabel + " : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<GamingOptimizationResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    public async Task<List<HostGpu>> GetHostGpusAsync()
    {
        var result = await RunAsync("Get-NovaVmHostGpus.ps1", "Detection des GPU hote");
        var dtos = result.DeserializeData<List<HostGpuDto>>() ?? new();
        return dtos.Select(d => new HostGpu
        {
            Name = d.Name ?? "GPU inconnu",
            VramBytes = d.VramBytes,
            DriverVersion = d.DriverVersion,
            PartitionSupported = d.PartitionSupported,
            PartitionCheckError = d.PartitionCheckError,
        }).ToList();
    }

    public async Task<HostStats> GetHostStatsAsync()
    {
        var result = await RunSilentAsync("Get-NovaVmHostStats.ps1", "Statistiques hote");
        var dto = result.DeserializeData<HostStatsDto>();
        if (dto is null) return HostStats.Empty;
        return new HostStats
        {
            CpuUsagePercent = dto.CpuUsagePercent,
            RamUsedGb = dto.RamUsedGb,
            RamTotalGb = dto.RamTotalGb,
            StorageUsedGb = dto.StorageUsedGb,
            StorageTotalGb = dto.StorageTotalGb,
        };
    }

    public async Task<List<VirtualDisk>> GetDisksAsync()
    {
        var result = await RunAsync("Get-NovaVmDisks.ps1", "Liste des disques");
        var dtos = result.DeserializeData<List<VirtualDiskDto>>() ?? new();
        return dtos.Select(d => new VirtualDisk
        {
            Path = d.Path ?? "",
            SizeGb = d.SizeGb,
            UsedGb = d.UsedGb,
            AttachedVm = d.AttachedVm,
        }).ToList();
    }

    public async Task<DiagnosticsDto?> GetDiagnosticsAsync()
    {
        var result = await RunAsync("Get-NovaVmDiagnostics.ps1", "Diagnostic Hyper-V/GPU-P");
        return result.DeserializeData<DiagnosticsDto>();
    }

    /// <summary>Active Hyper-V si necessaire et ajoute l'utilisateur au groupe local
    /// "Hyper-V Administrators" - voir Enable-NovaVmHyperV.ps1. Necessite une elevation
    /// (invite UAC), independamment des droits Hyper-V Administrateurs eux-memes.</summary>
    public async Task<(HyperVSetupResultDto? Result, string? Error)> EnableHyperVAsync()
    {
        var result = await _runner.RunElevatedAsync("Enable-NovaVmHyperV.ps1");

        _log.Log(result.Success ? LogLevel.Success : LogLevel.Error, "Enable-NovaVmHyperV.ps1",
            "Activation automatique de Hyper-V : " + (result.Success ? "succes" : "echec"),
            result.Success ? null : (result.Error ?? result.RawError));

        if (!result.Success) return (null, result.Error ?? result.RawError);
        var dto = result.DeserializeData<HyperVSetupResultDto>();
        return dto is null ? (null, "Reponse invalide du script.") : (dto, null);
    }

    public async Task<HostLimits> GetHostLimitsAsync()
    {
        var result = await RunSilentAsync("Get-NovaVmHostMemoryLimits.ps1", "Capacites de l'hote (RAM/CPU)");
        var dto = result.DeserializeData<HostLimitsDto>();
        if (dto is null) return HostLimits.Default;
        return new HostLimits
        {
            TotalPhysicalMb = dto.TotalPhysicalMb,
            MaxVmMemoryMb = dto.MaxVmMemoryMb,
            CpuCores = dto.CpuCores,
            CpuLogicalProcessors = dto.CpuLogicalProcessors,
        };
    }

    // --- Helpers -----------------------------------------------------------

    private Task<VirtualMachine?> RunForVmAsync(
        string script, string actionLabel, params (string Name, string Value)[] parameters) =>
        RunForVmAsync(script, actionLabel, onProgress: null, parameters);

    private async Task<VirtualMachine?> RunForVmAsync(
        string script, string actionLabel, Action<string>? onProgress, params (string Name, string Value)[] parameters)
    {
        var result = await RunAsyncCore(script, actionLabel, silent: false, onProgress, parameters);
        if (!result.Success) return null;

        var dto = result.DeserializeData<VirtualMachineDto>();
        return dto is null ? null : VirtualMachine.FromDto(dto);
    }

    private Task<PowerShellResult> RunAsync(
        string script, string actionLabel, params (string Name, string Value)[] parameters) =>
        RunAsyncCore(script, actionLabel, silent: false, onProgress: null, parameters);

    private Task<PowerShellResult> RunSilentAsync(
        string script, string actionLabel, params (string Name, string Value)[] parameters) =>
        RunAsyncCore(script, actionLabel, silent: true, onProgress: null, parameters);

    private async Task<PowerShellResult> RunAsyncCore(
        string script, string actionLabel, bool silent, Action<string>? onProgress,
        params (string Name, string Value)[] parameters)
    {
        var result = onProgress is null
            ? await _runner.RunAsync(script, parameters)
            : await _runner.RunWithProgressAsync(script, onProgress, parameters);

        if (!silent)
        {
            if (result.Success)
            {
                _log.Log(LogLevel.Success, script, actionLabel + " : succes");
            }
            else
            {
                _log.Log(LogLevel.Error, script, actionLabel + " : echec", result.Error ?? result.RawError);
            }
        }

        return result;
    }
}
