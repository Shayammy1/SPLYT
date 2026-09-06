using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private DiagnosticsDto? _diagnostics;
    private string _defaultDiskPath = @"C:\NovaVM\Disks";
    private bool _autoSelectGpu = true;
    private bool _darkTheme = true;
    private AppLanguage _selectedLanguage = Loc.CurrentLanguage;
    private bool _languageChanged;

    public SettingsViewModel(NovaVmService vmService)
    {
        _vmService = vmService;
        RefreshDiagnosticsCommand = new AsyncRelayCommand(LoadAsync);
        RestartNowCommand = new RelayCommand(RestartNow);
        _ = LoadAsync();
    }

    public DiagnosticsDto? Diagnostics { get => _diagnostics; private set => SetProperty(ref _diagnostics, value); }

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

    public string AppVersion => "SPLYT 0.2.0-prototype";

    public AsyncRelayCommand RefreshDiagnosticsCommand { get; }
    public RelayCommand RestartNowCommand { get; }

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
