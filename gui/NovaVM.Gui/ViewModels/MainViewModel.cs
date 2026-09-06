using System.Collections.ObjectModel;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// ViewModel de la coquille de l'application : navigation laterale (ViewModel-first,
/// via des DataTemplates dans App.xaml qui savent afficher chaque type de page) et
/// ouverture de la fenetre modale "Creer une VM".
/// </summary>
public sealed class MainViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private object _currentViewModel;
    private NavItem? _selectedNavItem;
    private bool _isCreateDialogOpen;
    private CreateVmDialogViewModel? _createVmDialog;
    private bool _isSunshineDialogOpen;
    private SunshineCredentialsDialogViewModel? _sunshineCredentialsDialog;
    private bool _isEnhancedSessionFixDialogOpen;
    private EnhancedSessionFixDialogViewModel? _enhancedSessionFixDialog;
    private bool _isHyperVSetupDialogOpen;
    private HyperVSetupDialogViewModel? _hyperVSetupDialog;

    public MainViewModel(NovaVmService vmService, LogService log)
    {
        _vmService = vmService;

        Dashboard = new DashboardViewModel(vmService, log);
        VmList = new VmListViewModel(vmService);
        Gpu = new GpuViewModel(vmService);
        Storage = new StorageViewModel(vmService);
        Settings = new SettingsViewModel(vmService);
        Journal = new JournalViewModel(log);

        // Quand une VM change (creee/demarree/supprimee...), le Dashboard se
        // rafraichit pour rester coherent avec l'onglet "Machines virtuelles".
        VmList.VmsChanged += (_, _) => _ = Dashboard.LoadAsync();

        // La vue VmList ne connait pas la mecanique de la boite de dialogue
        // modale (qui vit au niveau de la coquille) : elle se contente de
        // demander son ouverture via cet evenement.
        VmList.CreateVmRequested += async (_, _) => await OpenCreateVmDialogAsync();
        VmList.SunshineInstallRequested += (_, vmName) => OpenSunshineCredentialsDialog(vmName);
        VmList.EnhancedSessionFixRequested += (_, vmName) => OpenEnhancedSessionFixDialog(vmName);

        NavItems = new ObservableCollection<NavItem>
        {
            new() { Title = Loc.Get("Nav_Dashboard"), Icon = "\U0001F3E0", ViewModel = Dashboard },
            new() { Title = Loc.Get("Nav_VmList"), Icon = "\U0001F4BB", ViewModel = VmList },
            new() { Title = Loc.Get("Nav_Gpu"), Icon = "\U0001F3AE", ViewModel = Gpu },
            new() { Title = Loc.Get("Nav_Storage"), Icon = "\U0001F4BE", ViewModel = Storage },
            new() { Title = Loc.Get("Nav_Journal"), Icon = "\U0001F4CB", ViewModel = Journal },
            new() { Title = Loc.Get("Nav_Settings"), Icon = "⚙", ViewModel = Settings },
        };

        _currentViewModel = Dashboard;
        _selectedNavItem = NavItems[0];

        OpenCreateVmDialogCommand = new AsyncRelayCommand(OpenCreateVmDialogAsync);
        CloseCreateVmDialogCommand = new RelayCommand(() => IsCreateDialogOpen = false);

        _ = CheckHyperVSetupAsync();
    }

    public ObservableCollection<NavItem> NavItems { get; }

    public NavItem? SelectedNavItem
    {
        get => _selectedNavItem;
        set
        {
            if (SetProperty(ref _selectedNavItem, value) && value is not null)
            {
                CurrentViewModel = value.ViewModel;
            }
        }
    }

    public object CurrentViewModel
    {
        get => _currentViewModel;
        private set => SetProperty(ref _currentViewModel, value);
    }

    public DashboardViewModel Dashboard { get; }
    public VmListViewModel VmList { get; }
    public GpuViewModel Gpu { get; }
    public StorageViewModel Storage { get; }
    public SettingsViewModel Settings { get; }
    public JournalViewModel Journal { get; }

    public bool IsCreateDialogOpen { get => _isCreateDialogOpen; private set => SetProperty(ref _isCreateDialogOpen, value); }
    public CreateVmDialogViewModel? CreateVmDialog { get => _createVmDialog; private set => SetProperty(ref _createVmDialog, value); }

    public bool IsSunshineDialogOpen { get => _isSunshineDialogOpen; private set => SetProperty(ref _isSunshineDialogOpen, value); }
    public SunshineCredentialsDialogViewModel? SunshineCredentialsDialog { get => _sunshineCredentialsDialog; private set => SetProperty(ref _sunshineCredentialsDialog, value); }

    public bool IsEnhancedSessionFixDialogOpen { get => _isEnhancedSessionFixDialogOpen; private set => SetProperty(ref _isEnhancedSessionFixDialogOpen, value); }
    public EnhancedSessionFixDialogViewModel? EnhancedSessionFixDialog { get => _enhancedSessionFixDialog; private set => SetProperty(ref _enhancedSessionFixDialog, value); }

    public bool IsHyperVSetupDialogOpen { get => _isHyperVSetupDialogOpen; private set => SetProperty(ref _isHyperVSetupDialogOpen, value); }
    public HyperVSetupDialogViewModel? HyperVSetupDialog { get => _hyperVSetupDialog; private set => SetProperty(ref _hyperVSetupDialog, value); }

    public AsyncRelayCommand OpenCreateVmDialogCommand { get; }
    public RelayCommand CloseCreateVmDialogCommand { get; }

    private async Task OpenCreateVmDialogAsync()
    {
        var gpus = await _vmService.GetHostGpusAsync();
        var memoryLimits = await _vmService.GetHostMemoryLimitsAsync();
        var dialog = new CreateVmDialogViewModel(_vmService, gpus, memoryLimits);
        dialog.Created += (_, _) =>
        {
            if (dialog.CreatedVm is not null) VmList.AddCreatedVm(dialog.CreatedVm);
            IsCreateDialogOpen = false;
        };
        dialog.Cancelled += (_, _) => IsCreateDialogOpen = false;
        CreateVmDialog = dialog;
        IsCreateDialogOpen = true;
    }

    private void OpenSunshineCredentialsDialog(string vmName)
    {
        var dialog = new SunshineCredentialsDialogViewModel(_vmService, vmName);
        dialog.Completed += (_, _) =>
        {
            IsSunshineDialogOpen = false;
            if (dialog.InstallResult is not null) VmList.OnSunshineInstalled(dialog.InstallResult);

            var url = dialog.InstallResult?.SunshineWebUiUrl;
            if (!string.IsNullOrWhiteSpace(url))
            {
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
                }
                catch
                {
                    // Best-effort : l'utilisateur peut toujours ouvrir l'URL manuellement
                    // (deja affichee dans le resume du diagnostic d'affichage).
                }
            }
        };
        dialog.Cancelled += (_, _) => IsSunshineDialogOpen = false;
        SunshineCredentialsDialog = dialog;
        IsSunshineDialogOpen = true;
    }

    /// <summary>Propose automatiquement d'activer Hyper-V au demarrage si ce n'est pas
    /// deja fait - la seule vraie dependance dure de SPLYT. Get-NovaVmDiagnostics.ps1 ne
    /// necessite pas d'elevation (juste une lecture), donc pas d'invite UAC surprise
    /// tant que l'utilisateur n'a pas explicitement clique sur "Activer maintenant".</summary>
    private async Task CheckHyperVSetupAsync()
    {
        var diag = await _vmService.GetDiagnosticsAsync();
        if (diag is null) return;

        if (diag.HyperVModuleInstalled)
        {
            // Hyper-V est bien detecte : si un redemarrage etait note comme "en
            // attente" (voir HyperVSetupDialogViewModel), il a fait son effet -
            // on efface la marque pour ne pas la trainer indefiniment.
            var settings = AppSettingsStore.Load();
            if (settings.HyperVRebootPending)
            {
                settings.HyperVRebootPending = false;
                AppSettingsStore.Save(settings);
            }
            return;
        }

        var rebootPending = AppSettingsStore.Load().HyperVRebootPending;
        var dialog = new HyperVSetupDialogViewModel(_vmService, rebootPending);
        dialog.Dismissed += (_, _) => IsHyperVSetupDialogOpen = false;
        HyperVSetupDialog = dialog;
        IsHyperVSetupDialogOpen = true;
    }

    private void OpenEnhancedSessionFixDialog(string vmName)
    {
        var dialog = new EnhancedSessionFixDialogViewModel(_vmService, vmName);
        dialog.Completed += (_, _) =>
        {
            IsEnhancedSessionFixDialogOpen = false;
            if (dialog.FixResult is not null) VmList.OnEnhancedSessionFixed(dialog.FixResult);
        };
        dialog.Cancelled += (_, _) => IsEnhancedSessionFixDialogOpen = false;
        EnhancedSessionFixDialog = dialog;
        IsEnhancedSessionFixDialogOpen = true;
    }
}
