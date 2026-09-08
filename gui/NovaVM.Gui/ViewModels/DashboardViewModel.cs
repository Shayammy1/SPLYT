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

    /// <param name="vms">LA MEME collection que celle de la page "Machines
    /// virtuelles", pas une copie : les deux pages affichaient auparavant deux
    /// listes interrogees separement, qui finissaient par se contredire (une VM
    /// marquee demarree d'un cote, arretee de l'autre). En partageant les memes
    /// objets VirtualMachine, un changement d'etat se reflete instantanement des
    /// deux cotes et la contradiction devient structurellement impossible.</param>
    public DashboardViewModel(NovaVmService vmService, LogService log, ObservableCollection<VirtualMachine> vms)
    {
        _vmService = vmService;
        _log = log;
        Vms = vms;
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        _ = LoadAsync();
    }

    public HostStats Stats { get => _stats; private set => SetProperty(ref _stats, value); }
    public ObservableCollection<VirtualMachine> Vms { get; }
    public List<LogEntry> Alerts { get => _alerts; private set => SetProperty(ref _alerts, value); }

    public AsyncRelayCommand RefreshCommand { get; }

    /// <summary>Ne recharge PAS la liste des VMs : elle appartient a VmListViewModel,
    /// qui la tient a jour pour les deux pages (voir le constructeur).</summary>
    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            Stats = await _vmService.GetHostStatsAsync();
            Alerts = _log.RecentAlerts().ToList();
        });
    }
}
