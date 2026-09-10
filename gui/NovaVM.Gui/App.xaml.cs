using System.Windows;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.PowerShell;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui;

/// <summary>
/// Point d'entree de l'application. StartupUri n'est pas utilise dans App.xaml :
/// le demarrage est fait ici a la main pour construire la "composition root"
/// (services + ViewModel principal) avant de creer et afficher la fenetre.
/// Pas de conteneur DI : l'appli reste assez petite pour qu'un cablage manuel
/// simple soit plus lisible qu'une dependance supplementaire.
/// </summary>
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        IPowerShellRunner runner = new PowerShellRunner();
        var log = new LogService();
        var vmService = new NovaVmService(runner, log);
        var mainViewModel = new MainViewModel(vmService, log);

        var mainWindow = new MainWindow
        {
            DataContext = mainViewModel,
        };
        // Arrete automatiquement les VMs en cours d'execution a la fermeture de SPLYT.
        // Best-effort et non-bloquant : Hyper-V traite chaque arret independamment du
        // processus SPLYT, la fenetre n'a pas besoin d'attendre la fin reelle.
        mainWindow.Closing += (_, _) =>
        {
            // Les consoles d'abord : leur processus vmconnect est un processus
            // separe, qui ne disparait pas parce que SPLYT se ferme. Sans cette
            // fermeture explicite, il survit sans fenetre visible et garde une
            // connexion ouverte sur la VM.
            mainViewModel.CloseAllConsoleWindows();
            _ = vmService.StopAllRunningVmsAsync();
        };
        mainWindow.Show();
    }
}
