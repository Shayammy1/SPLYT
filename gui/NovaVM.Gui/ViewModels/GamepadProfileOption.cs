using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// Une manette que Sunshine sait faire apparaitre dans la VM.
///
/// Les cinq valeurs sont celles que Sunshine accepte reellement, relevees dans
/// son binaire et non devinees d'apres sa documentation.
///
/// Pourquoi ce choix existe : laisse sur "auto", Sunshine emule une DualShock 4
/// des qu'il detecte un pave tactile ou des capteurs de mouvement cote client -
/// ce que fait justement une DualSense. Or une DS4 est un peripherique
/// DirectInput/HID, pas XInput : les jeux qui ne gerent que XInput ne la voient
/// pas du tout. D'ou "Xbox 360" propose par defaut ici, et non "automatique".
/// </summary>
public sealed class GamepadProfileOption
{
    private GamepadProfileOption(string value, string labelKey, string descriptionKey)
    {
        Value = value;
        LabelKey = labelKey;
        DescriptionKey = descriptionKey;
    }

    /// <summary>Ce qui est ecrit dans sunshine.conf ("x360", "ds4"...).</summary>
    public string Value { get; }

    private string LabelKey { get; }
    private string DescriptionKey { get; }

    /// <summary>Traduits a la lecture et non a la construction : la liste est
    /// statique, elle survivrait a un changement de langue si elle figeait les
    /// libelles une fois pour toutes.</summary>
    public string Label => Loc.Get(LabelKey);
    public string Description => Loc.Get(DescriptionKey);

    public override string ToString() => Label;

    /// <summary>Xbox 360 en deuxieme position et choisi par defaut (voir le
    /// constructeur du ViewModel) : c'est la seule valeur qui garantisse XInput,
    /// donc la compatibilite avec tous les jeux.</summary>
    public static IReadOnlyList<GamepadProfileOption> All { get; } = new[]
    {
        new GamepadProfileOption("auto", "VmList_Gamepad_Profile_Auto", "VmList_Gamepad_Profile_Auto_Desc"),
        new GamepadProfileOption("x360", "VmList_Gamepad_Profile_X360", "VmList_Gamepad_Profile_X360_Desc"),
        new GamepadProfileOption("xone", "VmList_Gamepad_Profile_XOne", "VmList_Gamepad_Profile_XOne_Desc"),
        new GamepadProfileOption("ds4", "VmList_Gamepad_Profile_Ds4", "VmList_Gamepad_Profile_Ds4_Desc"),
        new GamepadProfileOption("switch", "VmList_Gamepad_Profile_Switch", "VmList_Gamepad_Profile_Switch_Desc"),
    };
}
