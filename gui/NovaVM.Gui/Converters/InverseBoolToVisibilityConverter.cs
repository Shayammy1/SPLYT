using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace NovaVM.Gui.Converters;

/// <summary>Visible quand la valeur est fausse. Complement de
/// BooleanToVisibilityConverter, qui ne sait pas s'inverser : utilise pour les
/// elements que la barre laterale reduite doit masquer (titres, sous-titres).</summary>
public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is Visibility.Collapsed;
}
