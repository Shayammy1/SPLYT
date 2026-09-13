using System.ComponentModel;
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
/// Elle ne se ferme PAS d'elle-meme : ni croix, ni Alt+F4. Le seul moyen de la
/// retirer est le bouton de la page d'accueil. Une superposition de surveillance
/// qu'un clic ou un raccourci malheureux fait disparaitre ne surveille plus rien,
/// et on ne s'en apercoit qu'au moment ou on la cherche.
///
/// Volontairement deplacable et non "traversante" : une fenetre qui laisse
/// passer les clics est invisible a la souris, donc impossible a ecarter quand
/// elle gene. Ici il suffit de l'attraper.
/// </summary>
public partial class UsageOverlayWindow : Window
{
    private bool _allowClose;

    public UsageOverlayWindow(Window? owner)
    {
        InitializeComponent();
        MouseLeftButtonDown += OnDrag;
        Loaded += (_, _) => MoveToTopRight();
        Closing += OnClosing;

        if (owner is not null)
        {
            Owner = owner;

            // Quand SPLYT se ferme, ses fenetres filles doivent suivre : sans cette
            // levee de garde, le refus de fermeture laisserait une superposition
            // orpheline a l'ecran, et l'application ne se terminerait jamais.
            owner.Closing += (_, _) => _allowClose = true;
        }
    }

    /// <summary>Seule facon legitime de la retirer : le bouton de l'accueil.</summary>
    public void CloseFromToggle()
    {
        _allowClose = true;
        Close();
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!_allowClose) e.Cancel = true;
    }

    /// <summary>Coin superieur droit de l'ecran qui porte la fenetre principale de
    /// SPLYT, et non de l'ecran principal : sur un poste a plusieurs ecrans, c'est
    /// la que l'utilisateur regarde.</summary>
    private void MoveToTopRight()
    {
        var reference = Owner ?? Application.Current?.MainWindow;
        var work = reference is null
            ? new Services.ScreenFit.Rect<double>(
                SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width, SystemParameters.WorkArea.Height)
            : Services.ScreenFit.GetWorkArea(reference);

        // La marge de 10 du Border fait deja respirer le bord : on colle donc au
        // coin sans ajouter d'ecart supplementaire.
        Left = work.Left + work.Width - ActualWidth;
        Top = work.Top;
    }

    private void OnDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) DragMove();
    }
}
