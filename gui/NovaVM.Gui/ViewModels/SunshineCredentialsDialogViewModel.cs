using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

/// <summary>Modele de la boite de dialogue demandant les identifiants Windows de
/// la VM pour installer Sunshine automatiquement via PowerShell Direct (voir
/// NovaVmService.InstallSunshineAutomaticallyAsync). Ces identifiants sont ceux
/// que l'utilisateur a deja definis pour SA VM a l'installation de Windows :
/// NovaVM ne les journalise jamais, et ne les memorise que si l'utilisateur coche
/// "Se souvenir de mes identifiants" - via le Gestionnaire d'identifiants Windows
/// (DPAPI, voir VmCredentialStore), jamais en clair dans un fichier NovaVM.
///
/// Enchaine aussi l'etape de preparation (NovaVmService.EnableStreamingAsync :
/// installation de Moonlight sur l'hote + depot de l'installeur Sunshine sur le
/// Bureau de la VM) avant l'installation proprement dite - anciennement deux
/// boutons separes dans l'interface, fusionnes ici car le second dependait
/// silencieusement du premier.</summary>
public sealed class SunshineCredentialsDialogViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private string _username = "";
    private bool _rememberCredentials;
    private string? _progressText;

    public SunshineCredentialsDialogViewModel(NovaVmService vmService, string vmName)
    {
        _vmService = vmService;
        VmName = vmName;

        InstallCommand = new AsyncRelayCommand(InstallAsync, () => !string.IsNullOrWhiteSpace(Username));
        CancelCommand = new RelayCommand(() => Cancelled?.Invoke(this, EventArgs.Empty));

        if (VmCredentialStore.TryLoad(vmName, out var savedUsername, out var savedPassword))
        {
            Username = savedUsername;
            InitialPassword = savedPassword;
            RememberCredentials = true;
        }
    }

    public string VmName { get; }
    public string Username { get => _username; set => SetProperty(ref _username, value); }
    public bool RememberCredentials { get => _rememberCredentials; set => SetProperty(ref _rememberCredentials, value); }

    /// <summary>Etape en cours ("Preparation..." puis "Installation...") - affiche a
    /// l'utilisateur pendant que RunBusyAsync tourne, pour ne pas laisser une seule
    /// barre de progression opaque pendant les deux etapes enchainees.</summary>
    public string? ProgressText { get => _progressText; private set => SetProperty(ref _progressText, value); }

    /// <summary>Mot de passe recharge depuis le Gestionnaire d'identifiants Windows si
    /// "Se souvenir de mes identifiants" a ete coche precedemment - applique une seule
    /// fois par la vue (code-behind) a l'ouverture, jamais mis a jour depuis la vue.</summary>
    public string? InitialPassword { get; private set; }

    /// <summary>Cablee par la vue (code-behind) : lit le PasswordBox et retourne
    /// sa valeur. WPF n'expose jamais PasswordBox.Password comme DependencyProperty
    /// (choix de securite delibere) : impossible de le lier via {Binding}.</summary>
    public Func<string>? GetPassword { get; set; }

    public SunshineInstallResultDto? InstallResult { get; private set; }

    public AsyncRelayCommand InstallCommand { get; }
    public RelayCommand CancelCommand { get; }

    public event EventHandler? Completed;
    public event EventHandler? Cancelled;

    private async Task InstallAsync()
    {
        await RunBusyAsync(async () =>
        {
            var password = GetPassword?.Invoke() ?? "";
            if (string.IsNullOrEmpty(password))
            {
                ErrorMessage = Loc.Get("Common_PasswordRequired");
                return;
            }

            ProgressText = Loc.Get("Sunshine_Preparing");
            var (prepResult, prepError) = await _vmService.EnableStreamingAsync(VmName);
            if (prepResult is null)
            {
                ErrorMessage = prepError ?? Loc.Get("Sunshine_PrepFailed");
                ProgressText = null;
                return;
            }

            ProgressText = Loc.Get("Sunshine_Installing");
            var (result, error) = await _vmService.InstallSunshineAutomaticallyAsync(VmName, ResolveUsername(Username), password);
            ProgressText = null;
            if (result is null)
            {
                ErrorMessage = error ?? Loc.Get("Sunshine_InstallFailed");
                return;
            }

            if (RememberCredentials) VmCredentialStore.Save(VmName, Username, password);
            else VmCredentialStore.Delete(VmName);

            InstallResult = result;
            Completed?.Invoke(this, EventArgs.Empty);
        });
    }

    /// <summary>Un compte Microsoft ne peut s'authentifier localement (PowerShell Direct,
    /// runas, etc.) que sous la forme "MicrosoftAccount\email" - jamais l'e-mail seul.
    /// L'utilisateur ne tape que son e-mail : ce prefixe technique est ajoute ici pour lui,
    /// sauf s'il a deja saisi un nom de compte local ou un domaine ("PC\utilisateur").</summary>
    private static string ResolveUsername(string username)
    {
        var trimmed = username.Trim();
        if (trimmed.Contains('@') && !trimmed.Contains('\\'))
        {
            return $"MicrosoftAccount\\{trimmed}";
        }
        return trimmed;
    }
}
