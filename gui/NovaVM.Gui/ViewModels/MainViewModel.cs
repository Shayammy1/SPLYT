using System.Collections.ObjectModel;
using System.Windows.Threading;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using Wpf.Ui.Controls;

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
    private bool _isConfirmDialogOpen;
    private ConfirmDialogViewModel? _confirmDialog;
    private bool _isInfoDialogOpen;
    private InfoDialogViewModel? _infoDialog;
    private bool _isLanguageChoiceDialogOpen;
    private LanguageChoiceDialogViewModel? _languageChoiceDialog;
    private bool _isMoonlightLaunchDialogOpen;
    private MoonlightLaunchDialogViewModel? _moonlightLaunchDialog;
    private bool _isSplytSetupDialogOpen;
    private SplytSetupDialogViewModel? _splytSetupDialog;
    private bool _isSidebarCollapsed;
    private readonly DispatcherTimer _stateRefreshTimer;

    public MainViewModel(NovaVmService vmService, LogService log)
    {
        _vmService = vmService;

        // VmList d'abord : c'est lui qui detient la liste des VMs, que le Dashboard
        // se contente ensuite de partager (voir son constructeur).
        VmList = new VmListViewModel(vmService);
        Dashboard = new DashboardViewModel(vmService, log, VmList.Vms);
        Gpu = new GpuViewModel(vmService);
        Storage = new StorageViewModel(vmService);
        Settings = new SettingsViewModel(vmService, log);
        Journal = new JournalViewModel(log);
        Debug = new DebugViewModel(vmService);

        // Quand une VM change (creee/demarree/supprimee...), le Dashboard se
        // rafraichit pour rester coherent avec l'onglet "Machines virtuelles".
        VmList.VmsChanged += (_, _) => _ = Dashboard.LoadAsync();

        // La vue VmList ne connait pas la mecanique de la boite de dialogue
        // modale (qui vit au niveau de la coquille) : elle se contente de
        // demander son ouverture via cet evenement.
        VmList.CreateVmRequested += async (_, _) => await OpenCreateVmDialogAsync();
        VmList.SunshineInstallRequested += (_, vmName) => OpenSunshineCredentialsDialog(vmName);
        VmList.EnhancedSessionFixRequested += (_, vmName) => OpenEnhancedSessionFixDialog(vmName);

        // La VmList construit elle-meme sa boite de confirmation (elle seule sait ce
        // que chaque choix doit declencher) ; la coquille se charge uniquement de
        // l'afficher par-dessus toute la fenetre, comme les autres modales.
        VmList.ConfirmRequested += (_, dialog) => OpenConfirmDialog(dialog);
        VmList.InfoRequested += (_, dialog) => OpenInfoDialog(dialog);
        VmList.SplytSetupSuggested += (_, vm) => OpenSplytSetupDialog(vm);
        VmList.ConsoleRequested += (_, vm) => OpenConsoleWindow(vm);
        VmList.MoonlightLaunchRequested += (_, vm) => OpenMoonlightLaunchDialog(vm);

        NavItems = new ObservableCollection<NavItem>
        {
            new() { Title = Loc.Get("Nav_Dashboard"), Icon = SymbolRegular.Home24, ViewModel = Dashboard },
            new() { Title = Loc.Get("Nav_VmList"), Icon = SymbolRegular.Desktop24, ViewModel = VmList },
            new() { Title = Loc.Get("Nav_Gpu"), Icon = SymbolRegular.XboxController24, ViewModel = Gpu },
            new() { Title = Loc.Get("Nav_Storage"), Icon = SymbolRegular.Database24, ViewModel = Storage },
            new() { Title = Loc.Get("Nav_Journal"), Icon = SymbolRegular.DocumentText24, ViewModel = Journal },
            new() { Title = Loc.Get("Nav_Debug"), Icon = SymbolRegular.Wrench24, ViewModel = Debug },
            new() { Title = Loc.Get("Nav_Settings"), Icon = SymbolRegular.Settings24, ViewModel = Settings },
        };

        _currentViewModel = Dashboard;
        _selectedNavItem = NavItems[0];

        OpenCreateVmDialogCommand = new AsyncRelayCommand(OpenCreateVmDialogAsync);
        CloseCreateVmDialogCommand = new RelayCommand(() => IsCreateDialogOpen = false);
        ToggleSidebarCommand = new RelayCommand(() => IsSidebarCollapsed = !IsSidebarCollapsed);

        // Rafraichissement periodique de l'etat des VMs : un arret propre passe par
        // "Arret en cours" pendant plusieurs secondes, et une VM peut aussi etre
        // eteinte depuis l'interieur (l'utilisateur eteint Windows dans la VM) ou
        // depuis le Gestionnaire Hyper-V. Sans ca, l'etat affiche restait fige
        // jusqu'au prochain clic sur Actualiser.
        _stateRefreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _stateRefreshTimer.Tick += async (_, _) => await VmList.RefreshStatesAsync();
        _stateRefreshTimer.Start();

        _ = RunFirstRunFlowAsync();
    }

    /// <summary>Enchaine les invites de demarrage dans l'ordre : la langue d'abord
    /// (au tout premier lancement uniquement - inutile de proposer d'installer
    /// Hyper-V dans une langue que l'utilisateur n'a pas encore choisie), puis la
    /// verification Hyper-V.</summary>
    private async Task RunFirstRunFlowAsync()
    {
        if (Loc.NeedsLanguageChoice)
        {
            var restarting = await AskLanguageAsync();
            // Redemarrage en cours pour appliquer la langue : ne rien enchainer,
            // l'invite Hyper-V sera proposee par l'instance qui redemarre.
            if (restarting) return;
        }

        await CheckHyperVSetupAsync();
    }

    /// <summary>Demande la resolution et la frequence, puis lance la session. Ce
    /// choix n'est pas cosmetique : Sunshine applique le mode reclame par le client
    /// a l'ecran virtuel de l'invite (voir MoonlightLaunchDialogViewModel).</summary>
    private void OpenMoonlightLaunchDialog(Models.VirtualMachine vm)
    {
        var dialog = new MoonlightLaunchDialogViewModel(vm.Name, vm.Resolution, vm.RefreshRateHz);

        dialog.Closed += async (_, launch) =>
        {
            IsMoonlightLaunchDialogOpen = false;
            MoonlightLaunchDialog = null;
            if (launch) await VmList.LaunchWithMoonlightAsync(dialog.SelectedResolution, dialog.SelectedRefreshRate);
        };

        MoonlightLaunchDialog = dialog;
        IsMoonlightLaunchDialogOpen = true;
    }

    /// <summary>Retourne vrai si l'application est en train de redemarrer pour
    /// appliquer la langue choisie.</summary>
    private Task<bool> AskLanguageAsync()
    {
        var completion = new TaskCompletionSource<bool>();
        var dialog = new LanguageChoiceDialogViewModel();

        dialog.Confirmed += (_, restartNeeded) =>
        {
            IsLanguageChoiceDialogOpen = false;
            if (restartNeeded) RestartApp();
            completion.TrySetResult(restartNeeded);
        };

        LanguageChoiceDialog = dialog;
        IsLanguageChoiceDialogOpen = true;
        return completion.Task;
    }

    /// <summary>Les textes deja affiches ne changent qu'au demarrage (voir Loc) :
    /// au tout premier lancement, rien n'est en cours, donc relancer immediatement
    /// est plus simple pour l'utilisateur que de lui demander de le faire.</summary>
    private static void RestartApp()
    {
        try
        {
            System.Diagnostics.Process.Start(Environment.ProcessPath ?? "NovaVM.Gui.exe");
        }
        catch
        {
            // Best-effort : si le relancement echoue, l'utilisateur peut fermer et
            // rouvrir SPLYT lui-meme - la langue est deja enregistree.
        }
        System.Windows.Application.Current.Shutdown();
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
    public DebugViewModel Debug { get; }
    public JournalViewModel Journal { get; }

    public bool IsCreateDialogOpen { get => _isCreateDialogOpen; private set => SetProperty(ref _isCreateDialogOpen, value); }
    public CreateVmDialogViewModel? CreateVmDialog { get => _createVmDialog; private set => SetProperty(ref _createVmDialog, value); }

    public bool IsSunshineDialogOpen { get => _isSunshineDialogOpen; private set => SetProperty(ref _isSunshineDialogOpen, value); }
    public SunshineCredentialsDialogViewModel? SunshineCredentialsDialog { get => _sunshineCredentialsDialog; private set => SetProperty(ref _sunshineCredentialsDialog, value); }

    public bool IsEnhancedSessionFixDialogOpen { get => _isEnhancedSessionFixDialogOpen; private set => SetProperty(ref _isEnhancedSessionFixDialogOpen, value); }
    public EnhancedSessionFixDialogViewModel? EnhancedSessionFixDialog { get => _enhancedSessionFixDialog; private set => SetProperty(ref _enhancedSessionFixDialog, value); }

    public bool IsHyperVSetupDialogOpen { get => _isHyperVSetupDialogOpen; private set => SetProperty(ref _isHyperVSetupDialogOpen, value); }
    public HyperVSetupDialogViewModel? HyperVSetupDialog { get => _hyperVSetupDialog; private set => SetProperty(ref _hyperVSetupDialog, value); }

    public bool IsConfirmDialogOpen { get => _isConfirmDialogOpen; private set => SetProperty(ref _isConfirmDialogOpen, value); }
    public ConfirmDialogViewModel? ConfirmDialog { get => _confirmDialog; private set => SetProperty(ref _confirmDialog, value); }

    public bool IsInfoDialogOpen { get => _isInfoDialogOpen; private set => SetProperty(ref _isInfoDialogOpen, value); }
    public InfoDialogViewModel? InfoDialog { get => _infoDialog; private set => SetProperty(ref _infoDialog, value); }

    public bool IsLanguageChoiceDialogOpen { get => _isLanguageChoiceDialogOpen; private set => SetProperty(ref _isLanguageChoiceDialogOpen, value); }
    public LanguageChoiceDialogViewModel? LanguageChoiceDialog { get => _languageChoiceDialog; private set => SetProperty(ref _languageChoiceDialog, value); }

    public bool IsMoonlightLaunchDialogOpen { get => _isMoonlightLaunchDialogOpen; private set => SetProperty(ref _isMoonlightLaunchDialogOpen, value); }
    public MoonlightLaunchDialogViewModel? MoonlightLaunchDialog { get => _moonlightLaunchDialog; private set => SetProperty(ref _moonlightLaunchDialog, value); }

    public bool IsSplytSetupDialogOpen { get => _isSplytSetupDialogOpen; private set => SetProperty(ref _isSplytSetupDialogOpen, value); }
    public SplytSetupDialogViewModel? SplytSetupDialog { get => _splytSetupDialog; private set => SetProperty(ref _splytSetupDialog, value); }

    public AsyncRelayCommand OpenCreateVmDialogCommand { get; }
    public RelayCommand CloseCreateVmDialogCommand { get; }
    public RelayCommand ToggleSidebarCommand { get; }

    /// <summary>Barre laterale reduite aux icones : la liste des VMs et son panneau
    /// de details tiennent mal cote a cote sur un portable avec 250 px de navigation
    /// en permanence.</summary>
    public bool IsSidebarCollapsed
    {
        get => _isSidebarCollapsed;
        set
        {
            if (SetProperty(ref _isSidebarCollapsed, value)) OnPropertyChanged(nameof(SidebarWidth));
        }
    }

    /// <summary>Largeur reelle de la colonne de navigation. Une ColumnDefinition ne
    /// se pilote pas par declencheur de style, d'ou cette valeur calculee.</summary>
    public double SidebarWidth => IsSidebarCollapsed ? 64 : 250;

    /// <summary>La recherche du bandeau superieur filtre la liste des VMs : y taper
    /// depuis l'accueil doit donc aussi amener sur la page qui montre le resultat,
    /// sinon on tape dans le vide.</summary>
    public void GoToVmList()
    {
        var vmListItem = NavItems.FirstOrDefault(i => ReferenceEquals(i.ViewModel, VmList));
        if (vmListItem is not null) SelectedNavItem = vmListItem;
    }

    private async Task OpenCreateVmDialogAsync()
    {
        var gpus = await _vmService.GetHostGpusAsync();
        var hostLimits = await _vmService.GetHostLimitsAsync();
        var dialog = new CreateVmDialogViewModel(_vmService, gpus, hostLimits);
        dialog.Created += (_, _) =>
        {
            if (dialog.CreatedVm is not null) VmList.AddCreatedVm(dialog.CreatedVm);
            IsCreateDialogOpen = false;
        };
        dialog.Cancelled += (_, _) => IsCreateDialogOpen = false;
        CreateVmDialog = dialog;
        IsCreateDialogOpen = true;
    }

    /// <summary>La boite se referme sur n'importe quel choix : c'est le handler
    /// Closed pose par l'appelant (VmList) qui decide de l'action, pas la coquille.</summary>
    private void OpenConfirmDialog(ConfirmDialogViewModel dialog)
    {
        dialog.Closed += (_, _) => IsConfirmDialogOpen = false;
        ConfirmDialog = dialog;
        IsConfirmDialogOpen = true;
    }

    private void OpenInfoDialog(InfoDialogViewModel dialog)
    {
        dialog.Closed += (_, _) => IsInfoDialogOpen = false;
        InfoDialog = dialog;
        IsInfoDialogOpen = true;
    }

    /// <summary>Ouvre la configuration en un clic ("bouton SPLYT") et ramene la
    /// fenetre au premier plan : cette boite s'ouvre notamment toute seule quand
    /// Windows vient de finir de s'installer, moment ou l'utilisateur est en train
    /// de regarder la VM et pas SPLYT.</summary>
    private void OpenSplytSetupDialog(Models.VirtualMachine vm)
    {
        // Deja ouverte pour cette VM : ne pas la reinitialiser sous les doigts de
        // l'utilisateur (le rafraichissement periodique peut repasser par ici).
        if (IsSplytSetupDialogOpen && SplytSetupDialog?.VmName == vm.Name) return;

        var dialog = new SplytSetupDialogViewModel(_vmService, vm, VmList.HostGpus);
        dialog.Closed += (_, _) => IsSplytSetupDialogOpen = false;
        dialog.VmChanged += async (_, _) => await VmList.RefreshStatesAsync();

        SplytSetupDialog = dialog;
        IsSplytSetupDialogOpen = true;
        BringToForeground();
    }

    /// <summary>Ouvre (ou ramene au premier plan) la console de la VM dans sa propre
    /// fenetre. Une seule par VM : recliquer sur "Console" ne doit pas empiler des
    /// connexions vmconnect.</summary>
    private void OpenConsoleWindow(Models.VirtualMachine vm)
    {
        if (_consoleWindows.TryGetValue(vm.Name, out var existing))
        {
            if (existing.WindowState == System.Windows.WindowState.Minimized)
            {
                existing.WindowState = System.Windows.WindowState.Normal;
            }
            existing.Activate();
            return;
        }

        var window = new Controls.VmConsoleWindow(vm);
        _consoleWindows[vm.Name] = window;
        window.Closed += (_, _) => _consoleWindows.Remove(vm.Name);
        window.Show();
    }

    private readonly Dictionary<string, Controls.VmConsoleWindow> _consoleWindows = new();

    /// <summary>Windows empeche une application en arriere-plan de voler le premier
    /// plan ; l'aller-retour par Topmost est la maniere usuelle de contourner ca
    /// proprement pour une fenetre qui a une vraie raison de se montrer.</summary>
    private static void BringToForeground()
    {
        var window = System.Windows.Application.Current?.MainWindow;
        if (window is null) return;

        if (window.WindowState == System.Windows.WindowState.Minimized)
        {
            window.WindowState = System.Windows.WindowState.Normal;
        }
        window.Activate();
        window.Topmost = true;
        window.Topmost = false;
        window.Focus();
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
