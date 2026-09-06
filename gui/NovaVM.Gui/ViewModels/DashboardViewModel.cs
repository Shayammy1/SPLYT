using System.Collections.ObjectModel;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;

namespace NovaVM.Gui.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private readonly LogService _log;
    private HostStats _stats = HostStats.Empty;
    private List<LogEntry> _alerts = new();

    public DashboardViewModel(NovaVmService vmService, LogService log)
    {
        _vmService = vmService;
        _log = log;
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        _ = LoadAsync();
    }

    public HostStats Stats { get => _stats; private set => SetProperty(ref _stats, value); }
    public ObservableCollection<VirtualMachine> Vms { get; } = new();
    public List<LogEntry> Alerts { get => _alerts; private set => SetProperty(ref _alerts, value); }

    public AsyncRelayCommand RefreshCommand { get; }

    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            Stats = await _vmService.GetHostStatsAsync();

            var vms = await _vmService.GetVmsAsync();
            Vms.Clear();
            foreach (var vm in vms) Vms.Add(vm);

            Alerts = _log.RecentAlerts().ToList();
        });
    }
}
