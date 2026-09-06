namespace NovaVM.Gui.Models;

/// <summary>RAM physique reelle de l'hote et limite raisonnable pour une VM (voir
/// Get-NovaHostMemoryInfo dans NovaVm.Common.psm1).</summary>
public sealed class HostMemoryLimits
{
    public long TotalPhysicalMb { get; init; }
    public long MaxVmMemoryMb { get; init; }

    public double TotalPhysicalGb => Math.Round(TotalPhysicalMb / 1024.0, 1);
    public double MaxVmMemoryGb => Math.Round(MaxVmMemoryMb / 1024.0, 1);

    public static HostMemoryLimits Default { get; } = new() { TotalPhysicalMb = 8192, MaxVmMemoryMb = 6144 };
}
