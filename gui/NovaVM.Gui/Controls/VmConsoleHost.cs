using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace NovaVM.Gui.Controls;

/// <summary>
/// Affiche la console d'une VM Hyper-V A L'INTERIEUR de SPLYT, au lieu de la
/// fenetre vmconnect.exe flottante qui s'ouvre par-dessus l'application.
///
/// Principe : vmconnect.exe s'authentifie tout seul aupres du service Hyper-V
/// (port 2179, CredSSP) - chose qu'on ne sait PAS refaire nous-memes, verifie
/// longuement (voir la memoire "route B" : le controle ActiveX RDP n'obtient
/// jamais d'identifiants). On le lance donc normalement, puis on lui emprunte sa
/// fenetre : SetParent dans la notre, cadre et chrome retires.
///
/// Trois pieges, tous rencontres et corriges ici :
/// 1. vmconnect RECREE son style de fenetre quand la VM demarre : il faut le
///    redepouiller a chaque cycle, une seule passe au reparentage ne tient pas.
/// 2. Sa boite "Se connecter a &lt;VM&gt;" (passage en Session Amelioree, proposee
///    une fois Windows demarre dans l'invite) est une fenetre de PREMIER NIVEAU
///    distincte : elle echappe au reparentage et vole le clavier. On la valide
///    automatiquement.
/// 3. vmconnect n'etire JAMAIS la video pour remplir la fenetre : elle reste a la
///    resolution negociee, ancree en haut a gauche, le reste peint en gris Win32
///    (#F0F0F0). Confirme sur une fenetre vmconnect autonome, jamais touchee par
///    SPLYT - c'est natif, pas un effet de bord du reparentage. La parade n'est
///    donc pas de masquer ce gris, mais de MESURER la zone video a l'execution
///    et de dimensionner l'hote exactement dessus : le gris tombe alors hors du
///    cadre visible, et c'est le fond SPLYT qui entoure la video.
/// </summary>
public sealed class VmConsoleHost : HwndHost
{
    /// <summary>Nom de la VM dont on affiche la console. Changer cette valeur
    /// ferme la console precedente et en ouvre une nouvelle.</summary>
    public static readonly DependencyProperty VmNameProperty = DependencyProperty.Register(
        nameof(VmName), typeof(string), typeof(VmConsoleHost),
        new PropertyMetadata(null, OnConsoleInputChanged));

    /// <summary>Faux tant que la VM n'est pas demarree : inutile d'ouvrir une
    /// console sur une machine eteinte (vmconnect afficherait son propre ecran
    /// "l'ordinateur virtuel est eteint", avec son habillage a lui).</summary>
    public static readonly DependencyProperty IsConsoleEnabledProperty = DependencyProperty.Register(
        nameof(IsConsoleEnabled), typeof(bool), typeof(VmConsoleHost),
        new PropertyMetadata(false, OnConsoleInputChanged));

    public string? VmName
    {
        get => (string?)GetValue(VmNameProperty);
        set => SetValue(VmNameProperty, value);
    }

    public bool IsConsoleEnabled
    {
        get => (bool)GetValue(IsConsoleEnabledProperty);
        set => SetValue(IsConsoleEnabledProperty, value);
    }

    private IntPtr _container;
    private Process? _vmconnect;
    private IntPtr _console;
    private bool _maximizedOnce;
    private DispatcherTimer? _timer;
    private Size _videoSize;

    public VmConsoleHost()
    {
        // Sans ca, WPF garde le focus clavier pour lui et rien de ce que tape
        // l'utilisateur n'atteint la VM : une fenetre native hebergee ne recoit les
        // touches que si elle detient le focus AU SENS WIN32, ce que WPF ne fait
        // pas tout seul (probleme classique de HwndHost).
        Focusable = true;
        MouseLeftButtonDown += (_, _) => FocusConsole();
        GotKeyboardFocus += (_, _) => FocusConsole();
    }

