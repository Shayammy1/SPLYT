using System.Collections.ObjectModel;
using NovaVM.Gui.Models;
using NovaVM.Gui.Services;

namespace NovaVM.Gui.ViewModels;

public sealed class JournalViewModel : ViewModelBase
{
    public JournalViewModel(LogService log)
    {
        Entries = log.Entries;
    }

    public ReadOnlyObservableCollection<LogEntry> Entries { get; }
}
