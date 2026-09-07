using System.Collections.ObjectModel;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

public sealed class VmListViewModel : ViewModelBase
{
    public static readonly string NoGpuLabel = Loc.Get("Vm_NoGpuOption");

    private readonly NovaVmService _vmService;
    private VirtualMachine? _selectedVm;
    private HostLimits _hostLimits = HostLimits.Default;

    private int _editCpu;
    private double _editMemoryGb;
    private bool _editDynamicMemoryEnabled;
    private string? _editGpuName;
    private int _editGpuVramMb;
    private string? _gpuDiagnosticsSummary;
    private string? _displayDiagnosticsSummary;
    private string _vddUsername = "";
    private bool _vddRememberCredentials;
    private string? _vddResultText;
    private string _gamingUsername = "";
    private bool _gamingRememberCredentials;
    private string? _gamingResultText;
    private string? _nvidiaDriverInstallerPath;
    private string? _nvidiaPatchResultText;
    private IReadOnlyList<HostGpu> _hostGpus = Array.Empty<HostGpu>();
    private bool _isInstallingGpuDriver;
    private string? _gpuDriverInstallStep;

    public VmListViewModel(NovaVmService vmService)
    {
        _vmService = vmService;

        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        OpenCreateVmDialogCommand = new RelayCommand(() => CreateVmRequested?.Invoke(this, EventArgs.Empty));
        StartCommand = new AsyncRelayCommand(() => ChangeStateAsync(_vmService.StartVmAsync), () => SelectedVm is { State: VmState.Off or VmState.Saved or VmState.Error });
        StopCommand = new RelayCommand(AskHowToStop, () => SelectedVm is { State: VmState.Running });
        DeleteCommand = new RelayCommand(AskDeleteConfirmation, () => SelectedVm is not null);
        SaveResourcesCommand = new AsyncRelayCommand(SaveResourcesAsync, () => SelectedVm is not null);
        SaveGpuCommand = new AsyncRelayCommand(SaveGpuAsync, () => SelectedVm is not null);
        RunGpuDiagnosticsCommand = new AsyncRelayCommand(RunGpuDiagnosticsAsync, () => SelectedVm is not null);
        InstallGpuDriverCommand = new AsyncRelayCommand(InstallGpuDriverAsync,
            () => SelectedVm is not null && !string.IsNullOrWhiteSpace(EditGpuName));
        RunDisplayDiagnosticsCommand = new AsyncRelayCommand(RunDisplayDiagnosticsAsync, () => SelectedVm is not null);
        OpenSunshineInstallDialogCommand = new RelayCommand(
            () => { if (SelectedVm is not null) SunshineInstallRequested?.Invoke(this, SelectedVm.Name); },
            () => SelectedVm is { State: VmState.Running });
        OpenEnhancedSessionFixDialogCommand = new RelayCommand(
            () => { if (SelectedVm is not null) EnhancedSessionFixRequested?.Invoke(this, SelectedVm.Name); },
            () => SelectedVm is { State: VmState.Running });
        VddDiagnoseCommand = new AsyncRelayCommand(() => VddRunAsync(),
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(VddUsername));
        VddEnableCommand = new AsyncRelayCommand(() => VddRunAsync(enable: true),
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(VddUsername));
        VddDisableCommand = new AsyncRelayCommand(() => VddRunAsync(disable: true),
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(VddUsername));
        VddInstallCommand = new AsyncRelayCommand(VddInstallAsync,
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(VddUsername));
        GamingOptimizePerformanceCommand = new AsyncRelayCommand(() => GamingOptimizeAsync(performance: true, privacy: false),
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(GamingUsername));
        GamingOptimizePrivacyCommand = new AsyncRelayCommand(() => GamingOptimizeAsync(performance: false, privacy: true),
            () => SelectedVm is { State: VmState.Running } && !string.IsNullOrWhiteSpace(GamingUsername));
        BrowseNvidiaDriverCommand = new RelayCommand(BrowseNvidiaDriver);
        PatchNvidiaGpuDriverCommand = new AsyncRelayCommand(PatchNvidiaGpuDriverAsync,
            () => SelectedVm is { State: VmState.Off } && !string.IsNullOrWhiteSpace(EditGpuName) && !string.IsNullOrWhiteSpace(NvidiaDriverInstallerPath));

        _ = LoadAsync();
    }

