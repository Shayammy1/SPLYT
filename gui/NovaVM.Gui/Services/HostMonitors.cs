using System.Runtime.InteropServices;

namespace NovaVM.Gui.Services;

/// <summary>
/// Liste les ecrans de l'hote, avec leur definition reelle.
///
/// Pourquoi passer par EnumDisplayDevices/EnumDisplaySettings plutot que par les
/// rectangles d'ecran habituels (MonitorFromWindow, SystemParameters...) : ceux-ci
/// sont exprimes dans le systeme de coordonnees de l'application qui les demande,
/// donc DIVISES par la mise a l'echelle quand Windows virtualise les coordonnees.
/// Un ecran 3840x2160 a 150 % s'annoncerait alors 2560x1440, et l'utilisateur ne
/// reconnaitrait pas son materiel dans la liste. Le mode d'affichage courant, lui,
/// est toujours donne en pixels reels, quelle que soit l'application qui le lit.
/// </summary>
internal static class HostMonitors
{
    /// <summary>Un ecran physique actuellement branche et actif.</summary>
    /// <param name="DeviceName">Nom Windows de l'affichage ("\\.\DISPLAY2"). C'est
    /// cette valeur qui est transmise au script de lancement : contrairement a des
    /// coordonnees, elle ne depend d'aucune mise a l'echelle.</param>
    /// <param name="Number">Numero affiche a l'utilisateur, tire du nom de
    /// l'affichage - le meme que celui des parametres Windows dans les cas
    /// courants.</param>
    internal sealed record Monitor(string DeviceName, int Number, int Width, int Height, bool IsPrimary);

    private const int EnumCurrentSettings = -1;
    private const int DisplayDeviceAttachedToDesktop = 0x00000001;
    private const int DisplayDevicePrimaryDevice = 0x00000004;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        public short SpecVersion;
        public short DriverVersion;
        public short Size;
        public short DriverExtra;
        public int Fields;
        public int PositionX;
        public int PositionY;
        public int DisplayOrientation;
        public int DisplayFixedOutput;
        public short Color;
        public short Duplex;
        public short YResolution;
        public short TtOption;
        public short Collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FormName;
        public short LogPixels;
        public int BitsPerPel;
        public int PelsWidth;
        public int PelsHeight;
        public int DisplayFlags;
        public int DisplayFrequency;
        public int ICMMethod;
        public int ICMIntent;
        public int MediaType;
        public int DitherType;
        public int Reserved1;
        public int Reserved2;
        public int PanningWidth;
        public int PanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplayDevices(string? device, uint index, ref DisplayDevice info, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplaySettings(string deviceName, int mode, ref DevMode devMode);

    /// <summary>Les ecrans actifs, l'ecran principal en tete. Liste vide si Windows
    /// ne repond pas : l'appelant se rabat alors sur "pas de choix a proposer".</summary>
    public static IReadOnlyList<Monitor> Enumerate()
    {
        var monitors = new List<Monitor>();

        for (uint index = 0; ; index++)
        {
            var device = new DisplayDevice();
            device.Size = Marshal.SizeOf<DisplayDevice>();
            if (!EnumDisplayDevices(null, index, ref device, 0)) break;

            // Un adaptateur peut exister sans ecran branche dessus : il n'a alors
            // aucune place sur le bureau et n'a rien a faire dans la liste.
            if ((device.StateFlags & DisplayDeviceAttachedToDesktop) == 0) continue;

            var mode = new DevMode();
            mode.Size = (short)Marshal.SizeOf<DevMode>();
            if (!EnumDisplaySettings(device.DeviceName, EnumCurrentSettings, ref mode)) continue;
            if (mode.PelsWidth <= 0 || mode.PelsHeight <= 0) continue;

            monitors.Add(new Monitor(
                device.DeviceName,
                ExtractNumber(device.DeviceName, monitors.Count + 1),
                mode.PelsWidth,
                mode.PelsHeight,
                (device.StateFlags & DisplayDevicePrimaryDevice) != 0));
        }

        return monitors.OrderByDescending(m => m.IsPrimary).ThenBy(m => m.Number).ToList();
    }

    /// <summary>"\\.\DISPLAY2" -> 2. Retombe sur le rang dans la liste si le nom ne
    /// suit pas cette forme, pour ne jamais afficher un ecran sans numero.</summary>
    private static int ExtractNumber(string deviceName, int fallback)
    {
        var digits = new string(deviceName.Where(char.IsDigit).ToArray());
        return int.TryParse(digits, out var number) && number > 0 ? number : fallback;
    }
}
