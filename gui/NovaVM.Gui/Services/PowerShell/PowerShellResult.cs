using System.Text.Json;

namespace NovaVM.Gui.Services.PowerShell;

public static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNameCaseInsensitive = true,
    };
}

/// <summary>
/// Resultat obtenu apres appel a un script scripts/hyperv/*.ps1, a partir de
/// l'enveloppe JSON standard { success, data, error } (voir NovaVm.Common.psm1).
/// </summary>
public sealed class PowerShellResult
{
    public bool Success { get; init; }
    public JsonElement? Data { get; init; }
    public string? Error { get; init; }
    public string RawOutput { get; init; } = "";
    public string RawError { get; init; } = "";
    public int ExitCode { get; init; }

    public T? DeserializeData<T>()
    {
        if (Data is null) return default;
        return Data.Value.Deserialize<T>(JsonOptions.Default);
    }

    public static PowerShellResult Failed(string error) => new()
    {
        Success = false,
        Error = error,
    };

    /// <summary>
    /// Cherche, en partant de la derniere ligne, la premiere ligne de stdout qui
    /// est un objet JSON valide portant "success" : c'est la ligne ecrite par
    /// Write-NovaResult. On part de la fin pour tolerer d'eventuelles lignes de
    /// diagnostic (Write-Verbose, etc.) qui precederaient le resultat final.
    /// </summary>
    public static PowerShellResult Parse(string stdout, string stderr, int exitCode)
    {
        var lines = stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var line = lines[i].Trim().TrimEnd('\r');
            if (line.Length == 0 || line[0] != '{') continue;

            try
            {
                using var doc = JsonDocument.Parse(line);
                var root = doc.RootElement;
                if (!root.TryGetProperty("success", out var successProp)) continue;

                var success = successProp.GetBoolean();
                string? error = root.TryGetProperty("error", out var errorProp) &&
                                 errorProp.ValueKind != JsonValueKind.Null
                    ? errorProp.GetString()
                    : null;
                JsonElement? data = root.TryGetProperty("data", out var dataProp) &&
                                     dataProp.ValueKind != JsonValueKind.Null
                    ? dataProp.Clone()
                    : null;

                return new PowerShellResult
                {
                    Success = success,
                    Data = data,
                    Error = error,
                    RawOutput = stdout,
                    RawError = stderr,
                    ExitCode = exitCode,
                };
            }
            catch (JsonException)
            {
                // Cette ligne n'est pas notre JSON de resultat : on continue de remonter.
            }
        }

        var message = !string.IsNullOrWhiteSpace(stderr)
            ? stderr.Trim()
            : $"Sortie inattendue du script PowerShell (code de sortie {exitCode}).";

        return new PowerShellResult
        {
            Success = false,
            Error = message,
            RawOutput = stdout,
            RawError = stderr,
            ExitCode = exitCode,
        };
    }
}
