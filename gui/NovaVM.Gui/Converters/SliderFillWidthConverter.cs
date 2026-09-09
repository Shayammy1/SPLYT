using System.Globalization;
using System.Windows.Data;

namespace NovaVM.Gui.Converters;

/// <summary>
/// Largeur de la portion coloree d'un slider, en pixels. Le rendu "piste remplie"
/// passe habituellement par le DecreaseRepeatButton du Track ; celui-ci ne dessine
/// rien ici (verifie a l'ecran, y compris avec une couleur criarde), donc la
/// portion parcourue est calculee explicitement.
/// Entrees : Value, Minimum, Maximum, ActualWidth du slider.
/// </summary>
public sealed class SliderFillWidthConverter : IMultiValueConverter
{
    /// <summary>Diametre du curseur, cf. FilledSliderStyle : la piste utile est
    /// amputee de cette largeur, et le remplissage doit s'arreter au centre du
    /// curseur, pas a son bord.</summary>
    private const double ThumbWidth = 18;

    public object Convert(object?[] values, Type targetType, object? parameter, CultureInfo culture)
    {
        if (values.Length < 4) return 0d;
        if (values[0] is not double value || values[1] is not double min ||
            values[2] is not double max || values[3] is not double totalWidth)
        {
            return 0d;
        }

        var range = max - min;
        var usable = totalWidth - ThumbWidth;
        if (range <= 0 || usable <= 0) return 0d;

        var ratio = Math.Clamp((value - min) / range, 0, 1);
        return ratio * usable + ThumbWidth / 2;
    }

    public object[] ConvertBack(object? value, Type[] targetTypes, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
