using System.Globalization;
using System.Windows.Data;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.Converters;

/// <summary>Affiche chaque langue dans SON PROPRE nom ("Francais"/"English"), pas dans
/// la langue active - convention habituelle des selecteurs de langue.</summary>
public sealed class AppLanguageToLabelConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value switch
    {
        AppLanguage.French => "Francais",
        AppLanguage.English => "English",
        _ => value?.ToString() ?? "",
    };

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
