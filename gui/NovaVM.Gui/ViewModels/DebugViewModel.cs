using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>Page "Depannage" : les reparations qui touchent l'ORDINATEUR HOTE plutot
/// qu'une VM en particulier, et qu'on ne veut donc pas voir melangees aux reglages
/// d'une machine. Aujourd'hui la remise en route du reseau des VMs ; d'autres
/// pannes recurrentes viendront naturellement s'ajouter ici.</summary>
public sealed class DebugViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private string? _networkRepairStatus;
    private bool _isRepairingNetwork;
    private bool _lastRepairSucceeded;

    public DebugViewModel(NovaVmService vmService)
    {
        _vmService = vmService;
        RepairNetworkCommand = new AsyncRelayCommand(RepairNetworkAsync, () => !IsRepairingNetwork);
    }

    public AsyncRelayCommand RepairNetworkCommand { get; }

    public bool IsRepairingNetwork
    {
        get => _isRepairingNetwork;
        private set
        {
            if (SetProperty(ref _isRepairingNetwork, value)) RepairNetworkCommand.RaiseCanExecuteChanged();
        }
    }

    /// <summary>Etape en cours pendant l'operation, puis compte rendu final.</summary>
    public string? NetworkRepairStatus { get => _networkRepairStatus; private set => SetProperty(ref _networkRepairStatus, value); }

    /// <summary>Colore le compte rendu : une reparation qui n'a rien change doit se
    /// distinguer au premier coup d'oeil d'une reparation qui a fonctionne.</summary>
    public bool LastRepairSucceeded { get => _lastRepairSucceeded; private set => SetProperty(ref _lastRepairSucceeded, value); }

    private async Task RepairNetworkAsync()
    {
        IsRepairingNetwork = true;
        LastRepairSucceeded = false;
        NetworkRepairStatus = Loc.Get("Debug_Network_InProgress");
        try
        {
            var (result, error) = await _vmService.RepairVmNetworkAsync(OnRepairProgress);
            if (result is null)
            {
                NetworkRepairStatus = Loc.Get("Debug_Network_Failed", error);
                return;
            }

            LastRepairSucceeded = result.WorkedAfter;
            NetworkRepairStatus = result.Message;
        }
        finally
        {
            IsRepairingNetwork = false;
        }
    }

    /// <summary>Appele depuis le thread qui suit la sortie du script eleve, pas le
    /// thread UI : on repasse par le Dispatcher avant de toucher une propriete liee.</summary>
    private void OnRepairProgress(string step)
    {
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => { NetworkRepairStatus = step; });
    }
}
