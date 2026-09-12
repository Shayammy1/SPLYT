using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace NovaVM.Gui.Services;

/// <summary>
/// Donne la place reellement disponible pour une fenetre, sur L'ECRAN OU ELLE SE
/// TROUVE.
///
/// Pourquoi ne pas se contenter de SystemParameters.WorkArea : cette propriete
/// decrit l'ecran PRINCIPAL, quel que soit l'ecran ou la fenetre est affichee. Sur
/// un poste a plusieurs ecrans de tailles differentes, ou simplement quand la
/// fenetre a ete deplacee, elle donne donc la mauvaise reponse - et une fenetre
/// dimensionnee dessus deborde de son ecran.
/// </summary>
internal static class ScreenFit
{
    /// <summary>Part de la zone de travail qu'une fenetre peut occuper au plus.
    /// Volontairement inferieure a 1 : coller au bord de la zone de travail met la
    /// fenetre au contact de la barre des taches de l'hote, ce qui donne
    /// l'impression que le bas du contenu passe dessous. Cette marge laisse
    /// respirer et garde la fenetre entierement saisissable.</summary>
    public const double UsableFraction = 0.9;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public int Flags;
    }

    private const int MonitorDefaultToNearest = 2;

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, int flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    /// <summary>Zone de travail de l'ecran qui porte cette fenetre, exprimee dans
    /// les unites de WPF (donc deja divisee par la mise a l'echelle de cet
    /// ecran-la). Retombe sur l'ecran principal si la fenetre n'a pas encore de
    /// poignee - au tout premier affichage, par exemple.</summary>
    public static Rect<double> GetWorkArea(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            var fallback = SystemParameters.WorkArea;
            return new Rect<double>(fallback.Left, fallback.Top, fallback.Width, fallback.Height);
        }

        var monitor = MonitorFromWindow(handle, MonitorDefaultToNearest);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info))
        {
            var fallback = SystemParameters.WorkArea;
            return new Rect<double>(fallback.Left, fallback.Top, fallback.Width, fallback.Height);
        }

        // Les rectangles de Win32 sont en pixels ; WPF compte en unites
        // independantes de la resolution. La conversion se lit sur la fenetre
        // elle-meme, elle est donc juste pour l'ecran ou celle-ci se trouve.
        var scale = PresentationSource.FromVisual(window)?.CompositionTarget?.TransformFromDevice;
        var scaleX = scale?.M11 ?? 1.0;
        var scaleY = scale?.M22 ?? 1.0;

        return new Rect<double>(
            info.Work.Left * scaleX,
            info.Work.Top * scaleY,
            (info.Work.Right - info.Work.Left) * scaleX,
            (info.Work.Bottom - info.Work.Top) * scaleY);
    }

    /// <summary>Reduit une fenetre pour qu'elle tienne sur son ecran, et la recentre
    /// si elle depassait. Sans effet si elle tient deja.</summary>
    public static void FitToScreen(Window window, double fraction = UsableFraction)
    {
        var work = GetWorkArea(window);
        var maxWidth = work.Width * fraction;
        var maxHeight = work.Height * fraction;

        var width = Math.Min(window.Width, maxWidth);
        var height = Math.Min(window.Height, maxHeight);
        if (double.IsNaN(width) || double.IsNaN(height)) return;

        // La taille minimale declaree dans le XAML peut elle-meme etre trop grande
        // pour l'ecran : sur un portable de 1366x768 mis a l'echelle a 125 %, la
        // hauteur utile ne fait que 576 unites WPF, moins que le MinHeight de 640.
        // WPF imposerait alors le minimum et la fenetre deborderait quand meme.
        // Mieux vaut une fenetre un peu a l'etroit mais entierement visible qu'une
        // fenetre dont une partie est hors de l'ecran, sans moyen de la ramener.
        if (window.MinWidth > maxWidth) window.MinWidth = maxWidth;
        if (window.MinHeight > maxHeight) window.MinHeight = maxHeight;

        var changed = width < window.Width || height < window.Height;
        window.Width = width;
        window.Height = height;

        if (changed)
        {
            // Recentre a partir de la taille REELLE apres application des minimums,
            // et non de celle demandee : sinon la fenetre reste decalee vers le haut
            // quand un minimum l'a fait grandir.
            window.UpdateLayout();
            var finalWidth = double.IsNaN(window.Width) ? width : Math.Max(window.Width, window.MinWidth);
            var finalHeight = double.IsNaN(window.Height) ? height : Math.Max(window.Height, window.MinHeight);
            window.Left = work.Left + (work.Width - finalWidth) / 2;
            window.Top = work.Top + (work.Height - finalHeight) / 2;
        }
    }

    /// <summary>Rectangle simple en unites WPF - System.Windows.Rect ne se prete pas
    /// a une construction depuis des bornes deja converties.</summary>
    public readonly struct Rect<T>(T left, T top, T width, T height)
    {
        public T Left { get; } = left;
        public T Top { get; } = top;
        public T Width { get; } = width;
        public T Height { get; } = height;
    }
}
