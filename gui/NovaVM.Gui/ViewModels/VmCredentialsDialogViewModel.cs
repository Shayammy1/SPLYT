using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// Demande les identifiants Windows d'une VM, et rien d'autre : c'est l'appelant
/// qui decide ce qu'il en fait.
///
/// Distincte de SunshineCredentialsDialogViewModel, qui enchaine lui-meme
/// l'installation de Sunshine et n'est donc pas reutilisable. Ici la boite ne
/// connait pas l'action : elle la recoit en delegue. Cela evite d'obliger
/// l'utilisateur a remplir l'onglet Affichage avant de pouvoir cliquer ailleurs,
/// ce qui rendait plusieurs boutons inutilisables sans raison visible.
///
/// Les identifiants ne sont jamais journalises. Ils ne sont memorises que si
/// l'utilisateur le demande, et alors dans le Gestionnaire d'identifiants de
/// Windows (DPAPI, voir VmCredentialStore), jamais en clair dans un fichier.
/// </summary>
public sealed class VmCredentialsDialogViewModel : ViewModelBase
{
    private readonly Func<string, string, Task<string?>> _action;
    private string _username = "";
    private bool _rememberCredentials;
    private string? _progressText;

    /// <param name="action">Recoit le nom d'utilisateur resolu et le mot de passe,
    /// rend null en cas de succes ou le message d'erreur a afficher. La boite reste
    /// ouverte tant qu'une erreur revient, pour que l'utilisateur corrige sa saisie
    /// sans avoir a tout recommencer.</param>
    public VmCredentialsDialogViewModel(
        string vmName, string title, string description, string confirmLabel,
        Func<string, string, Task<string?>> action)
    {
        VmName = vmName;
        Title = title;
        Description = description;
        ConfirmLabel = confirmLabel;
        _action = action;

        ConfirmCommand = new AsyncRelayCommand(ConfirmAsync, () => !string.IsNullOrWhiteSpace(Username));
        CancelCommand = new RelayCommand(() => Cancelled?.Invoke(this, EventArgs.Empty));

        // Pre-remplissage depuis le Gestionnaire d'identifiants : l'interet de la
        // boite est de ne rien avoir a retaper une fois la case cochee.
        if (VmCredentialStore.TryLoad(vmName, out var savedUsername, out var savedPassword))
        {
            Username = savedUsername;
            InitialPassword = savedPassword;
            RememberCredentials = true;
        }
    }

    public string VmName { get; }
    public string Title { get; }
    public string Description { get; }
    public string ConfirmLabel { get; }

    public string Username
    {
        get => _username;
        set { if (SetProperty(ref _username, value)) ConfirmCommand.RaiseCanExecuteChanged(); }
    }

    public bool RememberCredentials { get => _rememberCredentials; set => SetProperty(ref _rememberCredentials, value); }

    /// <summary>Etape en cours, affichee pendant que l'action tourne.</summary>
    public string? ProgressText { get => _progressText; private set => SetProperty(ref _progressText, value); }

    /// <summary>Mot de passe recharge depuis le Gestionnaire d'identifiants, applique
    /// une seule fois par la vue a l'ouverture : WPF n'expose pas PasswordBox.Password
    /// comme propriete de dependance, aucune liaison n'est possible.</summary>
    public string? InitialPassword { get; }

    /// <summary>Cablee par la vue (code-behind), pour la meme raison.</summary>
    public Func<string>? GetPassword { get; set; }

    public AsyncRelayCommand ConfirmCommand { get; }
    public RelayCommand CancelCommand { get; }

    public event EventHandler? Completed;
    public event EventHandler? Cancelled;

    private async Task ConfirmAsync()
    {
        await RunBusyAsync(async () =>
        {
            var password = GetPassword?.Invoke() ?? "";
            if (string.IsNullOrEmpty(password))
            {
                ErrorMessage = Loc.Get("Common_PasswordRequired");
                return;
            }

            ErrorMessage = null;
            ProgressText = Loc.Get("VmCredentials_Working");

            var error = await _action(ResolveUsername(Username), password);

            ProgressText = null;
            if (error is not null)
            {
                ErrorMessage = error;
                return;
            }

            if (RememberCredentials) VmCredentialStore.Save(VmName, Username, password);
            else VmCredentialStore.Delete(VmName);

            Completed?.Invoke(this, EventArgs.Empty);
        });
    }

    /// <summary>Un compte Microsoft ne s'authentifie localement que sous la forme
    /// "MicrosoftAccount\email" - jamais l'e-mail seul. L'utilisateur ne tape que son
    /// e-mail, le prefixe technique est ajoute pour lui.</summary>
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
