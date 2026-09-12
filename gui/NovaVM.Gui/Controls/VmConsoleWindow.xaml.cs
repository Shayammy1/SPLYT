using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using NovaVM.Gui.Models;
using NovaVM.Gui.Services.Localization;
using Wpf.Ui.Controls;

namespace NovaVM.Gui.Controls;

/// <summary>
/// Fenetre dediee a la console d'une VM, aux couleurs de SPLYT.
///
/// Pourquoi une fenetre plutot qu'un panneau dans l'application : vmconnect ne
/// met JAMAIS l'image a l'echelle (voir VmConsoleHost). Dans un onglet plus
/// petit que la resolution de la VM, l'image n'est donc pas reduite mais
/// ROGNEE - on ne voyait qu'une portion du bureau. Une fenetre qui s'ouvre a la
/// taille de la VM affiche l'ecran en entier, et le plein ecran permet d'y
/// travailler vraiment.
/// </summary>
public partial class VmConsoleWindow : FluentWindow
{
    private WindowState _stateBeforeFullScreen;
    private bool _isFullScreen;
    private bool _userResized;
    private bool _applyingVideoSize;

    public VmConsoleWindow(VirtualMachine vm)
    {
        InitializeComponent();

        Title = Loc.Get("Console_WindowTitle", vm.Name);
        TitleStrip.Title = Title;
        VmNameText.Text = vm.Name;
        FullScreenLabel.Text = Loc.Get("Console_FullScreenShort");

        Console.VideoSizeChanged += OnVideoSizeChanged;
        Console.VmName = vm.Name;
        Console.IsConsoleEnabled = true;

        // ISO encore premier peripherique de demarrage : il faut passer l'invite
        // "Press any key to boot from CD or DVD...", qui ne dure que deux ou trois
        // secondes. On martele Espace des l'ouverture, sans bloquer l'affichage.
        if (vm.NeedsBootKeyPress) _ = Console.SendBootKeyBurstAsync();

        // Echap et F11 : les deux reflexes attendus pour sortir/entrer en plein
        // ecran, sans avoir a retrouver un bouton masque.
        PreviewKeyDown += OnPreviewKeyDown;
        SizeChanged += OnUserResized;

        // Deplacer la fenetre vers un ecran a la mise a l'echelle differente change
        // la traduction pixels -> unites WPF, alors que la video, elle, fait toujours
        // le meme nombre de pixels. Sans ce rappel, la console gardait la taille
        // calculee pour l'echelle de l'ecran precedent.
        DpiChanged += (_, _) =>
        {
            _userResized = false;
            Console.RefreshDpiScale();
        };
        Closed += (_, _) =>
        {
            UnregisterFullScreenHotkey();
            Console.IsConsoleEnabled = false;
        };
    }

    /// <summary>Ajuste la fenetre a la resolution reelle de la VM, pour afficher
    /// l'ecran entier sans rognage (vmconnect ne met pas l'image a l'echelle) -
    /// dans la limite de l'ecran disponible.
    ///
    /// Suit CHAQUE changement de resolution et pas seulement le premier : au
    /// moment ou la fenetre s'ouvre, vmconnect n'est pas encore connecte et
    /// annonce une taille transitoire (640x400). S'y verrouiller laissait une
    /// fenetre minuscule affichant un coin du bureau, alors que la vraie
    /// resolution arrivait une seconde plus tard.</summary>
    private void OnVideoSizeChanged(object? sender, Size video)
    {
        VideoSizeText.Text = $"{(int)video.Width} x {(int)video.Height}";

        if (_isFullScreen || _userResized || video.Width <= 0 || video.Height <= 0) return;

        // Chrome deduite de la mise en page reelle (barre de titre + barre d'outils
        // + bordures) plutot qu'estimee : ne compter que HeaderBar oubliait la barre
        // de titre, la fenetre etait ~44 px trop courte et le bas de l'ecran de la
        // VM - notamment ses boutons - tombait hors du cadre.
        var chromeHeight = ActualHeight > 0 && ConsoleArea.ActualHeight > 0
            ? ActualHeight - ConsoleArea.ActualHeight
            : TitleStrip.ActualHeight + HeaderBar.ActualHeight + 16;
        var chromeWidth = ActualWidth > 0 && ConsoleArea.ActualWidth > 0
            ? ActualWidth - ConsoleArea.ActualWidth
            : 16;

        var maxWidth = SystemParameters.WorkArea.Width;
        var maxHeight = SystemParameters.WorkArea.Height;

        _applyingVideoSize = true;

        Width = Math.Min(video.Width + chromeWidth, maxWidth);
        Height = Math.Min(video.Height + chromeHeight, maxHeight);

        // Recentre : agrandir depuis le coin superieur gauche ferait deborder la
        // fenetre de l'ecran sur une VM en haute resolution.
        Left = Math.Max(SystemParameters.WorkArea.Left, (maxWidth - Width) / 2);
        Top = Math.Max(SystemParameters.WorkArea.Top, (maxHeight - Height) / 2);

        // Rendu a la main apres la passe de mise en page, pour ne pas prendre nos
        // propres redimensionnements pour ceux de l'utilisateur.
        Dispatcher.BeginInvoke(new Action(() => _applyingVideoSize = false),
            System.Windows.Threading.DispatcherPriority.Background);
    }

