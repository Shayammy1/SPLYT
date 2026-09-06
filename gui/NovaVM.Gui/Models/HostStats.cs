namespace NovaVM.Gui.Models;

public sealed class HostStats
{
    public double CpuUsagePercent { get; init; }
    public double RamUsedGb { get; init; }
    public double RamTotalGb { get; init; }
    public double StorageUsedGb { get; init; }
    public double StorageTotalGb { get; init; }

    public double RamUsagePercent => RamTotalGb <= 0 ? 0 : Math.Round(RamUsedGb / RamTotalGb * 100, 0);
    public double StorageUsagePercent => StorageTotalGb <= 0 ? 0 : Math.Round(StorageUsedGb / StorageTotalGb * 100, 0);

    public static HostStats Empty { get; } = new();
}
