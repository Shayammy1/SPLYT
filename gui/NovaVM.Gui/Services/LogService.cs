using System.Collections.ObjectModel;
using System.Windows.Threading;
using NovaVM.Gui.Models;

namespace NovaVM.Gui.Services;

/// <summary>
/// Journal applicatif partage (page "Journal" + bandeau d'alertes du Dashboard).
/// Chaque appel a NovaVmService y ajoute automatiquement une entree : c'est la
/// vue globale et centralisee des erreurs demandee pour l'appli.
/// </summary>
public sealed class LogService
{
    private const int MaxEntries = 500;
    private readonly ObservableCollection<LogEntry> _entries = new();
    private readonly Dispatcher _dispatcher;

    public LogService()
    {
        _dispatcher = Dispatcher.CurrentDispatcher;
        Entries = new ReadOnlyObservableCollection<LogEntry>(_entries);
    }

    public ReadOnlyObservableCollection<LogEntry> Entries { get; }

    public void Log(LogLevel level, string source, string message, string? details = null)
    {
        var entry = new LogEntry
        {
            Level = level,
            Source = source,
            Message = message,
            Details = details,
        };

        void Add()
        {
            _entries.Insert(0, entry);
            while (_entries.Count > MaxEntries)
            {
                _entries.RemoveAt(_entries.Count - 1);
            }
        }

        if (_dispatcher.CheckAccess()) Add();
        else _dispatcher.Invoke(Add);
    }

    public IEnumerable<LogEntry> RecentAlerts(int count = 5) =>
        _entries.Where(e => e.Level is LogLevel.Warning or LogLevel.Error).Take(count);
}
