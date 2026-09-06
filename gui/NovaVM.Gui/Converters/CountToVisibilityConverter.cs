using System.Collections;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace NovaVM.Gui.Converters;

/// <summary>
/// Convertit un nombre (ou Count d'une collection) en Visibility. Par defaut,
/// visible quand le nombre est superieur a 0. Avec ConverterParameter="Invert",
/// visible quand le nombre vaut 0 (utile pour les messages "aucun element").
/// </summary>
public sealed class CountToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var count = value switch
        {
            int i => i,
            ICollection c => c.Count,
            _ => 0,
        };

        var invert = string.Equals(parameter as string, "Invert", StringComparison.OrdinalIgnoreCase);
        var isEmpty = count == 0;
        var visible = invert ? isEmpty : !isEmpty;
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