    public ObservableCollection<VirtualMachine> Vms { get; } = new();
    public ObservableCollection<string> AvailableGpus { get; } = new();
    public ObservableCollection<string> GpuDropdownOptions { get; } = new();

    public VirtualMachine? SelectedVm
    {
        get => _selectedVm;
        set
        {
            if (SetProperty(ref _selectedVm, value))
            {
                LoadEditFieldsFromSelection();
                RaiseAllCanExecuteChanged();
            }
        }
    }

    // --- Champs "en edition" pour le panneau de detail (valides via un bouton
    // Enregistrer explicite, pour ne pas relancer PowerShell a chaque tick de slider). --

    public int EditCpu { get => _editCpu; set => SetProperty(ref _editCpu, value); }

    public double EditMemoryGb
    {
        get => _editMemoryGb;
        set
        {
            if (SetProperty(ref _editMemoryGb, value)) OnPropertyChanged(nameof(ShowRamWarning));
        }
    }

    public double TotalPhysicalRamGb => _hostLimits.TotalPhysicalGb;
    public double MaxMemoryGb => _hostLimits.MaxVmMemoryGb;
    public bool ShowRamWarning => EditMemoryGb > TotalPhysicalRamGb * 0.75;

    /// <summary>Borne haute reelle du curseur vCPU - voir HostLimits.MaxVmCpu.</summary>
    public int MaxCpu => _hostLimits.MaxVmCpu;
    public int CpuCores => _hostLimits.CpuCores;
    public int CpuLogicalProcessors => _hostLimits.CpuLogicalProcessors;

    /// <summary>Decoche par defaut : la RAM configuree reste toujours entierement
    /// assignee a la VM. Cochee, Hyper-V n'assigne que la RAM reellement utilisee
    /// (jusqu'a EditMemoryGb), et peut la reprendre quand la VM est peu chargee.</summary>
    public bool EditDynamicMemoryEnabled { get => _editDynamicMemoryEnabled; set => SetProperty(ref _editDynamicMemoryEnabled, value); }

    public string? EditGpuName
    {
        get => _editGpuName;
        set
        {
            if (SetProperty(ref _editGpuName, value))
            {
                OnPropertyChanged(nameof(EditGpuSelection));
                OnPropertyChanged(nameof(IsNvidiaGpuSelected));
                OnPropertyChanged(nameof(HasDedicatedVram));
                OnPropertyChanged(nameof(NoDedicatedVram));
                OnPropertyChanged(nameof(MaxGpuVramMb));
                if (EditGpuVramMb > MaxGpuVramMb) EditGpuVramMb = MaxGpuVramMb;
                InstallGpuDriverCommand.RaiseCanExecuteChanged();
                PatchNvidiaGpuDriverCommand.RaiseCanExecuteChanged();
            }
        }
    }

    /// <summary>Determine si le GPU-P configure est un GPU NVIDIA (recherche simple sur
    /// le nom) : n'affiche le panneau "Bidouille NVIDIA" que si pertinent, plutot que de
    /// distraire les utilisateurs AMD/Intel avec une fonctionnalite qui ne les concerne pas.</summary>
    public bool IsNvidiaGpuSelected => !string.IsNullOrWhiteSpace(EditGpuName) &&
        System.Text.RegularExpressions.Regex.IsMatch(EditGpuName, "(?i)nvidia|geforce|rtx|gtx|quadro");

    /// <summary>Adapte EditGpuName (nullable) pour un ComboBox dont les items sont
    /// toujours des chaines non nulles (NoGpuLabel represente "pas de GPU-P").</summary>
    public string EditGpuSelection
    {
        get => EditGpuName ?? NoGpuLabel;
        set => EditGpuName = value == NoGpuLabel ? null : value;
    }

    public int EditGpuVramMb { get => _editGpuVramMb; set => SetProperty(ref _editGpuVramMb, value); }

    /// <summary>GPU hote correspondant a EditGpuName (null si "Aucun" ou introuvable).</summary>
    private HostGpu? SelectedHostGpu =>
        string.IsNullOrWhiteSpace(EditGpuName) ? null : _hostGpus.FirstOrDefault(g => g.Name == EditGpuName);

