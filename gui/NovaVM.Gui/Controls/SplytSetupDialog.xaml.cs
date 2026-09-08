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
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is SplytSetupDialogViewModel viewModel)
        {
            viewModel.GetPassword = () => PasswordInput.Password;
            if (!string.IsNullOrEmpty(viewModel.InitialPassword))
            {
                PasswordInput.Password = viewModel.InitialPassword;
            }
        }
    }
}
