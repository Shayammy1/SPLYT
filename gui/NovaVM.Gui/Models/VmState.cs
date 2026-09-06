using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.Models;

/// <summary>
/// Etat d'une machine virtuelle NovaVM. Les valeurs correspondent (en texte)
/// a celles renvoyees par les scripts PowerShell du backend (voir
/// scripts/hyperv/NovaVm.Common.psm1) ; la conversion se fait via
/// <see cref="VmStateParser"/> plutot que via un enum JSON strict, pour rester
/// tolerant si Hyper-V renvoie un jour un etat que nous n'avons pas encore mappe.
/// </summary>
public enum VmState
{
    Off,
    Running,
    Starting,
    Stopping,
    Saved,
    Error,
    Unknown,
}

public static class VmStateParser
{
    public static VmState Parse(string? raw) => raw?.Trim().ToLowerInvariant() switch
    {
        "off" => VmState.Off,
        "running" => VmState.Running,
        "starting" => VmState.Starting,
        "stopping" => VmState.Stopping,
        "saved" => VmState.Saved,
        "error" => VmState.Error,
        _ => VmState.Unknown,
    };

    public static string ToDisplayString(this VmState state) => state switch
    {
        VmState.Off => Loc.Get("VmState_Off"),
        VmState.Running => Loc.Get("VmState_Running"),
        VmState.Starting => Loc.Get("VmState_Starting"),
        VmState.Stopping => Loc.Get("VmState_Stopping"),
        VmState.Saved => Loc.Get("VmState_Saved"),
        VmState.Error => Loc.Get("VmState_Error"),
        _ => Loc.Get("VmState_Unknown"),
    };
}
