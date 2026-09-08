using System.Collections.ObjectModel;
using System.Windows.Threading;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;

namespace NovaVM.Gui.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private readonly LogService _log;
    private readonly HostUsageSampler _usageSampler = new();
    private readonly DispatcherTimer _usageTimer;
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

        // CPU et RAM rafraichis chaque seconde, mesures dans le processus (voir
        // HostUsageSampler) : assez leger pour cette cadence, contrairement au
        // script PowerShell qui alimente le reste. Le stockage n'en fait pas
        // partie - il n'evolue pas a cette echelle de temps.
        _usageTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _usageTimer.Tick += (_, _) => UpdateLiveUsage();
        _usageTimer.Start();

        _ = LoadAsync();
    }

    /// <summary>Ne remplace que le CPU et la RAM utilisee : la RAM TOTALE et le
    /// stockage restent ceux mesures par Get-NovaVmHostStats.ps1. La RAM totale
    /// vient volontairement de la, et non de l'API systeme, pour rester identique
    /// au chiffre qui borne la RAM attribuable a une VM (Get-NovaHostMemoryInfo) -
    /// sinon le total affiche sauterait de quelques dixiemes de Go entre le
    /// chargement initial et le premier tick.</summary>
    private void UpdateLiveUsage()
    {
        var cpuPercent = _usageSampler.SampleCpuPercent();
        var availableRamGb = _usageSampler.SampleAvailableRamGb();
        if (cpuPercent is null && availableRamGb is null) return;

        var current = Stats;
        var ramUsedGb = availableRamGb is null || current.RamTotalGb <= 0
            ? current.RamUsedGb
            : Math.Round(Math.Max(0, current.RamTotalGb - availableRamGb.Value), 1);

        Stats = new HostStats
        {
            CpuUsagePercent = cpuPercent ?? current.CpuUsagePercent,
            RamUsedGb = ramUsedGb,
            RamTotalGb = current.RamTotalGb,
            StorageUsedGb = current.StorageUsedGb,
            StorageTotalGb = current.StorageTotalGb,
        };
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