    private static void OnConsoleInputChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is VmConsoleHost host && host._container != IntPtr.Zero) host.Restart();
    }

    /// <summary>Donne le focus Win32 a la fenetre de la console pour que le clavier
    /// y arrive (frappe dans l'invite, "Press any key to boot from CD"...).</summary>
    public void FocusConsole()
    {
        if (_console == IntPtr.Zero) return;
        Focus();
        Native.SetFocus(_console);
    }

    /// <summary>Laisse les touches filer vers la console au lieu que WPF les
    /// consomme comme raccourcis de l'application.</summary>
    protected override bool TranslateAcceleratorCore(ref MSG msg, System.Windows.Input.ModifierKeys modifiers) => false;

    /// <summary>Envoie Ctrl+Alt+Fin a la console, que vmconnect traduit en
    /// Ctrl+Alt+Suppr pour la VM. Windows reserve le vrai Ctrl+Alt+Suppr et
    /// aucune application ne peut le simuler, d'ou ce detour - c'est aussi ce que
    /// propose le menu Action de vmconnect.</summary>
    public void SendCtrlAltDelete()
    {
        if (_console == IntPtr.Zero) return;
        FocusConsole();
        Native.SendCtrlAltEnd();
    }

    /// <summary>Martele Espace pendant quelques secondes pour passer l'invite
    /// firmware "Press any key to boot from CD or DVD...", que l'utilisateur ne
    /// peut pas attraper a temps.
    ///
    /// La touche est envoyee DANS la fenetre de la console et non via le clavier
    /// synthetique WMI (Msvm_Keyboard.TypeKey) : verifie a l'ecran, WMI fonctionne
    /// sur une VM sans GPU-P mais reste sans effet des qu'un adaptateur GPU-P est
    /// attache - les appels reussissent sans erreur et la touche n'arrive jamais.
    /// GPU-P etant la raison d'etre de SPLYT, c'etait inutilisable.</summary>
    public async Task SendBootKeyBurstAsync()
    {
        var deadline = DateTime.UtcNow.AddSeconds(12);
        while (DateTime.UtcNow < deadline)
        {
            if (_console != IntPtr.Zero)
            {
                FocusConsole();
                Native.SendSpace();
            }
            await Task.Delay(250);
        }
    }

    protected override HandleRef BuildWindowCore(HandleRef hwndParent)
    {
        // Fenetre conteneur peinte au fond SPLYT : c'est elle qu'on voit autour de
        // la video quand celle-ci ne remplit pas tout, a la place du gris Win32.
        _container = Native.CreateContainer(hwndParent.Handle);

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _timer.Tick += (_, _) => Pump();
        _timer.Start();

        Start();
        return new HandleRef(this, _container);
    }

    protected override void DestroyWindowCore(HandleRef hwnd)
    {
        Stop();
        _timer?.Stop();
        _timer = null;

        if (_container != IntPtr.Zero)
        {
            Native.DestroyWindow(_container);
            _container = IntPtr.Zero;
        }
    }

    /// <summary>Le conteneur prend exactement la taille de la video - jamais plus
    /// que l'espace offert. C'est ce qui fait tomber TOUT le chrome de vmconnect
    /// (menu et barre d'outils au-dessus, barre d'etat en dessous) hors du cadre
    /// visible : un HWND enfant ne peint jamais hors du rectangle client de son
    /// parent. Le centrage est laisse a WPF, et le pourtour laisse voir le fond
    /// SPLYT.
    ///
    /// Le plafonnement par availableSize est essentiel : un HwndHost n'est pas
    /// rogne par la mise en page WPF ("airspace"), donc reclamer plus que la place
    /// disponible ferait deborder la console par-dessus le reste de l'interface.</summary>
    protected override Size MeasureOverride(Size availableSize)
    {
        if (_videoSize.Width <= 0 || _videoSize.Height <= 0) return base.MeasureOverride(availableSize);

        var width = double.IsInfinity(availableSize.Width)
            ? _videoSize.Width
            : Math.Min(_videoSize.Width, availableSize.Width);
        var height = double.IsInfinity(availableSize.Height)
            ? _videoSize.Height
            : Math.Min(_videoSize.Height, availableSize.Height);

        return new Size(width, height);
    }

    private void Restart()
    {
        Stop();
        _videoSize = default;
        _videoSizeDevice = default;
        Start();
    }

    private void Start()
    {
        if (!IsConsoleEnabled || string.IsNullOrWhiteSpace(VmName)) return;

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = System.IO.Path.Combine(Environment.SystemDirectory, "vmconnect.exe"),
                UseShellExecute = false,
            };
            startInfo.ArgumentList.Add(Environment.MachineName);
            startInfo.ArgumentList.Add(VmName!);
            _vmconnect = Process.Start(startInfo);
        }
        catch (Exception)
        {
            // Best-effort : sans console integree l'application reste utilisable,
            // l'utilisateur peut toujours ouvrir la console Hyper-V lui-meme.
            _vmconnect = null;
        }

        _console = IntPtr.Zero;
        _maximizedOnce = false;
    }

    private void Stop()
    {
        var process = _vmconnect;
        _vmconnect = null;
        _console = IntPtr.Zero;

        if (process is null) return;
        try
        {
            if (!process.HasExited) process.Kill();
        }
        catch
        {
            // Le processus a pu disparaitre entre-temps : rien a rattraper.
        }
        process.Dispose();
    }

    private void Pump()
    {
        if (_vmconnect is null || _vmconnect.HasExited) return;

        // vmconnect peut detruire sa fenetre et en recreer une (observe pendant le
        // demarrage de la VM) : on ne s'arrete pas, on la recherche a nouveau.
        if (_console != IntPtr.Zero && !Native.IsWindow(_console))
        {
            _console = IntPtr.Zero;
            _maximizedOnce = false;
        }

        if (_console == IntPtr.Zero)
        {
            _vmconnect.Refresh();
            var found = _vmconnect.MainWindowHandle;
            if (found != IntPtr.Zero)
            {
                if (!_maximizedOnce)
                {
                    // Meme precaution qu'ailleurs dans SPLYT (voir
                    // NovaVmService.ResizeConsoleWindowAsync) : vmconnect s'ouvre
                    // dans une petite fenetre et reagit mal a un redimensionnement
                    // direct. Le maximiser une fois d'abord rend la suite fiable.
                    Native.ShowWindow(found, Native.SW_MAXIMIZE);
                    _maximizedOnce = true;
                    return;
                }

                Native.StripFrame(found);
                Native.SetParent(found, _container);
                Native.AttachThreadInput(Native.GetCurrentThreadId(),
                    Native.GetWindowThreadProcessId(found, out _), true);
                _console = found;
            }
        }

        if (_console != IntPtr.Zero)
        {
            Native.StripFrame(_console);
            LayoutConsole();
        }

        DismissStrayDialogs();
    }

    /// <summary>Place la fenetre vmconnect pour que SEULE sa zone video occupe le
    /// conteneur : son menu et sa barre d'outils sortent par le haut, sa barre
    /// d'etat et son fond gris par le bas.</summary>
    private void LayoutConsole()
    {
        if (!Native.GetClientRect(_container, out var container)) return;
        var containerW = container.Right - container.Left;
        var containerH = container.Bottom - container.Top;
        if (containerW <= 0 || containerH <= 0) return;

        var video = Native.FindVideoRect(_console);
        if (video is null)
        {
            // Pas encore mesurable (connexion en cours) : on remplit, quitte a
            // montrer le chrome une fraction de seconde.
            Native.SetWindowPos(_console, 0, 0, containerW, containerH);
            return;
        }

        if (!Native.GetWindowRect(_console, out var window)) return;

        var v = video.Value;
        var videoW = v.Right - v.Left;
        var videoH = v.Bottom - v.Top;
        if (videoW <= 0 || videoH <= 0) return;

        // Decalage du coin haut-gauche de la video par rapport a celui de la
        // fenetre : c'est la hauteur du menu + de la barre d'outils, mesuree et
        // non devinee (elle change avec le theme et la mise a l'echelle).
        var offsetX = v.Left - window.Left;
        var offsetY = v.Top - window.Top;

        NotifyVideoSize(videoW, videoH);

        // La video est calee sur l'origine du conteneur, qui fait deja exactement
        // sa taille (voir MeasureOverride) : tout le chrome de vmconnect - menu et
        // barre d'outils au-dessus, barre d'etat en dessous - se retrouve hors du
        // rectangle client du conteneur, donc invisible. Le centrage a l'ecran est
        // l'affaire de WPF, pas la notre : le faire ici ramenait la barre d'etat
        // dans le cadre des que le conteneur etait plus grand que la video (vu en
        // plein ecran).
        //
        // La hauteur demandee reste "confortable" pour que vmconnect ne recalcule
        // pas sa mise en page et ne reduise pas la video.
        Native.SetWindowPos(_console, -offsetX, -offsetY,
            offsetX + videoW + offsetX, offsetY + videoH + BottomChromeAllowance);
    }

    /// <summary>Marge laissee sous la video pour la barre d'etat de vmconnect :
    /// elle doit rester DANS la fenetre (sinon vmconnect recalcule sa mise en page
    /// et reduit la video), mais tombe hors du conteneur.</summary>
    private const int BottomChromeAllowance = 48;

    /// <summary>Taille reelle de la zone video de la VM, mesuree une fois la
    /// connexion etablie. La fenetre de console s'en sert pour se dimensionner
    /// dessus : vmconnect ne mettant pas l'image a l'echelle, une fenetre plus
    /// petite ne reduit pas l'image, elle la ROGNE.</summary>
    public event EventHandler<Size>? VideoSizeChanged;

    /// <summary>Taille de la video en PIXELS, telle que Win32 la rapporte. Conservee
    /// telle quelle, separement de la version en unites WPF : les deux mondes ne
    /// parlent pas la meme langue (voir ApplyVideoSize).</summary>
    private Size _videoSizeDevice;

    private void NotifyVideoSize(int width, int height)
    {
        if (Math.Abs(_videoSizeDevice.Width - width) < 1 && Math.Abs(_videoSizeDevice.Height - height) < 1) return;

        _videoSizeDevice = new Size(width, height);
        ApplyVideoSize();
    }

    /// <summary>Convertit la taille mesuree en pixels vers les unites de WPF, puis la
    /// publie.
    ///
    /// C'est LA correction de la mise a l'echelle. GetWindowRect rend des pixels
    /// physiques ; WPF, lui, compte en unites independantes de la resolution. A
    /// 100 % les deux coincident, et c'est pourquoi le defaut ne se voyait pas ici.
    /// A 125 % - le reglage par defaut de Windows sur beaucoup d'ecrans - une video
    /// de 1920 pixels etait reclamee comme 1920 unites WPF, soit 2400 pixels : la
    /// fenetre de console s'ouvrait un quart trop grande et l'image tombait a cote.
    ///
    /// Le rapport est lu sur la fenetre elle-meme (TransformFromDevice) plutot que
    /// dans un reglage systeme : il est ainsi juste par ecran, et suit la fenetre
    /// quand elle passe sur un ecran a l'echelle differente.</summary>
    private void ApplyVideoSize()
    {
        if (_videoSizeDevice.Width <= 0 || _videoSizeDevice.Height <= 0) return;

        var scale = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice;
        var videoSize = scale.HasValue
            ? new Size(_videoSizeDevice.Width * scale.Value.M11, _videoSizeDevice.Height * scale.Value.M22)
            : _videoSizeDevice;

        if (Math.Abs(_videoSize.Width - videoSize.Width) < 0.5 &&
            Math.Abs(_videoSize.Height - videoSize.Height) < 0.5)
        {
            return;
        }

        _videoSize = videoSize;
        InvalidateMeasure();
        VideoSizeChanged?.Invoke(this, _videoSize);
    }

    /// <summary>A appeler quand la fenetre change d'echelle (deplacement vers un
    /// ecran a la mise a l'echelle differente) : la taille en pixels n'a pas bouge,
    /// mais sa traduction en unites WPF, si.</summary>
    public void RefreshDpiScale() => ApplyVideoSize();

    /// <summary>Valide automatiquement les boites que vmconnect ouvre a cote de sa
    /// fenetre principale (typiquement "Se connecter a &lt;VM&gt;", le choix de
    /// resolution de la Session Amelioree). Sans ca elles flottent par-dessus SPLYT
    /// et captent le clavier.</summary>
    private void DismissStrayDialogs()
    {
        if (_vmconnect is null || _vmconnect.HasExited) return;
        Native.DismissDialogs((uint)_vmconnect.Id, _console);
    }

    private static class Native
    {
        private const int GwlStyle = -16;
        private const int GwlExStyle = -20;

        private const long WsChild = 0x40000000;
        private const long WsVisible = 0x10000000;
        private const long WsPopup = 0x80000000;
        private const long WsCaption = 0x00C00000;
        private const long WsThickFrame = 0x00040000;
        private const long WsMinimizeBox = 0x00020000;
        private const long WsMaximizeBox = 0x00010000;
        private const long WsSysMenu = 0x00080000;
        private const long WsBorder = 0x00800000;
        private const long WsDlgFrame = 0x00400000;
        private const long WsExAppWindow = 0x00040000;

        private const uint SwpFrameChanged = 0x0020;
        private const uint SwpShowWindow = 0x0040;
        private const uint SwpNoZOrder = 0x0004;

        public const int SW_MAXIMIZE = 3;

        private const byte VkEscape = 0x1B;
        private const byte VkControl = 0x11;
        private const byte VkMenu = 0x12; // Alt
        private const byte VkEnd = 0x23;
        private const byte VkSpace = 0x20;
        private const uint KeyEventFKeyUp = 0x0002;

        // Couleur de fond du conteneur = BackgroundColor de Themes/Colors.xaml
        // (#12141A), au format COLORREF (0x00BBGGRR).
        private const int SplytBackgroundColorRef = 0x1A1412;

        private const string ContainerClassName = "SplytVmConsoleContainer";
        private static bool _classRegistered;

        // Conserve en champ statique : le delegue passe a Win32 ne doit pas etre
        // ramasse par le GC tant que la classe de fenetre existe.
        private static WndProc? _defaultWndProc;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left, Top, Right, Bottom;
        }

        private delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WNDCLASSEX
        {
            public uint cbSize;
            public uint style;
            public IntPtr lpfnWndProc;
            public int cbClsExtra;
            public int cbWndExtra;
            public IntPtr hInstance;
            public IntPtr hIcon;
            public IntPtr hCursor;
            public IntPtr hbrBackground;
            [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
            [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
            public IntPtr hIconSm;
        }

        private delegate bool EnumProc(IntPtr hWnd, IntPtr param);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern ushort RegisterClassEx(ref WNDCLASSEX wc);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowEx(
            uint exStyle, string className, string? windowName, uint style,
            int x, int y, int width, int height,
            IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateSolidBrush(int color);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string? name);

        [DllImport("user32.dll")]
        public static extern bool DestroyWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr SetParent(IntPtr child, IntPtr parent);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetParent(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int cmd);

        [DllImport("user32.dll")]
        public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

        [DllImport("user32.dll")]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumProc callback, IntPtr param);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr param);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder buffer, int max);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder buffer, int max);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint from, uint to, bool attach);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr SetFocus(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte key, byte scan, uint flags, IntPtr extra);

        public static IntPtr CreateContainer(IntPtr parent)
        {
            EnsureClassRegistered();
            return CreateWindowEx(0, ContainerClassName, null,
                (uint)(WsChild | WsVisible), 0, 0, 1, 1, parent, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        }

        private static void EnsureClassRegistered()
        {
            if (_classRegistered) return;

            _defaultWndProc = DefWindowProc;
            var wc = new WNDCLASSEX
            {
                cbSize = (uint)Marshal.SizeOf<WNDCLASSEX>(),
                lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_defaultWndProc),
                hInstance = GetModuleHandle(null),
                // Le fond est peint par Windows a partir de ce pinceau : aucune
                // gestion de WM_PAINT a ecrire, et jamais de blanc au
                // redimensionnement.
                hbrBackground = CreateSolidBrush(SplytBackgroundColorRef),
                lpszClassName = ContainerClassName,
            };
            RegisterClassEx(ref wc);
            _classRegistered = true;
        }

        public static void SetWindowPos(IntPtr hWnd, int x, int y, int width, int height) =>
            SetWindowPos(hWnd, IntPtr.Zero, x, y, width, height,
                SwpFrameChanged | SwpShowWindow | SwpNoZOrder);

        /// <summary>Retire tout ce qui fait une fenetre de premier niveau. A
        /// rappeler a chaque cycle : vmconnect se recree un cadre en cours de
        /// route.</summary>
        public static void StripFrame(IntPtr hWnd)
        {
            var style = (long)GetWindowLongPtr(hWnd, GwlStyle);
            var wanted = style;
            wanted &= ~(WsPopup | WsCaption | WsThickFrame | WsMinimizeBox |
                        WsMaximizeBox | WsSysMenu | WsBorder | WsDlgFrame);
            wanted |= WsChild | WsVisible;
            if (wanted != style) SetWindowLongPtr(hWnd, GwlStyle, (IntPtr)wanted);

            var ex = (long)GetWindowLongPtr(hWnd, GwlExStyle);
            if ((ex & WsExAppWindow) != 0) SetWindowLongPtr(hWnd, GwlExStyle, (IntPtr)(ex & ~WsExAppWindow));
        }

        public static void SendSpace()
        {
            keybd_event(VkSpace, 0, 0, IntPtr.Zero);
            keybd_event(VkSpace, 0, KeyEventFKeyUp, IntPtr.Zero);
        }

        /// <summary>Combinaison Ctrl+Alt+Fin, que vmconnect transmet a la VM comme
        /// Ctrl+Alt+Suppr.</summary>
        public static void SendCtrlAltEnd()
        {
            keybd_event(VkControl, 0, 0, IntPtr.Zero);
            keybd_event(VkMenu, 0, 0, IntPtr.Zero);
            keybd_event(VkEnd, 0, 0, IntPtr.Zero);
            keybd_event(VkEnd, 0, KeyEventFKeyUp, IntPtr.Zero);
            keybd_event(VkMenu, 0, KeyEventFKeyUp, IntPtr.Zero);
            keybd_event(VkControl, 0, KeyEventFKeyUp, IntPtr.Zero);
        }

        /// <summary>Rectangle ecran de la zone video, mesure et non devine. La pile
        /// d'affichage de vmconnect empile plusieurs fenetres exactement
        /// superposees (ATL:, UIMainClass, IHWindowClass, OPWindowClass...) : on
        /// retient la plus grande, ce qui ecarte le menu et la barre d'etat (des
        /// bandes de 24 px) sans dependre d'un nom de classe precis.</summary>
        public static RECT? FindVideoRect(IntPtr consoleWindow)
        {
            RECT? best = null;
            var bestArea = 0L;

            EnumChildWindows(consoleWindow, (child, _) =>
            {
                if (!IsWindowVisible(child)) return true;
                if (!GetWindowRect(child, out var rect)) return true;

                var width = (long)(rect.Right - rect.Left);
                var height = (long)(rect.Bottom - rect.Top);
                // Une bande fine est une barre d'outils ou d'etat, pas la video.
                if (height < 64 || width < 64) return true;

                var area = width * height;
                if (area <= bestArea) return true;

                bestArea = area;
                best = rect;
                return true;
            }, IntPtr.Zero);

            return best;
        }

        /// <summary>Ecarte (touche Echap) les fenetres de premier niveau du
        /// processus vmconnect autres que la console deja integree.
        ///
        /// Echap et NON Entree : la boite "Se connecter a &lt;VM&gt;" propose de
        /// passer en Session Amelioree (RDP). L'accepter donne une vue RDP qui,
        /// sur une machine verrouillee ou sans session ouverte, n'affiche qu'un
        /// fond d'ecran - PAS l'ecran de connexion. Compare a l'image reelle du
        /// framebuffer de la VM (WMI GetVirtualSystemThumbnailImage) : la VM
        /// montrait bien son ecran de verrouillage avec l'horloge pendant que la
        /// console, elle, restait sur un fond nu. La refuser garde la Session
        /// Basique, c'est-a-dire l'ecran reel de la machine - le seul qui marche
        /// aussi avant l'installation de Windows (firmware, installeur).
        ///
        /// IMPORTANT : n'appeler qu'APRES avoir identifie la console, sinon la
        /// fenetre principale se fait elle-meme passer pour un dialogue au premier
        /// cycle et recoit une touche parasite.</summary>
        public static void DismissDialogs(uint processId, IntPtr consoleWindow)
        {
            EnumWindows((hWnd, _) =>
            {
                if (hWnd == consoleWindow) return true;
                if (!IsWindowVisible(hWnd)) return true;
                if (GetParent(hWnd) != IntPtr.Zero) return true;

                GetWindowThreadProcessId(hWnd, out var owner);
                if (owner != processId) return true;

                var title = new StringBuilder(256);
                GetWindowText(hWnd, title, title.Capacity);
                if (title.Length == 0) return true;

                SetForegroundWindow(hWnd);
                keybd_event(VkEscape, 0, 0, IntPtr.Zero);
                keybd_event(VkEscape, 0, KeyEventFKeyUp, IntPtr.Zero);
                return true;
            }, IntPtr.Zero);
        }
    }
}
