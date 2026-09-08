using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>Boite d'information purement explicative (titre + texte + un seul bouton
/// de fermeture), avec une case "Ne plus afficher a l'avenir" optionnelle. Utilisee
/// pour expliquer l'onglet GPU-P la premiere fois qu'on l'ouvre : la fonctionnalite
/// est le coeur de SPLYT mais son nom ne dit rien a quelqu'un qui decouvre.</summary>
public sealed class InfoDialogViewModel : ViewModelBase
{
    private bool _dontShowAgain;

    public InfoDialogViewModel(string title, string message, bool showDontShowAgain = false)
    {
        Title = title;
        Message = message;
        ShowDontShowAgain = showDontShowAgain;
        CloseLabel = Loc.Get("Common_Close");
        DontShowAgainLabel = Loc.Get("Common_DontShowAgain");

        CloseCommand = new RelayCommand(() => Closed?.Invoke(this, DontShowAgain));
    }

    public string Title { get; }
    public string Message { get; }
    public string CloseLabel { get; }
    public string DontShowAgainLabel { get; }
    public bool ShowDontShowAgain { get; }

    public bool DontShowAgain { get => _dontShowAgain; set => SetProperty(ref _dontShowAgain, value); }

    public RelayCommand CloseCommand { get; }

    /// <summary>Emis a la fermeture, avec l'etat final de la case "Ne plus afficher".</summary>
    public event EventHandler<bool>? Closed;
}
