using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;

namespace NovaVM.Gui.Services;

/// <summary>
/// Dit QUEL peripherique d'entree vient d'etre utilise, pour que l'utilisateur
/// puisse identifier une souris ou un clavier en le manipulant : la ligne
/// correspondante s'allume.
///
/// Pourquoi c'est necessaire : Windows nomme la quasi-totalite des souris et des
/// claviers "Peripherique d'entree USB", a l'identique. Devant une liste de six
/// lignes portant le meme nom, la seule facon de savoir laquelle est la bonne est
/// de bouger la souris et de regarder ce qui reagit.
///
/// CE QUI EST LU, ET CE QUI NE L'EST PAS. L'API d'entree brute permettrait de
/// lire les touches frappees ; ce n'est pas fait ici. Seul l'EN-TETE de chaque
/// evenement est demande (RID_HEADER), qui contient l'identifiant du peripherique
/// et rien d'autre : ni code de touche, ni position de souris, ni bouton. La
/// charge utile n'est jamais demandee a Windows, donc jamais lue.
///
/// L'ecoute ne tourne que pendant que la liste des peripheriques est affichee
/// (comptage des demarrages/arrets), et jamais en arriere-plan.
/// </summary>
internal sealed class HostInputWatcher : IDisposable
{
    /// <summary>Identite materielle du peripherique qui vient d'etre utilise, sous
    /// la forme "1bcf:0005", et le segment d'instance quand il est lisible.</summary>
    public event EventHandler<HostInputSignal>? InputSeen;

    private const int WmInput = 0x00FF;
    private const uint RidHeader = 0x10000005;
    private const uint RidiDeviceName = 0x20000007;
    private const uint RidevInputSink = 0x00000100;

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputDevice
    {
        public ushort UsagePage;
        public ushort Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputHeader
    {
        public uint Type;
        public uint Size;
        public IntPtr Device;
        public IntPtr WParam;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(
        [In] RawInputDevice[] devices, uint count, uint size);

    [DllImport("user32.dll")]
    private static extern uint GetRawInputData(
        IntPtr rawInput, uint command, out RawInputHeader data, ref uint size, uint headerSize);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetRawInputDeviceInfo(
        IntPtr device, uint command, StringBuilder? data, ref uint size);

    /// <summary>Un seul guetteur pour toute l'application : l'inscription aux
    /// entrees brutes se fait par processus et par usage, donc un second guetteur
    /// deroberait les evenements au premier, qui se tairait sans erreur. A creer
    /// depuis le fil de l'interface, HwndSource en ayant besoin.</summary>
    public static HostInputWatcher Shared { get; } = new();

    private readonly HwndSource _sink;
    private readonly Dictionary<IntPtr, HostInputSignal> _known = new();
    private int _users;
    private bool _registered;
    private bool _disposed;

    public HostInputWatcher()
    {
        // Fenetre de message uniquement (HWND_MESSAGE) : invisible, jamais dans la
        // barre des taches, elle n'existe que pour recevoir WM_INPUT.
        _sink = new HwndSource(new HwndSourceParameters("SPLYT input watcher")
        {
            ParentWindow = new IntPtr(-3),   // HWND_MESSAGE
            Width = 0,
            Height = 0,
        });
        _sink.AddHook(OnMessage);
    }

    /// <summary>Commence a ecouter, ou incremente le nombre de vues interessees.
    /// L'ecoute s'arrete des que plus personne ne regarde.</summary>
    public void Start()
    {
        if (_disposed) return;
        _users++;
        if (_registered || _users <= 0) return;

        // INPUTSINK : les evenements arrivent meme quand SPLYT n'a pas le focus.
        // Indispensable ici - l'utilisateur doit pouvoir cliquer avec la souris a
        // identifier, ce qui donne justement le focus a une autre fenetre.
        var devices = new[]
        {
            new RawInputDevice { UsagePage = 0x01, Usage = 0x02, Flags = RidevInputSink, Target = _sink.Handle },
            new RawInputDevice { UsagePage = 0x01, Usage = 0x06, Flags = RidevInputSink, Target = _sink.Handle },
        };
        _registered = RegisterRawInputDevices(devices, (uint)devices.Length, (uint)Marshal.SizeOf<RawInputDevice>());
    }

    public void Stop()
    {
        if (_users > 0) _users--;
        if (_users > 0 || !_registered) return;

        // RIDEV_REMOVE (0x00000001) avec une cible nulle : Windows exige que le
        // handle soit nul pour un retrait, sous peine d'echec silencieux.
        var devices = new[]
        {
            new RawInputDevice { UsagePage = 0x01, Usage = 0x02, Flags = 0x00000001, Target = IntPtr.Zero },
            new RawInputDevice { UsagePage = 0x01, Usage = 0x06, Flags = 0x00000001, Target = IntPtr.Zero },
        };
        RegisterRawInputDevices(devices, (uint)devices.Length, (uint)Marshal.SizeOf<RawInputDevice>());
        _registered = false;
    }

    private IntPtr OnMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WmInput) return IntPtr.Zero;

        var size = (uint)Marshal.SizeOf<RawInputHeader>();
        // RID_HEADER, et jamais RID_INPUT : on ne demande QUE l'identifiant du
        // peripherique. Le contenu de la frappe n'est meme pas recupere.
        if (GetRawInputData(lParam, RidHeader, out var header, ref size, size) == uint.MaxValue)
        {
            return IntPtr.Zero;
        }

        var signal = Describe(header.Device);
        if (signal is not null) InputSeen?.Invoke(this, signal);
        return IntPtr.Zero;
    }

