using System.Windows.Markup;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.Markup;

/// <summary>Extension XAML {markup:Tr Cle} : resout une cle de traduction vers le texte
/// de la langue active (voir Loc). Resolue une seule fois au chargement de la vue - le
/// changement de langue prend effet au redemarrage de SPLYT (choix assume, voir Loc).</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TrExtension : MarkupExtension
{
    public TrExtension() { }

    public TrExtension(string key) => Key = key;

    [ConstructorArgument("key")]
    public string Key { get; set; } = "";

    public override object ProvideValue(IServiceProvider serviceProvider) => Loc.Get(Key);
}
