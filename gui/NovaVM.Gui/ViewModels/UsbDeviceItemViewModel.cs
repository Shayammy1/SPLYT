using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// Une ligne de la liste des peripheriques USB de l'hote, dans l'onglet
/// Peripheriques d'une VM.
///
/// Trois etats possibles, et un seul compte vraiment pour l'utilisateur : tant
/// qu'un peripherique n'est pas PRIS par la VM, il continue de piloter l'hote.
/// "Partage" est un etat intermediaire d'usbipd (le peripherique est disponible
/// mais personne ne l'a saisi) qu'il ne faut surtout pas presenter comme une
/// reussite.
/// </summary>
public sealed class UsbDeviceItemViewModel : ObservableObject
{
    private bool _shared;
    private bool _attached;
    private string? _clientIp;
    private bool _isSelected;
    private bool _isActive;
    private bool _reserved;
    private bool _vmIsRunning;

    public UsbDeviceItemViewModel(UsbDeviceDto dto)
    {
        BusId = dto.BusId ?? "";
        Description = string.IsNullOrWhiteSpace(dto.Description)
            ? Loc.Get("VmList_Usb_UnknownDevice")
            : dto.Description!;
        LikelyInput = dto.LikelyInput;
        HardwareLabel = ExtractVidPid(dto.InstanceId);
        _shared = dto.Shared;
        _attached = dto.Attached;
        _clientIp = dto.ClientIp;
    }

    public string BusId { get; }
    public string Description { get; }
    public bool LikelyInput { get; }

    /// <summary>Identite materielle ("1bcf:0005"). Windows nomme la plupart des
    /// souris et claviers "Peripherique d'entree USB", a l'identique : sans ce
    /// repere ni le numero de port, deux lignes de la liste sont impossibles a
    /// distinguer.</summary>
    public string HardwareLabel { get; }

    /// <summary>"port 3-3 - 1bcf:0005", affiche sous le nom.</summary>
    public string IdentityText => string.IsNullOrEmpty(HardwareLabel)
        ? Loc.Get("VmList_Usb_Port", BusId)
        : Loc.Get("VmList_Usb_PortAndId", BusId, HardwareLabel);

    /// <summary>"USB\VID_1BCF&amp;PID_0005\..." -> "1bcf:0005". Chaine vide si le
    /// format n'est pas celui attendu : mieux vaut ne rien afficher qu'un repere
    /// faux.</summary>
    private static string ExtractVidPid(string? instanceId)
    {
        if (string.IsNullOrEmpty(instanceId)) return "";
        var match = System.Text.RegularExpressions.Regex.Match(
            instanceId, @"VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})");
        return match.Success
            ? $"{match.Groups[1].Value.ToLowerInvariant()}:{match.Groups[2].Value.ToLowerInvariant()}"
            : "";
    }

    public bool Shared
    {
        get => _shared;
        set { if (SetProperty(ref _shared, value)) NotifyDerived(); }
    }

    public bool Attached
    {
        get => _attached;
        set { if (SetProperty(ref _attached, value)) NotifyDerived(); }
    }

    public string? ClientIp
    {
        get => _clientIp;
        set { if (SetProperty(ref _clientIp, value)) NotifyDerived(); }
    }

    /// <summary>Coche dans la fenetre du bouton SPLYT : ce peripherique sera confie
    /// a la VM a la fin de la configuration. Inutilise dans l'onglet Peripheriques,
    /// ou l'action se fait ligne par ligne.</summary>
    public bool IsSelected { get => _isSelected; set => SetProperty(ref _isSelected, value); }

    /// <summary>Le temoin d'identification : vrai pendant un court instant apres que
    /// ce peripherique a servi. Bouger la souris ou appuyer sur une touche allume
    /// sa ligne, seul moyen de la reconnaitre quand Windows les nomme toutes
    /// pareil. Voir UsbActivityTracker.</summary>
    public bool IsActive { get => _isActive; set => SetProperty(ref _isActive, value); }

    /// <summary>Date du dernier evenement, lue par le temporisateur qui eteint.</summary>
    public DateTime LastActivityUtc { get; set; }

    /// <summary>Ce peripherique est promis a la VM selectionnee. Se pose machine
    /// eteinte, quand le rattachement reel est impossible : "usbip attach" tourne
    /// dans l'invite et va chercher le peripherique par le reseau.</summary>
    public bool Reserved
    {
        get => _reserved;
        set { if (SetProperty(ref _reserved, value)) NotifyDerived(); }
    }

    /// <summary>Etat de la VM selectionnee, recopie a chaque rafraichissement : c'est
    /// lui qui decide si le bouton de la ligne confie le peripherique tout de suite
    /// ou se contente de le reserver.</summary>
    public bool VmIsRunning
    {
        get => _vmIsRunning;
        set { if (SetProperty(ref _vmIsRunning, value)) NotifyDerived(); }
    }

    /// <summary>Ce que fait le bouton de la ligne. Quatre cas et non deux : machine
    /// eteinte, on ne peut que promettre.</summary>
    public string ActionLabel
    {
        get
        {
            if (!VmIsRunning) return Loc.Get(Reserved ? "VmList_Usb_Unreserve" : "VmList_Usb_Reserve");
            return Loc.Get(Attached ? "VmList_Usb_GiveBack" : "VmList_Usb_GiveToVm");
        }
    }

    public string StateText
    {
        get
        {
            if (Attached) return Loc.Get("VmList_Usb_State_Attached", ClientIp ?? "");
            // La reservation prime sur "partage" dans l'affichage : c'est
            // l'information utile, et un peripherique reserve est toujours partage.
            if (Reserved) return Loc.Get("VmList_Usb_State_Reserved");
            if (Shared) return Loc.Get("VmList_Usb_State_Shared");
            return Loc.Get("VmList_Usb_State_OnHost");
        }
    }

    private void NotifyDerived()
    {
        OnPropertyChanged(nameof(ActionLabel));
        OnPropertyChanged(nameof(StateText));
    }
}
