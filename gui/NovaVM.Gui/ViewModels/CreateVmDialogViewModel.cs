using System.Collections.ObjectModel;
using System.IO;
using System.Windows.Threading;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>Modele de l'assistant "Creer une VM" (fenetre modale CreateVmDialog).</summary>
public sealed class CreateVmDialogViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private readonly HostLimits _hostLimits;
    private readonly IReadOnlyList<HostGpu> _hostGpus;
    private readonly Dispatcher _uiDispatcher;

    private string _name = "";
    private int _cpu = 4;
    private double _memoryGb;
    private int _diskSizeGb = 80;
    private string _selectedGpu = AutoGpuOption;
    private int _gpuVramMb = 4096;
    private string? _isoPath;
    private bool _dynamicMemoryEnabled;
    private string? _currentStep;
    private double _progressPercent;
    private bool _isDownloadingIso;
    private string? _isoDownloadStatusText;

    public static readonly string AutoGpuOption = Loc.Get("CreateVm_AutoGpu");
    public static readonly string NoGpuOption = Loc.Get("Vm_NoGpuOption");

    // Doit correspondre exactement, dans l'ordre, aux Write-NovaProgress de
    // scripts/hyperv/New-NovaVm.ps1 : chaque etape reellement franchie fait
    // avancer la barre d'1/7e, jamais une simulation basee sur le temps. Reste en
    // francais deliberement (comme tous les messages generes par les scripts
    // PowerShell - hors perimetre de la traduction, voir Loc) : ce tableau doit
    // matcher EXACTEMENT le texte que le script ecrit, pas une version traduite.
    private static readonly string[] CreationSteps =
    {
        "Validation des parametres",
        "Creation de la VM",
        "Creation du disque virtuel",
        "Montage de l'image ISO",
        "Configuration du processeur et de la memoire",
        "Configuration du demarrage",
        "Finalisation",
    };

    public CreateVmDialogViewModel(NovaVmService vmService, IReadOnlyList<HostGpu> hostGpus, HostLimits hostLimits)
    {
        _vmService = vmService;
        _hostLimits = hostLimits;
        _hostGpus = hostGpus;
        _uiDispatcher = Dispatcher.CurrentDispatcher;

        AvailableGpus.Add(AutoGpuOption);
        foreach (var gpu in hostGpus.Where(g => g.PartitionSupported)) AvailableGpus.Add(gpu.Name);
        AvailableGpus.Add(NoGpuOption);

        // Heuristique "auto" : le premier GPU partitionnable detecte (souvent le seul).
        _autoSelectedGpu = hostGpus.FirstOrDefault(g => g.PartitionSupported)?.Name;

        // Valeur par defaut adaptee a la machine : jamais plus que la moitie de
        // la limite raisonnable, jamais plus que la limite elle-meme.
        _memoryGb = Math.Min(8, Math.Max(1, MaxMemoryGb / 2));
        _cpu = Math.Min(_cpu, MaxCpu);
        _gpuVramMb = Math.Min(_gpuVramMb, MaxGpuVramMb);

        // Une ISO Windows 11 deja telechargee (creation de VM precedente, ou telechargement
        // lance depuis cette meme fenetre) est reutilisee automatiquement : l'utilisateur n'a
        // besoin de la telecharger/selectionner qu'une seule fois au total.
        if (_vmService.IsWindowsIsoCached())
        {
            _isoPath = NovaVmService.DefaultWindowsIsoPath;
        }

        CreateCommand = new AsyncRelayCommand(CreateAsync, () => !string.IsNullOrWhiteSpace(Name));
        CancelCommand = new RelayCommand(() => Cancelled?.Invoke(this, EventArgs.Empty));
        BrowseIsoCommand = new RelayCommand(BrowseIso);
        DownloadWindowsIsoCommand = new AsyncRelayCommand(DownloadWindowsIsoAsync, () => !IsDownloadingIso);
    }

    private readonly string? _autoSelectedGpu;

    public ObservableCollection<string> AvailableGpus { get; } = new();

    public double TotalPhysicalRamGb => _hostLimits.TotalPhysicalGb;
    public double MaxMemoryGb => _hostLimits.MaxVmMemoryGb;

    /// <summary>Borne haute reelle du curseur vCPU (coeurs physiques de cet hote) -
    /// voir HostLimits.MaxVmCpu pour le pourquoi des coeurs plutot que des threads.</summary>
    public int MaxCpu => _hostLimits.MaxVmCpu;
    public int CpuCores => _hostLimits.CpuCores;
    public int CpuLogicalProcessors => _hostLimits.CpuLogicalProcessors;

    public string Name { get => _name; set => SetProperty(ref _name, value); }
    public int Cpu { get => _cpu; set => SetProperty(ref _cpu, value); }

    public double MemoryGb
    {
        get => _memoryGb;
        set
        {
            if (SetProperty(ref _memoryGb, value)) OnPropertyChanged(nameof(ShowRamWarning));
        }
    }

    /// <summary>Avertissement (pas un blocage : le curseur est deja borne par MaxMemoryGb)
    /// quand on approche de la totalite de la RAM physique de la machine.</summary>
    public bool ShowRamWarning => MemoryGb > TotalPhysicalRamGb * 0.75;

    public int DiskSizeGb { get => _diskSizeGb; set => SetProperty(ref _diskSizeGb, value); }

    /// <summary>Decoche par defaut : la RAM configuree reste toujours entierement
    /// assignee a la VM (comportement Hyper-V par defaut). Cochee, Hyper-V n'assigne
    /// que la RAM reellement utilisee (jusqu'a ce meme montant), et peut la reprendre
    /// quand la VM est peu chargee.</summary>
    public bool DynamicMemoryEnabled { get => _dynamicMemoryEnabled; set => SetProperty(ref _dynamicMemoryEnabled, value); }

    /// <summary>Libelle de l'etape en cours (une des CreationSteps), ou null hors creation.</summary>
    public string? CurrentStep { get => _currentStep; private set => SetProperty(ref _currentStep, value); }

    /// <summary>Avancement reel (0-100), calcule a partir de l'etape reellement
    /// atteinte par le script (voir OnCreationProgress) - jamais simule par le temps.</summary>
    public double ProgressPercent { get => _progressPercent; private set => SetProperty(ref _progressPercent, value); }

    public string SelectedGpu
    {
        get => _selectedGpu;
        set
        {
            if (SetProperty(ref _selectedGpu, value))
            {
                OnPropertyChanged(nameof(HasDedicatedVram));
                OnPropertyChanged(nameof(NoDedicatedVram));
                OnPropertyChanged(nameof(MaxGpuVramMb));
                if (GpuVramMb > MaxGpuVramMb) GpuVramMb = MaxGpuVramMb;
            }
        }
    }

    public int GpuVramMb { get => _gpuVramMb; set => SetProperty(ref _gpuVramMb, value); }

    /// <summary>GPU hote reellement vise par la selection courante ("Auto" resolu,
    /// null pour "Aucun" ou un nom inconnu).</summary>
    private HostGpu? SelectedHostGpu
    {
        get
        {
            if (SelectedGpu == NoGpuOption) return null;
            var name = SelectedGpu == AutoGpuOption ? _autoSelectedGpu : SelectedGpu;
            return name is null ? null : _hostGpus.FirstOrDefault(g => g.Name == name);
        }
    }

    /// <summary>Faux pour un GPU integre (aucune VRAM dediee : il puise dans la RAM
    /// systeme, et le registre du pilote ne rapporte alors aucune taille) - dans ce
    /// cas le curseur "VRAM allouee" n'a rien de reel a doser et reste desactive,
    /// plutot que de laisser croire a un reglage qui ne veut rien dire.</summary>
    public bool HasDedicatedVram => (SelectedHostGpu?.VramBytes ?? 0) > 0;

    /// <summary>Inverse de HasDedicatedVram (voir NoIsoYet pour la meme raison :
    /// BoolToVisibilityConverter ne sait pas inverser).</summary>
    public bool NoDedicatedVram => !HasDedicatedVram;

    /// <summary>Plafond du curseur VRAM : la VRAM reelle du GPU selectionne, jamais
    /// une valeur arbitraire superieure a ce que la carte possede.</summary>
    public int MaxGpuVramMb
    {
        get
        {
            var vramBytes = SelectedHostGpu?.VramBytes ?? 0;
            if (vramBytes <= 0) return 512;
            return Math.Max(512, (int)(vramBytes / 1024 / 1024));
        }
    }
    public string? IsoPath
    {
        get => _isoPath;
        set
        {
            if (SetProperty(ref _isoPath, value))
            {
                OnPropertyChanged(nameof(HasIso));
                OnPropertyChanged(nameof(NoIsoYet));
            }
        }
    }

    /// <summary>Vrai des qu'une image ISO (peu importe laquelle - telechargee
    /// automatiquement ou choisie via "Parcourir") est prete a etre utilisee.</summary>
    public bool HasIso => !string.IsNullOrWhiteSpace(IsoPath);

    /// <summary>Inverse de HasIso : evite de devoir gerer un ConverterParameter="Invert"
    /// sur BoolToVisibilityConverter (le BooleanToVisibilityConverter standard WPF ne le
    /// supporte pas, contrairement a NullToVisibilityConverter).</summary>
    public bool NoIsoYet => !HasIso;

    public bool IsDownloadingIso { get => _isDownloadingIso; private set => SetProperty(ref _isDownloadingIso, value); }

    /// <summary>Texte de progression brut du telechargement (pourcentage + Go), pas
    /// un libelle d'etape fixe comme CurrentStep pour la creation de VM elle-meme.</summary>
    public string? IsoDownloadStatusText { get => _isoDownloadStatusText; private set => SetProperty(ref _isoDownloadStatusText, value); }

    /// <summary>Cablee par la vue (code-behind) : ouvre le vrai selecteur de fichier
    /// Windows et retourne le chemin choisi, ou null si annule. Le ViewModel ne
    /// depend ainsi pas directement de Microsoft.Win32.OpenFileDialog.</summary>
    public Func<string?>? BrowseForIsoFile { get; set; }

    public AsyncRelayCommand CreateCommand { get; }
    public RelayCommand CancelCommand { get; }
    public RelayCommand BrowseIsoCommand { get; }
    public AsyncRelayCommand DownloadWindowsIsoCommand { get; }

    public VirtualMachine? CreatedVm { get; private set; }
    public event EventHandler? Created;
    public event EventHandler? Cancelled;

    private void BrowseIso()
    {
        var path = BrowseForIsoFile?.Invoke();
        if (string.IsNullOrWhiteSpace(path)) return;

        if (!File.Exists(path))
        {
            ErrorMessage = Loc.Get("CreateVm_IsoNotFound", path);
            return;
        }

        ErrorMessage = null;
        IsoPath = path;
    }

    private async Task DownloadWindowsIsoAsync()
    {
        ErrorMessage = null;
        IsoDownloadStatusText = Loc.Get("CreateVm_DownloadPreparing");
        IsDownloadingIso = true;
        DownloadWindowsIsoCommand.RaiseCanExecuteChanged();
        try
        {
            var (result, error) = await _vmService.DownloadWindowsIsoAsync(OnIsoDownloadProgress);
            if (result is null)
            {
                ErrorMessage = error ?? Loc.Get("CreateVm_IsoDownloadFailed");
                IsoDownloadStatusText = null;
                return;
            }

            IsoPath = result.IsoPath;
            IsoDownloadStatusText = result.Message;
        }
        finally
        {
            IsDownloadingIso = false;
            DownloadWindowsIsoCommand.RaiseCanExecuteChanged();
        }
    }

    /// <summary>Appele depuis le thread qui lit stdout du script (pas le thread UI) :
    /// on doit repasser par le Dispatcher avant de toucher des proprietes liees a des
    /// elements WPF - voir OnCreationProgress pour la meme contrainte.</summary>
    private void OnIsoDownloadProgress(string step)
    {
        _uiDispatcher.BeginInvoke(() => { IsoDownloadStatusText = step; });
    }

    private async Task CreateAsync()
    {
        CurrentStep = null;
        ProgressPercent = 0;

        await RunBusyAsync(async () =>
        {
            CurrentStep = CreationSteps[0];

            if (!string.IsNullOrWhiteSpace(IsoPath) && !File.Exists(IsoPath))
            {
                ErrorMessage = Loc.Get("CreateVm_IsoNotFound", IsoPath);
                return;
            }

            if (MemoryGb > MaxMemoryGb)
            {
                ErrorMessage = Loc.Get("Vm_RamLimitExceeded", MemoryGb, MaxMemoryGb);
                return;
            }

            // AutoGpuOption/NoGpuOption sont maintenant des chaines traduites (static
            // readonly, pas const) : un pattern switch sur des constantes ne compile
            // plus contre elles, d'ou ces comparaisons explicites.
            string? gpuName;
            if (SelectedGpu == AutoGpuOption) gpuName = _autoSelectedGpu;
            else if (SelectedGpu == NoGpuOption) gpuName = null;
            else gpuName = SelectedGpu;

            var (vm, error) = await _vmService.CreateVmAsync(
                Name, Cpu, (long)(MemoryGb * 1024), DiskSizeGb,
                gpuName, gpuName is null ? 0 : GpuVramMb, IsoPath,
                dynamicMemoryEnabled: DynamicMemoryEnabled, onProgress: OnCreationProgress);

            if (vm is null)
            {
                ErrorMessage = error ?? Loc.Get("CreateVm_CreationFailed");
                return;
            }

            ProgressPercent = 100;
            CreatedVm = vm;
            Created?.Invoke(this, EventArgs.Empty);
        });
    }

    /// <summary>Appele par NovaVmService/PowerShellRunner depuis le thread qui lit
    /// stdout du script (pas le thread UI) : on doit repasser par le Dispatcher
    /// avant de toucher des proprietes liees a des elements WPF.</summary>
    private void OnCreationProgress(string step)
    {
        _uiDispatcher.BeginInvoke(() =>
        {
            CurrentStep = step;
            var index = Array.IndexOf(CreationSteps, step);
            if (index >= 0) ProgressPercent = (index + 1) * 100.0 / CreationSteps.Length;
        });
    }
}
