using System.Text;
using NovaVM.Gui.Models;
using NovaVM.Gui.Mvvm;
using NovaVM.Gui.Services;
using NovaVM.Gui.Services.Localization;

namespace NovaVM.Gui.ViewModels;

/// <summary>
/// Le bouton "SPLYT" : enchaine d'un seul clic toute la configuration d'une VM sur
/// laquelle Windows vient d'etre installe - GPU-P, pilote graphique, VDD, Sunshine -
/// en arretant et redemarrant la VM quand c'est necessaire.
///
/// Pourquoi cet enchainement vit ici et pas dans un script PowerShell unique : les
/// etapes n'ont pas le meme mode d'execution. Le GPU-P et le pilote exigent la VM
/// ETEINTE (et le pilote, une elevation UAC) ; VDD et Sunshine exigent au contraire
/// la VM DEMARREE et une authentification dans le Windows invite. Un seul script ne
/// peut pas basculer entre ces modes ; PowerShellRunner, si.
///
/// Deux limites assumees, imposees par Windows et par Sunshine eux-memes :
/// - les identifiants Windows de la VM sont indispensables (installer un logiciel
///   dans un invite demande de s'y authentifier) ; ils ne sont jamais journalises,
///   et memorises seulement si l'utilisateur le demande (VmCredentialStore) ;
/// - l'appariement Sunshine/Moonlight par code PIN reste manuel : c'est la
///   protection anti-streaming-non-consenti de Sunshine, jamais contournee.
/// </summary>
public sealed class SplytSetupDialogViewModel : ViewModelBase
{
    private readonly NovaVmService _vmService;
    private readonly IReadOnlyList<HostGpu> _hostGpus;
    private string _username = "";
    private bool _rememberCredentials;
    private string? _currentStep;
    private double _progressPercent;
    private string? _resultText;
    private bool _isFinished;

    public SplytSetupDialogViewModel(NovaVmService vmService, VirtualMachine vm, IReadOnlyList<HostGpu> hostGpus)
    {
        _vmService = vmService;
        _hostGpus = hostGpus;
        Vm = vm;

        RunCommand = new AsyncRelayCommand(RunAsync, () => !string.IsNullOrWhiteSpace(Username) && !IsFinished);
        CloseCommand = new RelayCommand(() => Closed?.Invoke(this, EventArgs.Empty));

        if (VmCredentialStore.TryLoad(vm.Name, out var savedUsername, out var savedPassword))
        {
            Username = savedUsername;
            InitialPassword = savedPassword;
            RememberCredentials = true;
        }
    }

    public VirtualMachine Vm { get; }
    public string VmName => Vm.Name;

    public string Username
    {
        get => _username;
        set { if (SetProperty(ref _username, value)) RunCommand.RaiseCanExecuteChanged(); }
    }

    public bool RememberCredentials { get => _rememberCredentials; set => SetProperty(ref _rememberCredentials, value); }

    /// <summary>Mot de passe recharge depuis le Gestionnaire d'identifiants Windows,
    /// applique une seule fois par la vue (code-behind) : WPF n'expose jamais
    /// PasswordBox.Password comme DependencyProperty.</summary>
    public string? InitialPassword { get; }

    /// <summary>Cablee par la vue (code-behind) : lit le PasswordBox.</summary>
    public Func<string>? GetPassword { get; set; }

    public string? CurrentStep { get => _currentStep; private set => SetProperty(ref _currentStep, value); }
    public double ProgressPercent { get => _progressPercent; private set => SetProperty(ref _progressPercent, value); }
    public string? ResultText { get => _resultText; private set => SetProperty(ref _resultText, value); }

