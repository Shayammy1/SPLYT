using System.Windows.Threading;
using NovaVM.Gui.ViewModels;

namespace NovaVM.Gui.Services;

/// <summary>
/// Allume la ligne du peripherique qu'on vient de manipuler, et l'eteint peu
/// apres. C'est le seul moyen pratique de reconnaitre une souris ou un clavier
/// dans une liste ou Windows les nomme tous "Peripherique d'entree USB" :
/// l'utilisateur bouge la souris a identifier, et regarde quelle ligne reagit.
///
/// L'extinction est faite par un temporisateur unique plutot que par un
/// compte a rebours par ligne : une souris produit des centaines d'evenements par
/// seconde, autant de minuteries creees et annulees pour rien.
/// </summary>
public sealed class UsbActivityTracker : IDisposable
{
    /// <summary>Duree d'allumage apres le dernier evenement. Assez long pour etre
    /// vu, assez court pour qu'un deplacement de souris ne laisse pas la ligne
    /// allumee bien apres qu'on l'a lachee.</summary>
    private static readonly TimeSpan Hold = TimeSpan.FromMilliseconds(700);

    private readonly Func<IEnumerable<UsbDeviceItemViewModel>> _items;
    private readonly DispatcherTimer _timer;
    private bool _started;
    private bool _disposed;

    public UsbActivityTracker(Func<IEnumerable<UsbDeviceItemViewModel>> items)
    {
        _items = items;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _timer.Tick += (_, _) => ClearExpired();
    }

    public void Start()
    {
        if (_disposed || _started) return;
        _started = true;
        HostInputWatcher.Shared.InputSeen += OnInputSeen;
        HostInputWatcher.Shared.Start();
        _timer.Start();
    }

    public void Stop()
    {
        if (!_started) return;
        _started = false;
        HostInputWatcher.Shared.InputSeen -= OnInputSeen;
        HostInputWatcher.Shared.Stop();
        _timer.Stop();

        foreach (var item in _items()) item.IsActive = false;
    }

    private void OnInputSeen(object? sender, HostInputSignal signal)
    {
        if (string.IsNullOrEmpty(signal.VidPid)) return;

        // Rapprochement par identite materielle. Deux exemplaires du meme modele
        // s'allument ensemble : ils sont indiscernables pour l'utilisateur aussi,
        // donc en allumer un seul au hasard serait trompeur.
        foreach (var item in _items())
        {
            if (!string.Equals(item.HardwareLabel, signal.VidPid, StringComparison.OrdinalIgnoreCase)) continue;
            item.LastActivityUtc = DateTime.UtcNow;
            item.IsActive = true;
        }
    }

    private void ClearExpired()
    {
        var now = DateTime.UtcNow;
        foreach (var item in _items())
        {
            if (item.IsActive && now - item.LastActivityUtc > Hold) item.IsActive = false;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Stop();
    }
}
