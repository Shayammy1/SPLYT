using System.Collections.ObjectModel;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;

namespace NovaVM.Gui.ViewModels;

public sealed class StorageViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;

    public StorageViewModel(NovaVmService vmService)
    {
        _vmService = vmService;
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        _ = LoadAsync();
    }

    public ObservableCollection<VirtualDisk> Disks { get; } = new();
    public AsyncRelayCommand RefreshCommand { get; }

    public async Task LoadAsync()
    {
        await RunBusyAsync(async () =>
        {
            var disks = await _vmService.GetDisksAsync();
            Disks.Clear();
            foreach (var disk in disks) Disks.Add(disk);
        });
    }
}
