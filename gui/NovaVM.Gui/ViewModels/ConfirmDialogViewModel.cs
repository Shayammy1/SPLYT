using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>Choix effectue par l'utilisateur dans une ConfirmDialogViewModel.</summary>
public enum ConfirmChoice
{
    Cancel,
    Primary,
    Secondary,
}

/// <summary>Boite de dialogue de confirmation generique (titre + message + 1 ou 2
/// actions + Annuler), affichee par MainViewModel comme les autres modales.
/// Mutualisee plutot que dupliquee : elle sert aussi bien au choix du type d'arret
/// d'une VM (deux actions : classique / force) qu'a la confirmation de suppression
/// (une seule action, presentee comme destructive).</summary>
public sealed class ConfirmDialogViewModel : ViewModelBase
{
    /// <param name="secondaryLabel">null pour n'afficher qu'une seule action.</param>
    /// <param name="primaryIsDanger">Presente l'action principale comme destructive
    /// (bouton rouge) plutot que comme l'action normale.</param>
    public ConfirmDialogViewModel(
        string title, string message, string primaryLabel, string? secondaryLabel = null, bool primaryIsDanger = false)
    {
        Title = title;
        Message = message;
        PrimaryLabel = primaryLabel;
        SecondaryLabel = secondaryLabel;
        PrimaryIsDanger = primaryIsDanger;
        CancelLabel = Loc.Get("Common_Cancel");

        PrimaryCommand = new RelayCommand(() => Close(ConfirmChoice.Primary));
        SecondaryCommand = new RelayCommand(() => Close(ConfirmChoice.Secondary));
        CancelCommand = new RelayCommand(() => Close(ConfirmChoice.Cancel));
    }

    public string Title { get; }
    public string Message { get; }
    public string PrimaryLabel { get; }
    public string? SecondaryLabel { get; }
    public string CancelLabel { get; }

    public bool PrimaryIsDanger { get; }

    /// <summary>Complementaire de PrimaryIsDanger : la vue choisit le style du bouton
    /// principal par Visibility sur deux boutons, WPF ne permettant pas de selectionner
    /// un Style par binding aussi simplement.</summary>
    public bool PrimaryIsAccent => !PrimaryIsDanger;

    public bool HasSecondary => !string.IsNullOrEmpty(SecondaryLabel);

    public RelayCommand PrimaryCommand { get; }
    public RelayCommand SecondaryCommand { get; }
    public RelayCommand CancelCommand { get; }

    /// <summary>Emis exactement une fois, avec le choix retenu (Cancel si la boite est
    /// simplement fermee).</summary>
    public event EventHandler<ConfirmChoice>? Closed;

    private bool _closed;

    private void Close(ConfirmChoice choice)
    {
        if (_closed) return;
        _closed = true;
        Closed?.Invoke(this, choice);
    }
}
