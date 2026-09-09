using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private readonly LogService _log;
    private DiagnosticsDto? _diagnostics;
    private string? _copyReportStatus;
    private string _defaultDiskPath = @"C:\NovaVM\Disks";
    private bool _autoSelectGpu = true;
    private bool _darkTheme = true;
    private AppLanguage _selectedLanguage = Loc.CurrentLanguage;
    private bool _languageChanged;

    public SettingsViewModel(NovaVmService vmService, LogService log)
    {
        _vmService = vmService;
        _log = log;
        RefreshDiagnosticsCommand = new AsyncRelayCommand(LoadAsync);
        RestartNowCommand = new RelayCommand(RestartNow);
        CopyDiagnosticReportCommand = new AsyncRelayCommand(CopyDiagnosticReportAsync);
        _ = LoadAsync();
    }

    public DiagnosticsDto? Diagnostics { get => _diagnostics; private set => SetProperty(ref _diagnostics, value); }

    /// <summary>Retour affiche apres un clic sur "copier le rapport" (succes ou
    /// echec du presse-papiers), plutot qu'un bouton qui ne dit rien.</summary>
    public string? CopyReportStatus { get => _copyReportStatus; private set => SetProperty(ref _copyReportStatus, value); }

    // Reglages d'application simples, en memoire pour l'instant (la persistence
    // sur disque - fichier de config utilisateur - viendra en phase d'implementation).
    public string DefaultDiskPath { get => _defaultDiskPath; set => SetProperty(ref _defaultDiskPath, value); }
    public bool AutoSelectGpu { get => _autoSelectGpu; set => SetProperty(ref _autoSelectGpu, value); }
    public bool DarkTheme { get => _darkTheme; set => SetProperty(ref _darkTheme, value); }

    public IReadOnlyList<AppLanguage> AvailableLanguages { get; } = new[] { AppLanguage.French, AppLanguage.English };

    /// <summary>Persistee immediatement (voir Loc.SetLanguage), mais n'affecte les
    /// textes deja affiches qu'au prochain demarrage de SPLYT (voir Loc pour le pourquoi) -
    /// d'ou LanguageChanged, qui affiche une invite de redemarrage.</summary>
    public AppLanguage SelectedLanguage
    {
        get => _selectedLanguage;
        set
        {
            if (SetProperty(ref _selectedLanguage, value))
            {
                Loc.SetLanguage(value);
                LanguageChanged = true;
            }
        }
    }

    public bool LanguageChanged { get => _languageChanged; private set => SetProperty(ref _languageChanged, value); }

    public string AppVersion => "SPLYT 0.7.0-prototype";

    public AsyncRelayCommand RefreshDiagnosticsCommand { get; }
    public RelayCommand RestartNowCommand { get; }

    /// <summary>Met dans le presse-papiers tout ce qu'il faut pour qu'un rapport de
    /// bug soit exploitable (materiel, pilotes, build de Windows, etat des VMs,
    /// dernieres erreurs) : demander ces informations a l'utilisateur donne des
    /// champs oublies ou faux, alors que SPLYT les connait deja.</summary>
    public AsyncRelayCommand CopyDiagnosticReportCommand { get; }

    private async Task CopyDiagnosticReportAsync()
    {
        CopyReportStatus = null;

        // Diagnostics rafraichis au moment du clic : un rapport doit decrire l'etat
        // actuel de la machine, pas celui de l'ouverture de la page.
        var diagnostics = await _vmService.GetDiagnosticsAsync();
        Diagnostics = diagnostics ?? Diagnostics;

        var report = DiagnosticReportBuilder.Build(
            AppVersion,
            diagnostics ?? Diagnostics,
            await _vmService.GetHostLimitsAsync(),
            await _vmService.GetHostGpusAsync(),
            await _vmService.GetVmsAsync(),
            _log.RecentAlerts(10));

        try
        {
            // Le presse-papiers peut etre momentanement verrouille par une autre
            // application : WPF echoue alors avec une exception COM, d'ou le retry.
            System.Windows.Clipboard.SetDataObject(report, copy: true);
            CopyReportStatus = Loc.Get("Settings_ReportCopied");
        }
        catch
        {
            try
            {
                await Task.Delay(150);
                System.Windows.Clipboard.SetDataObject(report, copy: true);
                CopyReportStatus = Loc.Get("Settings_ReportCopied");
            }
            catch (Exception ex)
            {
                CopyReportStatus = Loc.Get("Settings_ReportCopyFailed", ex.Message);
            }
        }
    }

    private void RestartNow()
    {
        try
        {
            System.Diagnostics.Process.Start(Environment.ProcessPath ?? "NovaVM.Gui.exe");
        }
        catch
        {
            // Best-effort : si le relancement automatique echoue, l'utilisateur peut
            // toujours fermer/rouvrir SPLYT lui-meme.
        }
        System.Windows.Application.Current.Shutdown();
    }

    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            Diagnostics = await _vmService.GetDiagnosticsAsync();
        });
    }
}
