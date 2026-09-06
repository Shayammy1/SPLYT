using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;
using NovaVM.Gui.Models;

namespace NovaVM.Gui.Converters;

/// <summary>Convertit un VmState en couleur d'accent pour le badge de statut d'une VM.</summary>
public sealed class VmStateToBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush Success = new((Color)ColorConverter.ConvertFromString("#34D399")!);
    private static readonly SolidColorBrush Warning = new((Color)ColorConverter.ConvertFromString("#FBBF24")!);
    private static readonly SolidColorBrush Danger = new((Color)ColorConverter.ConvertFromString("#F87171")!);
    private static readonly SolidColorBrush Muted = new((Color)ColorConverter.ConvertFromString("#5C6377")!);

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not VmState state) return Muted;
        return state switch
        {
            VmState.Running => Success,
            VmState.Starting or VmState.Stopping => Warning,
            VmState.Error => Danger,
            _ => Muted,
        };
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
