using System.Diagnostics;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.ViewModels;

/// <summary>Modele de la boite de dialogue proposee automatiquement au demarrage de
/// SPLYT quand Hyper-V n'est pas encore actif sur ce PC (voir MainViewModel). Action
/// au niveau de la machine (pas d'une VM precise) : aucun identifiant necessaire,
/// juste une elevation (invite UAC) - voir NovaVmService.EnableHyperVAsync.</summary>
public sealed class HyperVSetupDialogViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private HyperVSetupResultDto? _result;

    public HyperVSetupDialogViewModel(NovaVmService vmService)
    {
        _vmService = vmService;

        EnableCommand = new AsyncRelayCommand(EnableAsync);
        DismissCommand = new RelayCommand(() => Dismissed?.Invoke(this, EventArgs.Empty));
        RestartNowCommand = new RelayCommand(RestartNow);
    }

    /// <summary>Non-null une fois EnableCommand termine avec succes : bascule
    /// l'affichage de la boite de dialogue de l'invite initiale vers le resultat.</summary>
    public HyperVSetupResultDto? Result
    {
        get => _result;
        private set
        {
            if (SetProperty(ref _result, value))
            {
                OnPropertyChanged(nameof(RebootRequired));
                OnPropertyChanged(nameof(NoRebootRequired));
            }
        }
    }

    /// <summary>Proprietes derivees (plutot que ConverterParameter="Invert" sur
    /// BoolToVisibilityConverter, qui est le BooleanToVisibilityConverter standard
    /// WPF et ne le supporte pas - contrairement a NullToVisibilityConverter).</summary>
    public bool RebootRequired => Result?.RebootRequired ?? false;
    public bool NoRebootRequired => Result is not null && !Result.RebootRequired;

    public AsyncRelayCommand EnableCommand { get; }
    public RelayCommand DismissCommand { get; }
    public RelayCommand RestartNowCommand { get; }

    public event EventHandler? Dismissed;

    private async Task EnableAsync()
    {
        await RunBusyAsync(async () =>
        {
            var (result, error) = await _vmService.EnableHyperVAsync();
            if (result is null)
            {
                ErrorMessage = error ?? Loc.Get("HyperV_EnableFailed");
                return;
            }

            Result = result;
        });
    }

    /// <summary>Redemarre le PC apres un court delai (le temps de lire le message) -
    /// shutdown.exe ne necessite pas d'elevation pour redemarrer LA machine locale
    /// (droit accorde par defaut a tout utilisateur interactif).</summary>
    private void RestartNow()
    {
        try
        {
            Process.Start(new ProcessStartInfo("shutdown.exe", $"/r /t 10 /c \"{Loc.Get("HyperV_RestartMessage")}\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            });
        }
        catch (Exception ex)
        {
            ErrorMessage = Loc.Get("HyperV_RestartFailed", ex.Message);
            return;
        }
        Dismissed?.Invoke(this, EventArgs.Empty);
    }
}
