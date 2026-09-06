using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace NovaVM.Gui.Mvvm;

/// <summary>
/// Base MVVM minimale (pas de dependance externe type CommunityToolkit.Mvvm) :
/// juste INotifyPropertyChanged + un helper SetProperty, utilisee par les
/// modeles observables (Models/) et les ViewModels (ViewModels/).
/// </summary>
public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
