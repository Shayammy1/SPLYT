namespace NovaVM.Gui.Models;

public sealed class HostGpu
{
    public required string Name { get; init; }
    public long VramBytes { get; init; }
    public string? DriverVersion { get; init; }
    public bool PartitionSupported { get; init; }
    public string? PartitionCheckError { get; init; }
    public List<string> AssignedVmNames { get; init; } = new();

    public double VramGb => Math.Round(VramBytes / 1024.0 / 1024.0 / 1024.0, 1);
}
