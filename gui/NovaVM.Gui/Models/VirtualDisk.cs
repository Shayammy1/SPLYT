namespace NovaVM.Gui.Models;

public sealed class VirtualDisk
{
    public required string Path { get; init; }
    public double SizeGb { get; init; }
    public double UsedGb { get; init; }
    public string? AttachedVm { get; init; }

    public double UsagePercent => SizeGb <= 0 ? 0 : Math.Round(UsedGb / SizeGb * 100, 0);
}
