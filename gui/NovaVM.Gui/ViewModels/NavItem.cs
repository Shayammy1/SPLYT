using Wpf.Ui.Controls;

namespace NovaVM.Gui.ViewModels;

/// <summary>Une entree de la barre laterale : icone + titre + le ViewModel de la page
/// associee.
///
/// L'icone est un symbole Fluent (fourni par WPF-UI, deja reference par le projet) et
/// non plus un caractere emoji : les emoji sont rendus par la police de l'utilisateur,
/// donc en couleurs, a une taille et un alignement qu'on ne maitrise pas, et ils
/// juraient avec le reste de l'interface.</summary>
public sealed class NavItem
{
    public required string Title { get; init; }
    public required SymbolRegular Icon { get; init; }
    public required object ViewModel { get; init; }
}
