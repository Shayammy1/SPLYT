using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Views;

public partial class VmListView : UserControl
{
    public VmListView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    /// <summary>Cable le PasswordBox de l'onglet "Virtual Display Driver" au ViewModel
    /// (WPF n'expose jamais PasswordBox.Password comme DependencyProperty - choix de
    /// securite delibere - donc pas de {Binding} possible), et le pre-remplit quand la
    /// VM selectionnee change et qu'un mot de passe memorise existe pour elle.</summary>
    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is VmListViewModel oldViewModel)
        {
            oldViewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }

        if (e.NewValue is VmListViewModel viewModel)
        {
            viewModel.VddGetPassword = () => VddPasswordInput.Password;
            viewModel.GamingGetPassword = () => GamingPasswordInput.Password;
            viewModel.BrowseForNvidiaDriverFile = BrowseForNvidiaDriverFile;
            viewModel.PropertyChanged += OnViewModelPropertyChanged;
        }
    }

    private string? BrowseForNvidiaDriverFile()
    {
        var dialog = new OpenFileDialog
        {
            Title = Loc.Get("VmList_Nvidia_FilePickerTitle"),
            Filter = Loc.Get("VmList_Nvidia_FilePickerFilter"),
            CheckFileExists = true,
        };
        return dialog.ShowDialog() == true ? dialog.FileName : null;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(VmListViewModel.SelectedVm) && DataContext is VmListViewModel viewModel)
        {
            VddPasswordInput.Password = viewModel.VddInitialPassword ?? "";
            GamingPasswordInput.Password = viewModel.GamingInitialPassword ?? "";
        }
    }
}