    /// <summary>Identite materielle d'un peripherique, mise en cache : l'appel
    /// Win32 est fait une fois par peripherique et non a chaque mouvement de
    /// souris, qui en produit des centaines par seconde.</summary>
    private HostInputSignal? Describe(IntPtr device)
    {
        if (device == IntPtr.Zero) return null;
        if (_known.TryGetValue(device, out var cached)) return cached;

        uint length = 0;
        GetRawInputDeviceInfo(device, RidiDeviceName, null, ref length);
        if (length == 0) return null;

        var buffer = new StringBuilder((int)length + 2);
        if (GetRawInputDeviceInfo(device, RidiDeviceName, buffer, ref length) == uint.MaxValue) return null;

        var signal = HostInputSignal.Parse(buffer.ToString());
        _known[device] = signal;
        return signal;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _users = 0;
        _registered = false;
        Stop();
        _sink.RemoveHook(OnMessage);
        _sink.Dispose();
    }
}

/// <summary>Ce qu'on sait du peripherique qui vient de servir. Volontairement
/// pauvre : de quoi le reconnaitre dans une liste, rien de plus.</summary>
internal sealed class HostInputSignal
{
    private HostInputSignal(string vidPid, string instanceSegment)
    {
        VidPid = vidPid;
        InstanceSegment = instanceSegment;
    }

    /// <summary>"1bcf:0005", en minuscules - meme forme que dans la liste des
    /// peripheriques USB.</summary>
    public string VidPid { get; }

    /// <summary>Le segment d'instance du nom brut ("6&306893d8&0&3"), qui distingue
    /// deux exemplaires du meme modele branches en meme temps.</summary>
    public string InstanceSegment { get; }

    /// <summary>Decoupe un nom d'entree brute
    /// ("\\?\HID#VID_1BCF&amp;PID_0005#6&amp;306893d8&amp;0&amp;3#{guid}").</summary>
    public static HostInputSignal Parse(string deviceName)
    {
        var vidPid = "";
        var match = System.Text.RegularExpressions.Regex.Match(
            deviceName, @"VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        if (match.Success)
        {
            vidPid = $"{match.Groups[1].Value.ToLowerInvariant()}:{match.Groups[2].Value.ToLowerInvariant()}";
        }

        // Le segment d'instance est l'avant-dernier morceau separe par '#'.
        var parts = deviceName.Split('#');
        var segment = parts.Length >= 3 ? parts[^2].ToLowerInvariant() : "";

        return new HostInputSignal(vidPid, segment);
    }
}
