using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>Choix de la langue propose au tout premier demarrage de SPLYT, avant
/// toute autre chose (voir MainViewModel.RunFirstRunFlowAsync). N'apparait qu'une
/// seule fois : des que l'utilisateur valide, la langue est ecrite dans les
/// preferences et Loc.NeedsLanguageChoice devient faux definitivement.
///
/// Ses libelles ne passent PAS par Loc : la langue de l'interface n'est justement
/// pas encore choisie, donc les deux options sont ecrites chacune dans sa propre
/// langue (comme le fait n'importe quel selecteur de langue).</summary>
public sealed class LanguageChoiceDialogViewModel : ViewModelBase
{
    private AppLanguage _selectedLanguage = AppLanguage.English;

    public LanguageChoiceDialogViewModel()
    {
        ConfirmCommand = new RelayCommand(Confirm);
    }

    public IReadOnlyList<AppLanguage> AvailableLanguages { get; } =
        new[] { AppLanguage.English, AppLanguage.French };

    public AppLanguage SelectedLanguage { get => _selectedLanguage; set => SetProperty(ref _selectedLanguage, value); }

    public RelayCommand ConfirmCommand { get; }

    /// <summary>Emis une fois la langue enregistree. RestartNeeded est vrai si la
    /// langue choisie n'est pas celle deja chargee par l'application : les textes
    /// deja affiches ne changent qu'au demarrage suivant (voir Loc), donc la
    /// coquille relance SPLYT immediatement plutot que de laisser une interface
    /// dans la mauvaise langue.</summary>
    public event EventHandler<bool>? Confirmed;

    private void Confirm()
    {
        var restartNeeded = SelectedLanguage != Loc.CurrentLanguage;
        Loc.SetLanguage(SelectedLanguage);
        Confirmed?.Invoke(this, restartNeeded);
    }
}
