using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Controls;

/// <summary>
/// Le picker de fichier (Microsoft.Win32.OpenFileDialog) est une dependance
/// Windows/WPF concrete : on la cable ici, dans le code-behind de la vue,
/// plutot que dans le ViewModel (qui expose juste un delegue Func&lt;string?&gt;
/// a appeler). Le ViewModel reste ainsi ignorant de WPF.
/// </summary>
public partial class CreateVmDialog : UserControl
{
    public CreateVmDialog()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is CreateVmDialogViewModel viewModel)
        {
            viewModel.BrowseForIsoFile = BrowseForIsoFile;
        }
    }

    private string? BrowseForIsoFile()
    {
        var dialog = new OpenFileDialog
        {
            Title = Loc.Get("CreateVm_FilePickerTitle"),
            Filter = Loc.Get("CreateVm_FilePickerFilter"),
            CheckFileExists = true,
        };
        return dialog.ShowDialog() == true ? dialog.FileName : null;
    }
}
