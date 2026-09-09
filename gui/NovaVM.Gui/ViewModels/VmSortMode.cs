namespace NovaVM.Gui.ViewModels;

/// <summary>Ordre d'affichage de la liste des VMs (voir VmListViewModel.SortMode).</summary>
public enum VmSortMode
{
    /// <summary>VMs en cours d'execution d'abord, puis par nom. Choix par defaut :
    /// c'est la machine qui tourne qu'on cherche en premier.</summary>
    State,

    /// <summary>Ordre alphabetique pur.</summary>
    Name,
}