    /// <summary>Des que l'utilisateur redimensionne lui-meme, on cesse de suivre la
    /// resolution de la VM : sa taille de fenetre l'emporte sur la notre.</summary>
    private void OnUserResized(object sender, SizeChangedEventArgs e)
    {
        if (!_applyingVideoSize && IsLoaded) _userResized = true;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.F11)
        {
            ToggleFullScreen();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape && _isFullScreen)
        {
            ToggleFullScreen();
            e.Handled = true;
        }
    }

    private void OnToggleFullScreen(object sender, RoutedEventArgs e) => ToggleFullScreen();

    private void ToggleFullScreen()
    {
        if (_isFullScreen)
        {
            WindowStyle = WindowStyle.SingleBorderWindow;
            ResizeMode = ResizeMode.CanResize;
            WindowState = _stateBeforeFullScreen;
            TitleStrip.Visibility = Visibility.Visible;
            HeaderBar.Visibility = Visibility.Visible;
            FullScreenHint.Visibility = Visibility.Collapsed;
            _isFullScreen = false;
            UnregisterFullScreenHotkey();
            return;
        }

        _stateBeforeFullScreen = WindowState;
        TitleStrip.Visibility = Visibility.Collapsed;
        HeaderBar.Visibility = Visibility.Collapsed;
        FullScreenHint.Visibility = Visibility.Visible;

        // Repasser par Normal avant Maximized : sans ca, une fenetre deja
        // maximisee garde la place de la barre des taches et le plein ecran n'est
        // pas reellement plein.
        WindowState = WindowState.Normal;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        WindowState = WindowState.Maximized;
        _isFullScreen = true;
        RegisterFullScreenHotkey();

        Console.FocusConsole();
    }

    // --- Sortie garantie du plein ecran -------------------------------------
    //
    // En plein ecran, la barre d'outils est masquee ET la VM detient le focus
    // clavier au sens Win32 (c'est ce qui permet de taper dedans) : F11 et Echap
    // partent donc dans l'invite, WPF ne les voit jamais. Sans le raccourci
    // global ci-dessous, l'utilisateur serait piege. Il n'est enregistre QUE
    // pendant le plein ecran, et rendu des qu'on en sort.

    private const int HotkeyId = 0xB01;
    private const int WmHotkey = 0x0312;
    private const uint VkF11 = 0x7A;
    private HwndSource? _source;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private void RegisterFullScreenHotkey()
    {
        _source ??= (HwndSource)PresentationSource.FromVisual(this);
        if (_source is null) return;

        _source.AddHook(OnWindowMessage);
        RegisterHotKey(_source.Handle, HotkeyId, 0, VkF11);
    }

    private void UnregisterFullScreenHotkey()
    {
        if (_source is null) return;
        UnregisterHotKey(_source.Handle, HotkeyId);
        _source.RemoveHook(OnWindowMessage);
    }

    private IntPtr OnWindowMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && wParam.ToInt32() == HotkeyId && _isFullScreen)
        {
            ToggleFullScreen();
            handled = true;
        }
        return IntPtr.Zero;
    }

    /// <summary>Ctrl+Alt+Suppr ne peut pas etre simule : Windows le reserve. Dans
    /// une console Hyper-V, c'est Ctrl+Alt+Fin qui le transmet a la VM - on le
    /// propose donc en bouton, comme le fait le menu de vmconnect.</summary>
    private void OnSendCtrlAltDel(object sender, RoutedEventArgs e) => Console.SendCtrlAltDelete();
}
