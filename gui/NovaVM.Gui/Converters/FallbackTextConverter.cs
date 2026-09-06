using System.Globalization;
using System.Windows.Data;

namespace NovaVM.Gui.Converters;

/// <summary>Retourne ConverterParameter si value est nul/vide, sinon value tel quel.
/// Utilise par exemple pour afficher "Aucun GPU" quand VirtualMachine.GpuName est null.</summary>
public sealed class FallbackTextConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var text = value as string;
        return string.IsNullOrWhiteSpace(text) ? (parameter as string ?? "-") : text;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
