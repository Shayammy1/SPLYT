using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

/// <summary>Modele de la boite de dialogue demandant les identifiants Windows de la VM
/// pour corriger le blocage de la Session Amelioree sur l'ecran de verrouillage flou
/// (RDP ne gere pas Windows Hello) via NovaVmService.FixEnhancedSessionAsync. Memes
/// garanties de securite que SunshineCredentialsDialogViewModel : identifiants jamais
/// journalises, memorises uniquement si "Se souvenir de mes identifiants" est coche
/// (Gestionnaire d'identifiants Windows, voir VmCredentialStore).</summary>
public sealed class EnhancedSessionFixDialogViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private string _username = "";
    private bool _rememberCredentials;

    public EnhancedSessionFixDialogViewModel(NovaVmService vmService, string vmName)
    {
        _vmService = vmService;
        VmName = vmName;

        FixCommand = new AsyncRelayCommand(FixAsync, () => !string.IsNullOrWhiteSpace(Username));
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

    /// <summary>Mot de passe recharge depuis le Gestionnaire d'identifiants Windows si
    /// "Se souvenir de mes identifiants" a ete coche precedemment - applique une seule
    /// fois par la vue (code-behind) a l'ouverture, jamais mis a jour depuis la vue.</summary>
    public string? InitialPassword { get; private set; }

    /// <summary>Cablee par la vue (code-behind) : lit le PasswordBox et retourne
    /// sa valeur. WPF n'expose jamais PasswordBox.Password comme DependencyProperty
    /// (choix de securite delibere) : impossible de le lier via {Binding}.</summary>
    public Func<string>? GetPassword { get; set; }

    public EnhancedSessionFixResultDto? FixResult { get; private set; }

    public AsyncRelayCommand FixCommand { get; }
    public RelayCommand CancelCommand { get; }

    public event EventHandler? Completed;
    public event EventHandler? Cancelled;

    private async Task FixAsync()
    {
        await RunBusyAsync(async () =>
        {
            var password = GetPassword?.Invoke() ?? "";
            if (string.IsNullOrEmpty(password))
            {
                ErrorMessage = Loc.Get("Common_PasswordRequired");
                return;
            }

            var (result, error) = await _vmService.FixEnhancedSessionAsync(VmName, ResolveUsername(Username), password);
            if (result is null)
            {
                ErrorMessage = error ?? Loc.Get("EnhancedSession_FixFailed");
                return;
            }

            if (RememberCredentials) VmCredentialStore.Save(VmName, Username, password);
            else VmCredentialStore.Delete(VmName);

            FixResult = result;
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
