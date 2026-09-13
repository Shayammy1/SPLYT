using System.Windows;
using System.Windows.Controls;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Controls;

/// <summary>Meme raison que SunshineCredentialsDialog : le PasswordBox n'expose pas
/// sa valeur comme DependencyProperty (choix de securite WPF delibere), elle se lit
/// donc ici et jamais via {Binding}.</summary>
public partial class SplytSetupDialog : UserControl
{
    public SplytSetupDialog()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;

        // Filet de securite : selon la facon dont la coquille retire la fenetre,
        // DataContextChanged peut ne jamais annoncer l'ancien contexte. Sans ca,
        // l'ecoute des entrees resterait armee apres la fermeture.
        Unloaded += (_, _) => (DataContext as SplytSetupDialogViewModel)?.UsbActivity.Stop();
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is SplytSetupDialogViewModel previous) previous.UsbActivity.Stop();

        if (e.NewValue is SplytSetupDialogViewModel viewModel)
        {
            viewModel.GetPassword = () => PasswordInput.Password;
            if (!string.IsNullOrEmpty(viewModel.InitialPassword))
            {
                PasswordInput.Password = viewModel.InitialPassword;
            }

            // Temoins d'identification actifs tant que cette fenetre est affichee.
            // Elle est detruite a la fermeture (DataContext remis a null par la
            // coquille), ce qui rend l'ecoute.
            viewModel.UsbActivity.Start();
        }
    }
}
