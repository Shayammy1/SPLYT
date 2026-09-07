namespace NovaVM.Gui.Models;

/// <summary>Capacites reelles de l'hote (RAM et processeur) et limites raisonnables
/// pour une VM, telles que mesurees par Get-NovaHostMemoryInfo (NovaVm.Common.psm1).
/// Sert a borner les curseurs vCPU/RAM de la GUI sur du materiel reel plutot que sur
/// des maximums arbitraires.</summary>
public sealed class HostLimits
{
    public long TotalPhysicalMb { get; init; }
    public long MaxVmMemoryMb { get; init; }

    /// <summary>Coeurs physiques, tous sockets confondus.</summary>
    public int CpuCores { get; init; }

    /// <summary>Processeurs logiques (threads), tous sockets confondus.</summary>
    public int CpuLogicalProcessors { get; init; }

    public double TotalPhysicalGb => Math.Round(TotalPhysicalMb / 1024.0, 1);
    public double MaxVmMemoryGb => Math.Round(MaxVmMemoryMb / 1024.0, 1);

    /// <summary>Borne haute du curseur vCPU : les coeurs PHYSIQUES, pas les
    /// processeurs logiques. Hyper-V accepterait jusqu'aux processeurs logiques,
    /// mais au-dela des coeurs physiques les vCPU se partagent les memes coeurs -
    /// contre-productif pour l'usage vise (du jeu dans la VM), et proposer 16 vCPU
    /// sur un processeur 8 coeurs est trompeur.</summary>
    public int MaxVmCpu => Math.Max(1, CpuCores);

    public static HostLimits Default { get; } = new()
    {
        TotalPhysicalMb = 8192,
        MaxVmMemoryMb = 6144,
        CpuCores = 4,
        CpuLogicalProcessors = 8,
    };
}
