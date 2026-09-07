namespace NovaVM.Gui.Services.PowerShell;

// DTOs qui refletent exactement le JSON produit par scripts/hyperv/*.ps1
// (voir NovaVm.Common.psm1). PropertyNameCaseInsensitive=true (JsonOptions.Default)
// suffit a mapper le camelCase PowerShell vers le PascalCase C# ci-dessous,
// donc aucun [JsonPropertyName] n'est necessaire tant que les noms ne different
// que par la casse de leur premiere lettre.

public sealed class VirtualMachineDto
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? State { get; set; }
    public int Cpu { get; set; }
    public long MemoryMb { get; set; }
    public bool DynamicMemoryEnabled { get; set; }
    public string? GpuName { get; set; }
    public int GpuVramMb { get; set; }
    public string? Resolution { get; set; }
    public int Hz { get; set; }
    public string? DiskPath { get; set; }

    // double, pas int : la taille reelle d'un VHDX (Get-VHD) n'est pas toujours
    // un nombre entier de Go une fois arrondie a 1 decimale cote PowerShell.
    public double DiskSizeGb { get; set; }

    public string? IsoPath { get; set; }
    public bool NeedsBootKeyPress { get; set; }
    public string? LastError { get; set; }
}

public sealed class HostMemoryLimitsDto
{
    public long TotalPhysicalMb { get; set; }
    public long MaxVmMemoryMb { get; set; }
}

public sealed class HostGpuDto
{
    public string? Name { get; set; }
    public long VramBytes { get; set; }
    public string? DriverVersion { get; set; }
    public bool PartitionSupported { get; set; }
    public string? PartitionCheckError { get; set; }
}

public sealed class GpuDiagnosticsDto
{
    public string? VmName { get; set; }
    public int VmGeneration { get; set; }
    public bool GenerationOk { get; set; }
    public string? HostGpuName { get; set; }
    public string? HostGpuDriverVersion { get; set; }
    public bool HostGpuCompatible { get; set; }
    public string? HostGpuError { get; set; }
    public bool AdapterAttached { get; set; }
    public string? AdapterError { get; set; }
    public long? AdapterMinPartitionVRAM { get; set; }
    public long? AdapterMaxPartitionVRAM { get; set; }
    public long? AdapterOptimalPartitionVRAM { get; set; }
    public string? DriverCheckNote { get; set; }
    public string? IssuesText { get; set; }
    public bool OverallOk { get; set; }
}

public sealed class GpuDriverInstallResultDto
{
    public string? GpuName { get; set; }
    public string? DriverVersion { get; set; }
    public string? ProviderName { get; set; }
    public string? RegistryIndex { get; set; }
    public string? HostDriverStorePath { get; set; }
    public bool PnpAlreadyPresent { get; set; }
    public string? PnpInstalledDriver { get; set; }
    public string? Message { get; set; }
}

public sealed class SunshineInstallResultDto
{
    public int ExitCode { get; set; }
    public bool ServiceFound { get; set; }
    public string? ServiceStatus { get; set; }
    public bool CsrfConfigured { get; set; }
    public string? VmIpAddress { get; set; }
    public string? SunshineWebUiUrl { get; set; }
    public string? Message { get; set; }
}

public sealed class StreamingSetupResultDto
{
    public string? VmName { get; set; }
    public bool MoonlightInstalledOnHost { get; set; }
    public string? SunshineInstallerPath { get; set; }
    public string? NextSteps { get; set; }
    public string? Message { get; set; }
}

public sealed class EnhancedSessionFixResultDto
{
    public int? PreviousValue { get; set; }
    public int NewValue { get; set; }
    public bool AlreadyOff { get; set; }
    public string? Message { get; set; }
}

public sealed class VddDiagnosticsResultDto
{
    public bool VddPresent { get; set; }
    public string? VddStatus { get; set; }
    public int ShutdownCount { get; set; }
    public int LsmErrorCount { get; set; }
    public bool DisableApplied { get; set; }
    public string? DisableResult { get; set; }
    public bool EnableApplied { get; set; }
    public string? EnableResult { get; set; }
    public string? Message { get; set; }
}

public sealed class NvidiaGpuPatchResultDto
{
    public string? GpuName { get; set; }
    public string? PatternUsed { get; set; }
    public string? InfFile { get; set; }
    public string? PnpInstalledDriver { get; set; }
    public string? Message { get; set; }
}

public sealed class HyperVSetupResultDto
{
    public bool EditionSupported { get; set; }
    public bool AlreadyEnabled { get; set; }
    public bool RebootRequired { get; set; }
    public bool AddedToHyperVAdmins { get; set; }
    public string? Message { get; set; }
}

public sealed class WindowsIsoResultDto
{
    public string? IsoPath { get; set; }
    public bool AlreadyCached { get; set; }
    public double SizeGb { get; set; }
    public string? Message { get; set; }
}

public sealed class GamingOptimizationStepDto
{
    public string? Name { get; set; }
    public bool Success { get; set; }
    public string? Detail { get; set; }
}

public sealed class GamingOptimizationResultDto
{
    public List<GamingOptimizationStepDto>? Steps { get; set; }
    public bool RebootRecommended { get; set; }
    public string? Message { get; set; }
}

public sealed class VddInstallResultDto
{
    public bool AlreadyInstalled { get; set; }
    public string? VddStatus { get; set; }
    public string? Message { get; set; }
}

public sealed class DisplayDiagnosticsDto
{
    public string? VmName { get; set; }
    public string? RequestedResolution { get; set; }
    public int RequestedHz { get; set; }
    public int ActualHz { get; set; }
    public bool ActualHzIsReallyEnforced { get; set; }
    public bool HostEnhancedSessionAllowed { get; set; }
    public bool GpuPartitionActive { get; set; }
    public string? DisplayPathLimitation { get; set; }
    public string? Recommendation { get; set; }
}

public sealed class HostStatsDto
{
    public double CpuUsagePercent { get; set; }
    public double RamUsedGb { get; set; }
    public double RamTotalGb { get; set; }
    public double StorageUsedGb { get; set; }
    public double StorageTotalGb { get; set; }
}

public sealed class VirtualDiskDto
{
    public string? Path { get; set; }
    public double SizeGb { get; set; }
    public double UsedGb { get; set; }
    public string? AttachedVm { get; set; }
}

public sealed class DiagnosticsDto
{
    public bool HyperVModuleInstalled { get; set; }
    public string? HyperVModuleVersion { get; set; }
    public bool CanListVms { get; set; }
    public string? VmPermissionError { get; set; }
    public bool CanListPartitionableGpus { get; set; }
    public string? GpuPermissionError { get; set; }
    public bool IsElevated { get; set; }
}
