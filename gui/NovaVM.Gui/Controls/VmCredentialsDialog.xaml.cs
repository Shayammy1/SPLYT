using System.Windows;
using System.Windows.Controls;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Controls;

/// <summary>Le PasswordBox n'expose pas sa valeur comme propriete de dependance
/// (choix de securite WPF delibere, pour qu'un mot de passe ne transite jamais par
/// le systeme de liaison ni par ses journaux) : on le lit ici, dans le
/// code-behind, jamais via {Binding}.</summary>
public partial class VmCredentialsDialog : UserControl
{
    public VmCredentialsDialog()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is not VmCredentialsDialogViewModel viewModel) return;

        viewModel.GetPassword = () => PasswordInput.Password;
        if (!string.IsNullOrEmpty(viewModel.InitialPassword))
        {
            PasswordInput.Password = viewModel.InitialPassword;
        }

        // Le champ pertinent depend de ce qui est deja rempli : avec des
        // identifiants memorises, il ne reste rien a taper et le bouton doit etre
        // atteignable tout de suite.
        if (string.IsNullOrWhiteSpace(viewModel.Username)) Dispatcher.BeginInvoke(() => PasswordInput.Focus());
    }
}
