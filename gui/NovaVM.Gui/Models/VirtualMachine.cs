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
    private bool _needsBootKeyPress;
    private string _usbBusIds = "";
    private bool _unattendPending;
    private string _unattendStage = "";
    private int _unattendPercent;
    private string? _lastError;

    public string Id { get => _id; set => SetProperty(ref _id, value); }
    public string Name { get => _name; set => SetProperty(ref _name, value); }

    public VmState State
    {
        get => _state;
        set
        {
            if (SetProperty(ref _state, value))
            {
                OnPropertyChanged(nameof(StateDisplay));
                OnPropertyChanged(nameof(StateSortKey));
                OnPropertyChanged(nameof(IsRunning));
            }
        }
    }

    public string StateDisplay => State.ToDisplayString();

    /// <summary>Utilise notamment par la console integree : ouvrir vmconnect sur
    /// une machine eteinte n'afficherait que son propre ecran "l'ordinateur
    /// virtuel est eteint", avec son habillage a lui.</summary>
    public bool IsRunning => State == VmState.Running;

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

    /// <summary>Vrai quand une ISO est montee ET encore premier peripherique de
    /// demarrage : il faut alors passer l'invite firmware "Press any key to boot
    /// from CD or DVD...", que la console fait a la place de l'utilisateur (voir
    /// VmConsoleHost.SendBootKeyBurst).</summary>
    public bool NeedsBootKeyPress { get => _needsBootKeyPress; set => SetProperty(ref _needsBootKeyPress, value); }

    /// <summary>Ports USB reserves a cette VM ("3-3,1-4"). La reservation se pose
    /// machine eteinte ; le rattachement reel suit des que la VM est prete.</summary>
    public string UsbBusIds
    {
        get => _usbBusIds;
        set { if (SetProperty(ref _usbBusIds, value)) OnPropertyChanged(nameof(ReservedUsbBusIds)); }
    }

    /// <summary>La meme liste, decoupee, pour interroger l'appartenance sans
    /// refaire le decoupage a chaque ligne de la liste des peripheriques.</summary>
    public IReadOnlyList<string> ReservedUsbBusIds =>
        UsbBusIds.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    /// <summary>Vrai tant que l'installation automatique de Windows tourne. La VM
    /// est alors entierement cachee : pas de console, pas de flux - il n'y a rien
    /// d'utile a y voir, et un clic de travers pendant l'installation la casse.
    /// Seule la progression ci-dessous est montree.</summary>
    public bool UnattendPending
    {
        get => _unattendPending;
        set
        {
            if (SetProperty(ref _unattendPending, value))
            {
                OnPropertyChanged(nameof(InstallStageLabel));
            }
        }
    }

    /// <summary>Identifiant d'etape ecrit par Watch-NovaVmInstallComplete.ps1 :
    /// traduit ici, parce que les scripts restent en francais par convention.</summary>
    public string UnattendStage
    {
        get => _unattendStage;
        set
        {
            if (SetProperty(ref _unattendStage, value)) OnPropertyChanged(nameof(InstallStageLabel));
        }
    }

    public int UnattendPercent { get => _unattendPercent; set => SetProperty(ref _unattendPercent, value); }

    /// <summary>Libelle de l'etape en cours. Une etape inconnue retombe sur le
    /// libelle generique plutot que d'afficher une cle brute : les identifiants
    /// d'etape viennent d'un script qui peut evoluer sans la GUI.</summary>
    public string InstallStageLabel => UnattendStage switch
    {
        "starting" => Loc.Get("VmList_Install_Stage_Starting"),
        "boot" => Loc.Get("VmList_Install_Stage_Boot"),
        "copy" => Loc.Get("VmList_Install_Stage_Copy"),
        "configure" => Loc.Get("VmList_Install_Stage_Configure"),
        _ => Loc.Get("VmList_Install_Stage_Running"),
    };

    public string? LastError { get => _lastError; set => SetProperty(ref _lastError, value); }

    public bool HasGpuPartition => !string.IsNullOrWhiteSpace(GpuName);

    /// <summary>Cle de tri "les machines actives d'abord" : l'ordre des valeurs de
    /// VmState suit leur cycle de vie, pas l'interet qu'elles presentent pour
    /// l'utilisateur - trier sur l'enum brut ne mettrait donc pas En cours en tete.</summary>
    public int StateSortKey => State switch
    {
        VmState.Running => 0,
        VmState.Starting => 1,
        VmState.Stopping => 2,
        VmState.Saved => 3,
        VmState.Off => 4,
        _ => 5,
    };
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
        NeedsBootKeyPress = dto.NeedsBootKeyPress,
        UsbBusIds = dto.UsbBusIds ?? "",
        UnattendPending = dto.UnattendPending,
        UnattendStage = dto.UnattendStage ?? "",
        UnattendPercent = dto.UnattendPercent,
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
        NeedsBootKeyPress = dto.NeedsBootKeyPress;
        UsbBusIds = dto.UsbBusIds ?? "";
        UnattendPending = dto.UnattendPending;
        UnattendStage = dto.UnattendStage ?? "";
        UnattendPercent = dto.UnattendPercent;
        LastError = dto.LastError;
        OnPropertyChanged(nameof(HasGpuPartition));
        OnPropertyChanged(nameof(MemoryGb));
        OnPropertyChanged(nameof(DisplaySummary));
    }
}
