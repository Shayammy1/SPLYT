using System.Collections.ObjectModel;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;

namespace NovaVM.Gui.ViewModels;

public sealed class GpuViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;

    public GpuViewModel(NovaVmService vmService)
    {
        _vmService = vmService;
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        _ = LoadAsync();
    }

    public ObservableCollection<HostGpu> Gpus { get; } = new();
    public AsyncRelayCommand RefreshCommand { get; }

    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            var gpus = await _vmService.GetHostGpusAsync();
            var vms = await _vmService.GetVmsAsync();

            Gpus.Clear();
            foreach (var gpu in gpus)
            {
                gpu.AssignedVmNames.Clear();
                gpu.AssignedVmNames.AddRange(vms.Where(v => v.GpuName == gpu.Name).Select(v => v.Name));
                Gpus.Add(gpu);
            }
        });
    }
}