    /// <summary>Faux pour un GPU integre (aucune VRAM dediee, il puise dans la RAM
    /// systeme) : le curseur "VRAM allouee" n'a alors rien de reel a doser et reste
    /// desactive - voir la meme propriete dans CreateVmDialogViewModel.</summary>
    public bool HasDedicatedVram => (SelectedHostGpu?.VramBytes ?? 0) > 0;
    public bool NoDedicatedVram => !HasDedicatedVram;

    /// <summary>Plafond du curseur VRAM : la VRAM reelle du GPU selectionne.</summary>
    public int MaxGpuVramMb
    {
        get
        {
            var vramBytes = SelectedHostGpu?.VramBytes ?? 0;
            if (vramBytes <= 0) return 512;
            return Math.Max(512, (int)(vramBytes / 1024 / 1024));
        }
    }

    /// <summary>Vrai pendant toute la preparation du pilote GPU-P (plusieurs minutes :
    /// la copie du magasin de pilotes represente plusieurs Go) - alimente une barre de
    /// progression reelle, alimentee par les etapes du script.</summary>
    public bool IsInstallingGpuDriver { get => _isInstallingGpuDriver; private set => SetProperty(ref _isInstallingGpuDriver, value); }

    /// <summary>Libelle de l'etape en cours de Install-NovaVmGpuDriver.ps1 (voir
    /// Write-NovaProgress), ou null hors installation.</summary>
    public string? GpuDriverInstallStep { get => _gpuDriverInstallStep; private set => SetProperty(ref _gpuDriverInstallStep, value); }

    /// <summary>Texte du dernier diagnostic GPU-P (voir RunGpuDiagnosticsCommand),
    /// ou null tant qu'aucun diagnostic n'a ete lance pour la VM selectionnee.</summary>
    public string? GpuDiagnosticsSummary { get => _gpuDiagnosticsSummary; private set => SetProperty(ref _gpuDiagnosticsSummary, value); }

    /// <summary>Texte du dernier diagnostic d'affichage/Hz (voir RunDisplayDiagnosticsCommand).</summary>
    public string? DisplayDiagnosticsSummary { get => _displayDiagnosticsSummary; private set => SetProperty(ref _displayDiagnosticsSummary, value); }

    // --- Bidouille NVIDIA non officielle (voir Install-NovaVmNvidiaPatchedDriver.ps1) ---

    public string? NvidiaDriverInstallerPath { get => _nvidiaDriverInstallerPath; private set => SetProperty(ref _nvidiaDriverInstallerPath, value); }
    public string? NvidiaPatchResultText { get => _nvidiaPatchResultText; private set => SetProperty(ref _nvidiaPatchResultText, value); }

    /// <summary>Cablee par la vue (code-behind) : ouvre le vrai selecteur de fichier
    /// Windows pour l'installeur .exe NVIDIA et retourne le chemin choisi, ou null si
    /// annule.</summary>
    public Func<string?>? BrowseForNvidiaDriverFile { get; set; }

    // --- Onglet "Virtual Display Driver" : identifiants de la VM (memorisables
    // via le Gestionnaire d'identifiants Windows, voir VmCredentialStore), et
    // resolution/frequence a rendre disponible pour VDD. ---

