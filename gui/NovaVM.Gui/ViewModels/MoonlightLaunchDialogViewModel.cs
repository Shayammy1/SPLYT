using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// Choix de la resolution et de la frequence, propose avant chaque session
/// Moonlight.
///
/// Pourquoi demander plutot que deviner : dans le protocole Moonlight/Sunshine,
/// c'est le CLIENT qui reclame un mode d'affichage a chaque session, et Sunshine
/// l'applique a l'ecran virtuel VDD de l'invite (voir
/// Set-NovaVmStreamingQuality.ps1). Le mode choisi ici n'est donc pas une
/// preference cosmetique : il devient la resolution et la frequence reelles du
/// bureau diffuse.
/// </summary>
public sealed class MoonlightLaunchDialogViewModel : ViewModelBase
{
    /// <summary>Modes proposes. Cette liste doit rester alignee sur celle ecrite
    /// dans vdd_settings.xml par Set-NovaVmStreamingQuality.ps1 : le pilote VDD
    /// n'expose QUE les modes declares dans ce fichier, donc proposer ici une
    /// resolution absente de la-bas ferait echouer le changement de mode cote
    /// invite, sans autre explication qu'une image restee dans l'ancien format.</summary>
    private static readonly (int Width, int Height)[] SupportedResolutions =
    {
        (1280, 720),
        (1920, 1080),
        (2560, 1440),
        (3440, 1440),
        (3840, 2160),
    };

    private static readonly int[] SupportedRefreshRates = { 60, 90, 100, 120, 144 };

    private string _selectedResolution;
    private int _selectedRefreshRate;

    public MoonlightLaunchDialogViewModel(string vmName, string currentResolution, int currentRefreshRate)
    {
        VmName = vmName;
        Title = Loc.Get("Moonlight_Dialog_Title");
        Subtitle = Loc.Get("Moonlight_Dialog_Subtitle", vmName);
        ResolutionLabel = Loc.Get("Moonlight_Dialog_Resolution");
        RefreshRateLabel = Loc.Get("Moonlight_Dialog_RefreshRate");
        Hint = Loc.Get("Moonlight_Dialog_Hint");
        LaunchLabel = Loc.Get("Moonlight_Dialog_Launch");
        CancelLabel = Loc.Get("Common_Cancel");

        Resolutions = SupportedResolutions.Select(r => $"{r.Width}x{r.Height}").ToArray();
        RefreshRates = SupportedRefreshRates;

        // La derniere configuration connue de la VM sert de proposition, a condition
        // qu'elle fasse partie des modes reellement disponibles : une VM creee avec
        // une resolution exotique retomberait sinon sur une entree inexistante et la
        // liste s'afficherait vide.
        _selectedResolution = Resolutions.Contains(currentResolution) ? currentResolution : "1920x1080";
        _selectedRefreshRate = SupportedRefreshRates.Contains(currentRefreshRate) ? currentRefreshRate : 120;

        LaunchCommand = new RelayCommand(() => Close(true));
        CancelCommand = new RelayCommand(() => Close(false));
    }

    public string VmName { get; }
    public string Title { get; }
    public string Subtitle { get; }
    public string ResolutionLabel { get; }
    public string RefreshRateLabel { get; }
    public string Hint { get; }
    public string LaunchLabel { get; }
    public string CancelLabel { get; }

    public IReadOnlyList<string> Resolutions { get; }
    public IReadOnlyList<int> RefreshRates { get; }

    public string SelectedResolution { get => _selectedResolution; set => SetProperty(ref _selectedResolution, value); }
    public int SelectedRefreshRate { get => _selectedRefreshRate; set => SetProperty(ref _selectedRefreshRate, value); }

    public RelayCommand LaunchCommand { get; }
    public RelayCommand CancelCommand { get; }

    /// <summary>Emis exactement une fois : vrai si l'utilisateur lance, faux s'il
    /// annule.</summary>
    public event EventHandler<bool>? Closed;

    private bool _closed;

    private void Close(bool launch)
    {
        if (_closed) return;
        _closed = true;
        Closed?.Invoke(this, launch);
    }
}
