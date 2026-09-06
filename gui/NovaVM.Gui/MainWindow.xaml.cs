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
    }
}
