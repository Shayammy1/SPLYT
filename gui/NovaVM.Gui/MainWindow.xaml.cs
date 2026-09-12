using System.Windows.Input;
using NovaVM.Gui.ViewModels;
using Wpf.Ui.Controls;

namespace NovaVM.Gui;

/// <summary>
/// Fenetre principale : coquille (barre laterale + zone de contenu) dont tout le
/// contenu reel est pilote par MainViewModel (voir App.xaml.cs pour le cablage
/// du DataContext, et App.xaml pour les DataTemplates ViewModel -> Vue).
/// </summary>
public partial class MainWindow : FluentWindow
{
    public MainWindow()
    {
        InitializeComponent();
        PreviewKeyDown += OnPreviewKeyDown;

        // La taille declaree dans le XAML (1320x820) suppose un grand ecran. Sur un
        // portable de 1366x768, ou sur un ecran fortement mis a l'echelle, la
        // fenetre depassait et une partie de l'interface se retrouvait hors champ,
        // sans moyen de la ramener. On la ramene donc a ce que l'ecran peut
        // reellement afficher.
        //
        // Au moment de SourceInitialized et pas dans le constructeur : la fenetre a
        // alors une poignee, donc un ecran identifiable et un facteur d'echelle
        // connu. MinWidth/MinHeight du XAML restent respectes par WPF.
        SourceInitialized += (_, _) => Services.ScreenFit.FitToScreen(this);
    }

    /// <summary>Ctrl+K amene le curseur dans la recherche, comme l'indique la
    /// pastille affichee au bout du champ.</summary>
    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.K || (Keyboard.Modifiers & ModifierKeys.Control) != ModifierKeys.Control) return;

        ShellSearchBox.Focus();
        ShellSearchBox.SelectAll();
        e.Handled = true;
    }

    /// <summary>Le champ filtre la liste des VMs : y entrer depuis l'accueil doit
    /// aussi basculer sur la page qui montre le resultat du filtrage.</summary>
    private void ShellSearchBox_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        (DataContext as MainViewModel)?.GoToVmList();
    }
}