    public string VddUsername
    {
        get => _vddUsername;
        set
        {
            if (SetProperty(ref _vddUsername, value))
            {
                VddDiagnoseCommand.RaiseCanExecuteChanged();
                VddEnableCommand.RaiseCanExecuteChanged();
                VddDisableCommand.RaiseCanExecuteChanged();
                VddInstallCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public bool VddRememberCredentials { get => _vddRememberCredentials; set => SetProperty(ref _vddRememberCredentials, value); }
    public string? VddResultText { get => _vddResultText; private set => SetProperty(ref _vddResultText, value); }

    /// <summary>Mot de passe VDD recharge depuis le Gestionnaire d'identifiants Windows -
    /// applique une seule fois par la vue (code-behind) au chargement de la VM.</summary>
    public string? VddInitialPassword { get; private set; }

    /// <summary>Cablee par la vue (code-behind) : lit le PasswordBox de l'onglet VDD.
    /// WPF n'expose jamais PasswordBox.Password comme DependencyProperty (choix de
    /// securite delibere) : impossible de le lier via {Binding}.</summary>
    public Func<string>? VddGetPassword { get; set; }

    // --- Onglet "Optimisations gaming" (page Ressources) : reglages Windows
    // courants (performances / vie privee) appliques via PowerShell Direct.
    // Toutes les VMs geres par SPLYT etant des VM Windows (WHP/Hyper-V), ce
    // panneau est deja implicitement limite aux VM Windows par le fait qu'il
    // n'apparait que dans le panneau de detail d'une VM selectionnee (voir
    // le Visibility sur SelectedVm autour du TabControl dans VmListView.xaml). --

    public string GamingUsername
    {
        get => _gamingUsername;
        set
        {
            if (SetProperty(ref _gamingUsername, value))
            {
                GamingOptimizePerformanceCommand.RaiseCanExecuteChanged();
                GamingOptimizePrivacyCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public bool GamingRememberCredentials { get => _gamingRememberCredentials; set => SetProperty(ref _gamingRememberCredentials, value); }
    public string? GamingResultText { get => _gamingResultText; private set => SetProperty(ref _gamingResultText, value); }

    /// <summary>Mot de passe "Optimisations gaming" recharge depuis le Gestionnaire
    /// d'identifiants Windows - applique une seule fois par la vue (code-behind) au
    /// chargement de la VM.</summary>
    public string? GamingInitialPassword { get; private set; }

    /// <summary>Cablee par la vue (code-behind) : lit le PasswordBox de l'onglet
    /// "Optimisations gaming".</summary>
    public Func<string>? GamingGetPassword { get; set; }

    public AsyncRelayCommand RefreshCommand { get; }
    public RelayCommand OpenCreateVmDialogCommand { get; }
    public AsyncRelayCommand StartCommand { get; }

    /// <summary>N'arrete pas directement : demande d'abord LEQUEL des deux arrets
    /// (classique ou force) l'utilisateur veut, via une boite de confirmation - les
    /// deux boutons distincts d'avant ne disaient pas assez clairement ce qu'ils
    /// faisaient et l'arret force etait a un clic de distance sans avertissement.</summary>
    public RelayCommand StopCommand { get; }

    /// <summary>Demande confirmation avant de supprimer : l'operation efface aussi le
    /// disque virtuel et n'est pas annulable.</summary>
    public RelayCommand DeleteCommand { get; }
    public AsyncRelayCommand SaveResourcesCommand { get; }
    public AsyncRelayCommand SaveGpuCommand { get; }
    public AsyncRelayCommand RunGpuDiagnosticsCommand { get; }
    public AsyncRelayCommand InstallGpuDriverCommand { get; }
    public AsyncRelayCommand RunDisplayDiagnosticsCommand { get; }
    public RelayCommand OpenSunshineInstallDialogCommand { get; }
    public RelayCommand OpenEnhancedSessionFixDialogCommand { get; }
    public AsyncRelayCommand VddDiagnoseCommand { get; }
    public AsyncRelayCommand VddEnableCommand { get; }
    public AsyncRelayCommand VddDisableCommand { get; }
    public AsyncRelayCommand VddInstallCommand { get; }
    public AsyncRelayCommand GamingOptimizePerformanceCommand { get; }
    public AsyncRelayCommand GamingOptimizePrivacyCommand { get; }
    public RelayCommand BrowseNvidiaDriverCommand { get; }
    public AsyncRelayCommand PatchNvidiaGpuDriverCommand { get; }

    public event EventHandler? VmsChanged;
    public event EventHandler? CreateVmRequested;
    public event EventHandler<string>? SunshineInstallRequested;
    public event EventHandler<string>? EnhancedSessionFixRequested;

    /// <summary>Demande a la coquille (MainViewModel) d'afficher la boite de
    /// confirmation fournie par-dessus toute la fenetre : cette vue ne connait pas
    /// la mecanique des modales, comme pour CreateVmRequested.</summary>
    public event EventHandler<ConfirmDialogViewModel>? ConfirmRequested;

    /// <summary>Appele par MainViewModel une fois la boite de dialogue d'identifiants
    /// terminee avec succes, pour afficher le resultat (etapes restantes : PIN
    /// d'appariement) directement dans l'onglet Affichage plutot que de le perdre.</summary>
    public void OnSunshineInstalled(SunshineInstallResultDto result)
    {
        DisplayDiagnosticsSummary = Loc.Get("Vm_SunshineInstalledSummary", result.Message, result.SunshineWebUiUrl);
    }

    /// <summary>Appele par MainViewModel une fois la boite de dialogue de correction
    /// de la Session Amelioree terminee avec succes.</summary>
    public void OnEnhancedSessionFixed(EnhancedSessionFixResultDto result)
    {
        DisplayDiagnosticsSummary = result.Message;
    }

    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            var selectedName = SelectedVm?.Name;

            var vms = await _vmService.GetVmsAsync();
            Vms.Clear();
            foreach (var vm in vms) Vms.Add(vm);

            var gpus = await _vmService.GetHostGpusAsync();
            _hostGpus = gpus;
            AvailableGpus.Clear();
            GpuDropdownOptions.Clear();
            GpuDropdownOptions.Add(NoGpuLabel);
            foreach (var gpu in gpus.Where(g => g.PartitionSupported))
            {
                AvailableGpus.Add(gpu.Name);
                GpuDropdownOptions.Add(gpu.Name);
            }

            _hostLimits = await _vmService.GetHostLimitsAsync();
            OnPropertyChanged(nameof(TotalPhysicalRamGb));
            OnPropertyChanged(nameof(MaxMemoryGb));
            OnPropertyChanged(nameof(ShowRamWarning));
            OnPropertyChanged(nameof(MaxCpu));
            OnPropertyChanged(nameof(CpuCores));
            OnPropertyChanged(nameof(CpuLogicalProcessors));

            SelectedVm = selectedName is null
                ? Vms.FirstOrDefault()
                : Vms.FirstOrDefault(v => v.Name == selectedName) ?? Vms.FirstOrDefault();

            VmsChanged?.Invoke(this, EventArgs.Empty);
        });
    }

    public void AddCreatedVm(VirtualMachine vm)
    {
        Vms.Add(vm);
        SelectedVm = vm;
        VmsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void LoadEditFieldsFromSelection()
    {
        GpuDiagnosticsSummary = null;
        DisplayDiagnosticsSummary = null;
        VddResultText = null;
        VddUsername = "";
        VddInitialPassword = null;
        VddRememberCredentials = false;
        GamingResultText = null;
        GamingUsername = "";
        GamingInitialPassword = null;
        GamingRememberCredentials = false;
        NvidiaDriverInstallerPath = null;
        NvidiaPatchResultText = null;
        if (SelectedVm is null) return;
        EditCpu = SelectedVm.Cpu;
        EditMemoryGb = SelectedVm.MemoryGb;
        EditDynamicMemoryEnabled = SelectedVm.DynamicMemoryEnabled;
        EditGpuName = SelectedVm.GpuName;
        EditGpuVramMb = SelectedVm.GpuVramMb;
        InstallGpuDriverCommand.RaiseCanExecuteChanged();
        PatchNvidiaGpuDriverCommand.RaiseCanExecuteChanged();

        if (VmCredentialStore.TryLoad(SelectedVm.Name, out var savedUsername, out var savedPassword))
        {
            VddUsername = savedUsername;
            VddInitialPassword = savedPassword;
            VddRememberCredentials = true;
            GamingUsername = savedUsername;
            GamingInitialPassword = savedPassword;
            GamingRememberCredentials = true;
        }
    }

    private async Task ChangeStateAsync(Func<string, Task<VirtualMachine?>> action)
    {
        if (SelectedVm is null) return;
        var updated = await action(SelectedVm.Name);
        if (updated is not null) SelectedVm.UpdateFrom(ToDto(updated));
        RaiseAllCanExecuteChanged();
    }

    private void AskHowToStop()
    {
        if (SelectedVm is null) return;
        var name = SelectedVm.Name;

        var dialog = new ConfirmDialogViewModel(
            Loc.Get("VmList_StopChoice_Title"),
            Loc.Get("VmList_StopChoice_Message", name),
            primaryLabel: Loc.Get("VmList_StopChoice_Normal"),
            secondaryLabel: Loc.Get("VmList_StopChoice_Forced"));

        dialog.Closed += async (_, choice) =>
        {
            if (choice == ConfirmChoice.Primary) await ChangeStateAsync(_vmService.StopVmAsync);
            else if (choice == ConfirmChoice.Secondary) await ChangeStateAsync(_vmService.ForceStopVmAsync);
        };

        ConfirmRequested?.Invoke(this, dialog);
    }

    private void AskDeleteConfirmation()
    {
        if (SelectedVm is null) return;
        var name = SelectedVm.Name;

        var dialog = new ConfirmDialogViewModel(
            Loc.Get("VmList_DeleteConfirm_Title"),
            Loc.Get("VmList_DeleteConfirm_Message", name),
            primaryLabel: Loc.Get("Common_Delete"),
            primaryIsDanger: true);

        dialog.Closed += async (_, choice) =>
        {
            if (choice == ConfirmChoice.Primary) await DeleteSelectedAsync();
        };

        ConfirmRequested?.Invoke(this, dialog);
    }

    private async Task DeleteSelectedAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        var name = SelectedVm.Name;
        var (ok, error) = await _vmService.DeleteVmAsync(name);
        if (!ok)
        {
            ErrorMessage = error ?? Loc.Get("Vm_DeleteFailed", name);
            return;
        }

        var toRemove = Vms.FirstOrDefault(v => v.Name == name);
        if (toRemove is not null) Vms.Remove(toRemove);
        SelectedVm = Vms.FirstOrDefault();
        VmsChanged?.Invoke(this, EventArgs.Empty);
    }

    private async Task SaveResourcesAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        if (EditMemoryGb > MaxMemoryGb)
        {
            ErrorMessage = Loc.Get("Vm_RamLimitExceeded", EditMemoryGb, MaxMemoryGb);
            return;
        }

        var updated = await _vmService.SetResourcesAsync(SelectedVm.Name, EditCpu, (long)(EditMemoryGb * 1024), EditDynamicMemoryEnabled);
        if (updated is not null) SelectedVm.UpdateFrom(ToDto(updated));
    }

    private async Task SaveGpuAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        GpuDiagnosticsSummary = null;
        var (updated, error) = await _vmService.SetGpuPartitionAsync(SelectedVm.Name, EditGpuName, EditGpuVramMb);
        if (updated is null)
        {
            // Cause probable la plus frequente : la VM doit etre eteinte pour
            // (re)configurer le GPU-P (Add/Set-VMGpuPartitionAdapter ne s'appliquent
            // pas a chaud) - le message precis du script l'indique deja si c'est ca.
            ErrorMessage = error ?? Loc.Get("Vm_GpuConfigFailed");
            return;
        }
        SelectedVm.UpdateFrom(ToDto(updated));
        InstallGpuDriverCommand.RaiseCanExecuteChanged();
    }

    private async Task RunGpuDiagnosticsAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        var diag = await _vmService.GetGpuDiagnosticsAsync(SelectedVm.Name);
        if (diag is null)
        {
            GpuDiagnosticsSummary = Loc.Get("Vm_DiagnosticFailed");
            return;
        }

        var lines = new List<string>
        {
            $"Generation VM : {diag.VmGeneration} ({(diag.GenerationOk ? "OK" : "GPU-P necessite Generation 2")})",
            $"GPU hote detecte : {diag.HostGpuName ?? "aucun"}" + (diag.HostGpuDriverVersion is null ? "" : $" (pilote {diag.HostGpuDriverVersion})"),
            $"GPU compatible GPU-P : {(diag.HostGpuCompatible ? "Oui" : "Non")}" + (diag.HostGpuError is null ? "" : $" - erreur : {diag.HostGpuError}"),
            $"Adaptateur GPU-P attache a cette VM : {(diag.AdapterAttached ? "Oui" : "Non")}" + (diag.AdapterError is null ? "" : $" - erreur : {diag.AdapterError}"),
        };
        if (diag.AdapterAttached)
        {
            lines.Add($"Partition VRAM (echelle Hyper-V) : min {diag.AdapterMinPartitionVRAM} / max {diag.AdapterMaxPartitionVRAM} / optimal {diag.AdapterOptimalPartitionVRAM}");
        }
        if (!string.IsNullOrWhiteSpace(diag.IssuesText))
        {
            lines.Add($"Problemes detectes : {diag.IssuesText}");
        }
        lines.Add(diag.DriverCheckNote ?? "");
        lines.Add(diag.OverallOk ? "Resultat global : OK" : "Resultat global : PROBLEME (voir ci-dessus)");

        GpuDiagnosticsSummary = string.Join("\n", lines.Where(l => !string.IsNullOrWhiteSpace(l)));
    }

