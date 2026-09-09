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
