using System.Windows;
using System.Windows.Input;

namespace NovaVM.Gui.Controls;

/// <summary>
/// Petite superposition posee par-dessus tout, en haut a droite : CPU, RAM et
/// GPU de l'hote d'un coup d'oeil, sans revenir dans SPLYT.
///
/// Elle suit les memes chiffres que la page d'accueil - son DataContext EST le
/// DashboardViewModel - plutot que d'echantillonner de son cote : deux mesures
/// concurrentes du meme CPU donneraient deux valeurs differentes au meme
/// instant, et l'une des deux passerait pour fausse.
///
/// Volontairement deplacable et non "traversante" : une fenetre qui laisse
/// passer les clics est invisible a la souris, donc impossible a ecarter quand
/// elle gene. Ici il suffit de l'attraper.
/// </summary>
public partial class UsageOverlayWindow : Window
{
    public UsageOverlayWindow()
    {
        InitializeComponent();
        MouseLeftButtonDown += OnDrag;
        Loaded += (_, _) => MoveToTopRight();
    }

    /// <summary>Coin superieur droit de l'ecran qui porte la fenetre principale de
    /// SPLYT, et non de l'ecran principal : sur un poste a plusieurs ecrans, c'est
    /// la que l'utilisateur regarde.</summary>
    private void MoveToTopRight()
    {
        var owner = Owner ?? Application.Current?.MainWindow;
        var work = owner is null
            ? new Services.ScreenFit.Rect<double>(
                SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width, SystemParameters.WorkArea.Height)
            : Services.ScreenFit.GetWorkArea(owner);

        // La marge de 10 du Border fait deja respirer le bord : on colle donc au
        // coin sans ajouter d'ecart supplementaire.
        Left = work.Left + work.Width - ActualWidth;
        Top = work.Top;
    }

    private void OnDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) DragMove();
    }

    private void OnCloseClicked(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        Close();
    }
}
