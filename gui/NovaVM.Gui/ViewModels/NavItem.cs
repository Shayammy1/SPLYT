namespace NovaVM.Gui.ViewModels;

/// <summary>Une entree de la barre laterale : icone + titre + le ViewModel de la page associee.</summary>
public sealed class NavItem
{
    public required string Title { get; init; }
    public required string Icon { get; init; }
    public required object ViewModel { get; init; }
}
