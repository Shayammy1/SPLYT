using System.Windows;
using System.Windows.Controls;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Controls;

/// <summary>Le PasswordBox n'expose pas sa valeur comme DependencyProperty (choix
/// de securite WPF delibere, evite qu'un mot de passe transite par le systeme de
/// binding/logging) : on le lit directement ici, dans le code-behind, jamais via
/// {Binding}.</summary>
public partial class SunshineCredentialsDialog : UserControl
{
    public SunshineCredentialsDialog()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is SunshineCredentialsDialogViewModel viewModel)
        {
            viewModel.GetPassword = () => PasswordInput.Password;
            if (!string.IsNullOrEmpty(viewModel.InitialPassword))
            {
                PasswordInput.Password = viewModel.InitialPassword;
            }
        }
    }
}