    private async Task InstallGpuDriverAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        GpuDiagnosticsSummary = null;
        GpuDriverInstallStep = Loc.Get("VmList_Gpu_InstallDriverInProgress");
        IsInstallingGpuDriver = true;
        try
        {
            var (result, error) = await _vmService.InstallGpuDriverAsync(SelectedVm.Name, OnGpuDriverInstallProgress);
            if (result is null)
            {
                GpuDiagnosticsSummary = Loc.Get("Vm_DriverInstallFailed", error);
                return;
            }

            GpuDiagnosticsSummary = Loc.Get("Vm_DriverInstallSummary", result.Message, result.HostDriverStorePath);
        }
        finally
        {
            IsInstallingGpuDriver = false;
            GpuDriverInstallStep = null;
        }
    }

    /// <summary>Appele depuis le thread qui suit la sortie du script eleve (pas le
    /// thread UI) : on repasse par le Dispatcher avant de toucher une propriete liee.</summary>
    private void OnGpuDriverInstallProgress(string step)
    {
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => { GpuDriverInstallStep = step; });
    }

    private async Task RunDisplayDiagnosticsAsync()
    {
        if (SelectedVm is null) return;
        ErrorMessage = null;
        var diag = await _vmService.GetDisplayDiagnosticsAsync(SelectedVm.Name);
        if (diag is null)
        {
            DisplayDiagnosticsSummary = Loc.Get("Vm_DiagnosticFailed");
            return;
        }

        var lines = new[]
        {
            $"Frequence reellement appliquee : {diag.ActualHz} Hz ({(diag.ActualHzIsReallyEnforced ? "confirmee" : "NON garantie/appliquee par vmconnect")})",
            $"Resolution demandee : {diag.RequestedResolution}",
            $"GPU-P actif sur cette VM : {(diag.GpuPartitionActive ? "Oui" : "Non")}",
            $"Session amelioree autorisee par l'hote : {(diag.HostEnhancedSessionAllowed ? "Oui" : "Non")}",
            "",
            diag.DisplayPathLimitation ?? "",
            "",
            diag.Recommendation ?? "",
        };
        DisplayDiagnosticsSummary = string.Join("\n", lines.Where(l => l is not null));
    }

    private void BrowseNvidiaDriver()
    {
        var path = BrowseForNvidiaDriverFile?.Invoke();
        if (string.IsNullOrWhiteSpace(path)) return;

        NvidiaDriverInstallerPath = path;
        PatchNvidiaGpuDriverCommand.RaiseCanExecuteChanged();
    }

    private async Task PatchNvidiaGpuDriverAsync()
    {
        if (SelectedVm is null || string.IsNullOrWhiteSpace(NvidiaDriverInstallerPath)) return;
        ErrorMessage = null;
        NvidiaPatchResultText = Loc.Get("Vm_NvidiaPatchInProgress");
        var (result, error) = await _vmService.InstallNvidiaPatchedDriverAsync(SelectedVm.Name, NvidiaDriverInstallerPath);
        if (result is null)
        {
            NvidiaPatchResultText = error ?? Loc.Get("Vm_NvidiaPatchFailed");
            return;
        }

        NvidiaPatchResultText = result.Message;
    }

    private async Task VddRunAsync(bool disable = false, bool enable = false)
    {
        if (SelectedVm is null) return;
        var password = VddGetPassword?.Invoke() ?? "";
        if (string.IsNullOrEmpty(password))
        {
            VddResultText = Loc.Get("Common_PasswordRequired");
            return;
        }

        var (result, error) = await _vmService.DiagnoseVddAsync(SelectedVm.Name, ResolveVddUsername(VddUsername), password, disable, enable);
        if (result is null)
        {
            VddResultText = error ?? Loc.Get("Vm_VddDiagnosticFailed");
            return;
        }

        if (VddRememberCredentials) VmCredentialStore.Save(SelectedVm.Name, VddUsername, password);
        else VmCredentialStore.Delete(SelectedVm.Name);

        VddResultText = result.Message;
    }

    private async Task VddInstallAsync()
    {
        if (SelectedVm is null) return;
        var password = VddGetPassword?.Invoke() ?? "";
        if (string.IsNullOrEmpty(password))
        {
            VddResultText = Loc.Get("Common_PasswordRequired");
            return;
        }

        VddResultText = Loc.Get("Vm_VddInstallInProgress");
        var (result, error) = await _vmService.InstallVddAsync(SelectedVm.Name, ResolveVddUsername(VddUsername), password);
        if (result is null)
        {
            VddResultText = error ?? Loc.Get("Vm_VddInstallFailed");
            return;
        }

        if (VddRememberCredentials) VmCredentialStore.Save(SelectedVm.Name, VddUsername, password);
        else VmCredentialStore.Delete(SelectedVm.Name);

        VddResultText = result.Message;
    }

    private async Task GamingOptimizeAsync(bool performance, bool privacy)
    {
        if (SelectedVm is null) return;
        var password = GamingGetPassword?.Invoke() ?? "";
        if (string.IsNullOrEmpty(password))
        {
            GamingResultText = Loc.Get("Common_PasswordRequired");
            return;
        }

        GamingResultText = Loc.Get("Vm_GamingOptimizeInProgress");
        var (result, error) = await _vmService.OptimizeGamingAsync(
            SelectedVm.Name, ResolveVddUsername(GamingUsername), password, performance, privacy);
        if (result is null)
        {
            GamingResultText = error ?? Loc.Get("Vm_GamingOptimizeFailed");
            return;
        }

        if (GamingRememberCredentials) VmCredentialStore.Save(SelectedVm.Name, GamingUsername, password);
        else VmCredentialStore.Delete(SelectedVm.Name);

        GamingResultText = result.Message;
    }

    /// <summary>Un compte Microsoft ne peut s'authentifier localement (PowerShell Direct,
    /// runas, etc.) que sous la forme "MicrosoftAccount\email" - jamais l'e-mail seul.
    /// L'utilisateur ne tape que son e-mail : ce prefixe technique est ajoute ici pour lui,
    /// sauf s'il a deja saisi un nom de compte local ou un domaine ("PC\utilisateur").</summary>
    private static string ResolveVddUsername(string username)
    {
        var trimmed = username.Trim();
        if (trimmed.Contains('@') && !trimmed.Contains('\\'))
        {
            return $"MicrosoftAccount\\{trimmed}";
        }
        return trimmed;
    }

    private void RaiseAllCanExecuteChanged()
    {
        StartCommand.RaiseCanExecuteChanged();
        StopCommand.RaiseCanExecuteChanged();
        DeleteCommand.RaiseCanExecuteChanged();
        OpenSunshineInstallDialogCommand.RaiseCanExecuteChanged();
        OpenEnhancedSessionFixDialogCommand.RaiseCanExecuteChanged();
        VddDiagnoseCommand.RaiseCanExecuteChanged();
        VddEnableCommand.RaiseCanExecuteChanged();
        VddDisableCommand.RaiseCanExecuteChanged();
        VddInstallCommand.RaiseCanExecuteChanged();
        GamingOptimizePerformanceCommand.RaiseCanExecuteChanged();
        GamingOptimizePrivacyCommand.RaiseCanExecuteChanged();
        PatchNvidiaGpuDriverCommand.RaiseCanExecuteChanged();
    }

    private static VirtualMachineDto ToDto(VirtualMachine vm) => new()
    {
        Id = vm.Id,
        Name = vm.Name,
        State = vm.State.ToString(),
        Cpu = vm.Cpu,
        MemoryMb = vm.MemoryMb,
        GpuName = vm.GpuName,
        GpuVramMb = vm.GpuVramMb,
        Resolution = vm.Resolution,
        Hz = vm.RefreshRateHz,
        DiskPath = vm.DiskPath,
        DiskSizeGb = vm.DiskSizeGb,
        IsoPath = vm.IsoPath,
        LastError = vm.LastError,
    };
}
