using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.Models;

/// <summary>
/// Modele observable d'une VM NovaVM, utilise par la GUI. Distinct du DTO JSON
/// (<see cref="VirtualMachineDto"/>) qui reflete le contrat brut des scripts
/// PowerShell : ce modele expose des types "propres" (enum VmState, etc.) et
/// notifie les changements pour que les bindings XAML se mettent a jour apres
/// une action (demarrer/arreter/configurer).
/// </summary>
public sealed class VirtualMachine : ObservableObject
{
    private string _id = "";
    private string _name = "";
    private VmState _state;
    private int _cpu;
    private long _memoryMb;
    private bool _dynamicMemoryEnabled;
    private string? _gpuName;
    private int _gpuVramMb;
    private string _resolution = "1920x1080";
    private int _refreshRateHz = 60;
    private string _diskPath = "";
    private double _diskSizeGb;
    private string? _isoPath;
    private bool _osInstalled;
    private string? _lastError;

    public string Id { get => _id; set => SetProperty(ref _id, value); }
    public string Name { get => _name; set => SetProperty(ref _name, value); }

    public VmState State
    {
        get => _state;
        set
        {
            if (SetProperty(ref _state, value)) OnPropertyChanged(nameof(StateDisplay));
        }
    }

    public string StateDisplay => State.ToDisplayString();

    public int Cpu { get => _cpu; set => SetProperty(ref _cpu, value); }
    public long MemoryMb { get => _memoryMb; set => SetProperty(ref _memoryMb, value); }
    public bool DynamicMemoryEnabled { get => _dynamicMemoryEnabled; set => SetProperty(ref _dynamicMemoryEnabled, value); }
    public string? GpuName { get => _gpuName; set => SetProperty(ref _gpuName, value); }
    public int GpuVramMb { get => _gpuVramMb; set => SetProperty(ref _gpuVramMb, value); }
    public string Resolution { get => _resolution; set => SetProperty(ref _resolution, value); }
    public int RefreshRateHz { get => _refreshRateHz; set => SetProperty(ref _refreshRateHz, value); }
    public string DiskPath { get => _diskPath; set => SetProperty(ref _diskPath, value); }
    public double DiskSizeGb { get => _diskSizeGb; set => SetProperty(ref _diskSizeGb, value); }
    public string? IsoPath { get => _isoPath; set => SetProperty(ref _isoPath, value); }

    /// <summary>Vrai des qu'un Windows a demarre au moins une fois dans cette VM :
    /// c'est ce qui rend le bouton "SPLYT" (configuration en un clic) pertinent.</summary>
    public bool OsInstalled { get => _osInstalled; set => SetProperty(ref _osInstalled, value); }
    public string? LastError { get => _lastError; set => SetProperty(ref _lastError, value); }

    public bool HasGpuPartition => !string.IsNullOrWhiteSpace(GpuName);
    public double MemoryGb => Math.Round(MemoryMb / 1024.0, 1);
    public string DisplaySummary => Loc.Get("Vm_DisplaySummary", Cpu, MemoryGb, Resolution, RefreshRateHz);

    public static VirtualMachine FromDto(VirtualMachineDto dto) => new()
    {
        Id = dto.Id ?? "",
        Name = dto.Name ?? Loc.Get("Vm_Unnamed"),
        State = VmStateParser.Parse(dto.State),
        Cpu = dto.Cpu,
        MemoryMb = dto.MemoryMb,
        DynamicMemoryEnabled = dto.DynamicMemoryEnabled,
        GpuName = dto.GpuName,
        GpuVramMb = dto.GpuVramMb,
        Resolution = string.IsNullOrWhiteSpace(dto.Resolution) ? "1920x1080" : dto.Resolution!,
        RefreshRateHz = dto.Hz == 0 ? 60 : dto.Hz,
        DiskPath = dto.DiskPath ?? "",
        DiskSizeGb = dto.DiskSizeGb,
        IsoPath = dto.IsoPath,
        OsInstalled = dto.OsInstalled,
        LastError = dto.LastError,
    };

    /// <summary>Met a jour ce modele en place a partir d'un DTO frais, pour que les
    /// bindings existants (selection, scroll position...) survivent au refresh.</summary>
    public void UpdateFrom(VirtualMachineDto dto)
    {
        Name = dto.Name ?? Name;
        State = VmStateParser.Parse(dto.State);
        Cpu = dto.Cpu;
        MemoryMb = dto.MemoryMb;
        DynamicMemoryEnabled = dto.DynamicMemoryEnabled;
        GpuName = dto.GpuName;
        GpuVramMb = dto.GpuVramMb;
        Resolution = string.IsNullOrWhiteSpace(dto.Resolution) ? Resolution : dto.Resolution!;
        RefreshRateHz = dto.Hz == 0 ? RefreshRateHz : dto.Hz;
        DiskPath = dto.DiskPath ?? DiskPath;
        DiskSizeGb = dto.DiskSizeGb;
        IsoPath = dto.IsoPath;
        OsInstalled = dto.OsInstalled;
        LastError = dto.LastError;
        OnPropertyChanged(nameof(HasGpuPartition));
        OnPropertyChanged(nameof(MemoryGb));
        OnPropertyChanged(nameof(DisplaySummary));
    }
}