    /// <summary>Vrai une fois l'enchainement termine : le bouton "SPLYT" laisse
    /// alors place au compte rendu et a la fermeture.</summary>
    public bool IsFinished
    {
        get => _isFinished;
        private set
        {
            if (SetProperty(ref _isFinished, value))
            {
                OnPropertyChanged(nameof(NotFinished));
                RunCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public bool NotFinished => !IsFinished;

    public AsyncRelayCommand RunCommand { get; }
    public RelayCommand CloseCommand { get; }

    public event EventHandler? Closed;

    /// <summary>Emis quand l'enchainement a modifie l'etat de la VM, pour que la
    /// liste se resynchronise sans attendre le rafraichissement periodique.</summary>
    public event EventHandler? VmChanged;

    private const int TotalSteps = 7;

    private async Task RunAsync()
    {
        var password = GetPassword?.Invoke() ?? "";
        if (string.IsNullOrEmpty(password))
        {
            ResultText = Loc.Get("Common_PasswordRequired");
            return;
        }

        var report = new StringBuilder();
        var step = 0;

        await RunBusyAsync(async () =>
        {
            // --- 1. VM eteinte : requis par le GPU-P et par la copie du pilote ---
            Advance(++step, "Splyt_Step_Stopping");
            if (Vm.State == VmState.Running)
            {
                await _vmService.StopVmAsync(Vm.Name);
                // L'arret propre peut prendre du temps ; on ne bloque pas dessus
                // indefiniment, l'etape suivante echouera clairement si besoin.
                await WaitUntilOffAsync();
            }

            // Profite de la VM eteinte pour activer l'interface de services invite :
            // c'est elle qui permet d'y deposer l'installeur Sunshine (Copy-VMFile),
            // et elle n'est utilisable qu'apres un demarrage complet. L'activer ici,
            // juste avant le redemarrage de l'etape 4, evite a l'utilisateur un
            // aller-retour "redemarrez puis relancez l'action".
            await _vmService.EnableGuestServicesAsync(Vm.Name);

            // --- 2. GPU-P (si un GPU partitionnable existe sur cet hote) ---
            Advance(++step, "Splyt_Step_Gpu");
            var gpu = _hostGpus.FirstOrDefault(g => g.PartitionSupported);
            if (gpu is null)
            {
                report.AppendLine(Loc.Get("Splyt_Report_NoGpu"));
            }
            else
            {
                var vramMb = gpu.VramBytes > 0
                    ? (int)(gpu.VramBytes / 1024 / 1024 / 2)   // moitie de la VRAM reelle
                    : 4096;                                     // GPU integre : valeur indicative, Hyper-V repartit seul
                var (updated, gpuError) = await _vmService.SetGpuPartitionAsync(Vm.Name, gpu.Name, vramMb);
                report.AppendLine(updated is not null
                    ? Loc.Get("Splyt_Report_GpuOk", gpu.Name)
                    : Loc.Get("Splyt_Report_GpuFailed", gpuError));
            }

            // --- 3. Pilote graphique copie dans la VM (elevation UAC, plusieurs minutes) ---
            Advance(++step, "Splyt_Step_Driver");
            if (gpu is not null)
            {
                var (driver, driverError) = await _vmService.InstallGpuDriverAsync(Vm.Name, OnStepProgress);
                report.AppendLine(driver is not null
                    ? Loc.Get("Splyt_Report_DriverOk")
                    : Loc.Get("Splyt_Report_DriverFailed", driverError));
            }

            // --- 4. Redemarrage + attente reelle du demarrage de Windows ---
            Advance(++step, "Splyt_Step_Starting");
            await _vmService.StartVmAsync(Vm.Name);
            VmChanged?.Invoke(this, EventArgs.Empty);

            var guestReady = await _vmService.WaitForGuestReadyAsync(Vm.Name, OnStepProgress);
            if (!guestReady)
            {
                // Sans invite qui repond, VDD et Sunshine ne peuvent pas s'installer :
                // inutile de les tenter pour accumuler deux echecs de plus.
                report.AppendLine(Loc.Get("Splyt_Report_GuestNotReady"));
                Finish(report);
                return;
            }

            // --- 5. VDD (ecran virtuel, pour le 100+ Hz) ---
            Advance(++step, "Splyt_Step_Vdd");
            var (vdd, vddError) = await _vmService.InstallVddAsync(Vm.Name, ResolveUsername(Username), password);
            report.AppendLine(vdd is not null
                ? Loc.Get("Splyt_Report_VddOk")
                : Loc.Get("Splyt_Report_VddFailed", vddError));

            // --- 6. Sunshine (streaming vers le second ecran) ---
            // La preparation N'EST PAS optionnelle : c'est elle qui installe Moonlight
            // sur l'hote et depose l'installeur Sunshine sur le Bureau de la VM.
            // L'installation qui suit echoue avec "installeur introuvable" sans elle -
            // dependance silencieuse deja signalee dans SunshineCredentialsDialogViewModel,
            // et qui manquait bel et bien ici.
            Advance(++step, "Splyt_Step_Sunshine");
            var (streamingPrep, prepError) = await _vmService.EnableStreamingAsync(Vm.Name);
            if (streamingPrep is null)
            {
                report.AppendLine(Loc.Get("Splyt_Report_StreamingPrepFailed", prepError));
            }

            var (sunshine, sunshineError) = await _vmService.InstallSunshineAutomaticallyAsync(
                Vm.Name, ResolveUsername(Username), password);
            report.AppendLine(sunshine is not null
                ? Loc.Get("Splyt_Report_SunshineOk", sunshine.SunshineWebUiUrl)
                : Loc.Get("Splyt_Report_SunshineFailed", sunshineError));

            // --- 7. Reglages de qualite + appariement automatique ---
            // Sans interet si Sunshine ne s'est pas installe : on ne va pas configurer
            // puis apparier quelque chose qui n'existe pas.
            if (sunshine is not null)
            {
                Advance(++step, "Splyt_Step_Streaming");
                var (streaming, streamingError) = await _vmService.SetStreamingQualityAsync(
                    Vm.Name, ResolveUsername(Username), password);
                report.AppendLine(streaming is not null
                    ? streaming.Message ?? Loc.Get("Splyt_Report_StreamingOk")
                    : Loc.Get("Splyt_Report_StreamingFailed", streamingError));
            }

            if (RememberCredentials) VmCredentialStore.Save(Vm.Name, Username, password);
            else VmCredentialStore.Delete(Vm.Name);

            Finish(report);
        });
    }

    private void Advance(int step, string labelKey)
    {
        CurrentStep = Loc.Get(labelKey);
        ProgressPercent = (step - 1) * 100.0 / TotalSteps;
    }

    /// <summary>Progression fine remontee par un script (copie du pilote, attente du
    /// demarrage) : remplace le libelle d'etape sans toucher au pourcentage global.</summary>
    private void OnStepProgress(string text)
    {
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => { CurrentStep = text; });
    }

    private void Finish(StringBuilder report)
    {
        report.AppendLine();
        report.Append(Loc.Get("Splyt_Report_PairingReminder"));

        ProgressPercent = 100;
        CurrentStep = null;
        ResultText = report.ToString().Trim();
        IsFinished = true;
        VmChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Laisse a Hyper-V le temps de terminer un arret propre avant de
    /// toucher a la configuration de la VM.</summary>
    private async Task WaitUntilOffAsync()
    {
        for (var i = 0; i < 60; i++)
        {
            var vms = await _vmService.GetVmsAsync();
            var current = vms.FirstOrDefault(v => v.Name == Vm.Name);
            if (current is null || current.State == VmState.Off) return;
            await Task.Delay(2000);
        }
    }

    /// <summary>Meme regle que dans VmListViewModel : un compte Microsoft ne peut
    /// s'authentifier localement que sous la forme "MicrosoftAccount\email".</summary>
    private static string ResolveUsername(string username)
    {
        var trimmed = username.Trim();
        return trimmed.Contains('@') && !trimmed.Contains('\\') ? $"MicrosoftAccount\\{trimmed}" : trimmed;
    }
}
