<#
.SYNOPSIS
    Bouton "Lancer avec Moonlight" : demarre la VM si necessaire, attend qu'elle soit
    reellement joignable, puis ouvre Moonlight deja connecte a la session - sans que
    l'utilisateur ait a ouvrir Moonlight, choisir l'hote et regler quoi que ce soit.

    C'est ICI que se decide la qualite du flux, et pas dans Sunshine : dans le
    protocole Moonlight/Sunshine, c'est le CLIENT qui demande une resolution, une
    frequence et un debit ; le serveur encode ce qu'on lui demande. Regler "le debit
    dans Sunshine" n'existe pas.

    Les valeurs visent la meilleure qualite possible pour un flux LOCAL (l'hote et la
    VM sont la meme machine) :
    - debit calcule d'apres resolution x frequence (voir Get-NovaStreamBitrateKbps),
      tres au-dessus des defauts de Moonlight qui sont calibres pour du Wi-Fi ;
    - 4:4:4 : supprime le sous-echantillonnage de la chrominance, ce qui se voit
      surtout sur le texte et l'interface, et n'a de sens qu'a haut debit ;
    - lissage d'images (frame pacing) et optimisations jeu actives ;
    - codec laisse en "auto" : le client et le serveur negocient le meilleur commun
      (AV1/HEVC/H.264 selon le materiel), plutot que d'en imposer un que le decodeur
      de cette machine ne saurait peut-etre pas prendre en charge.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [int]$Fps = 100,
    [string]$Resolution = "",
    # 0 = calcule automatiquement d'apres la resolution et la frequence.
    [int]$BitrateKbps = 0,
    [string]$AppName = "Desktop",
    # Ecran de l'hote ou afficher le flux ("\\.\DISPLAY2"). Vide = la ou Moonlight
    # s'ouvre de lui-meme.
    [string]$MonitorDeviceName = ""
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Age minimal de la VM avant d'y brancher le flux. Voir l'attente correspondante
# plus bas : en dessous, l'affichage de l'invite n'a pas fini de se mettre en
# place et la capture de Sunshine echoue. Soixante secondes couvrent largement
# l'ouverture de session automatique et l'activation de l'ecran virtuel, et ne
# coutent rien sur une VM qui tournait deja.
$minimumUptimeSeconds = 60

# Deplacement de la fenetre de flux vers l'ecran demande.
#
# Moonlight 6.1 n'a AUCUNE option de ligne de commande pour choisir l'ecran, et la
# variable SDL_VIDEO_FULLSCREEN_DISPLAY, qui devrait epingler le plein ecran a un
# affichage donne, est sans effet ici (verifie sur cette version). Il reste donc a
# deplacer la fenetre une fois ouverte - ce qui fonctionne : elle se redimensionne
# a l'ecran d'arrivee et continue d'afficher le flux normalement.
#
# Tout se passe dans ce processus, en pixels reels : la conscience de la mise a
# l'echelle est reglee sur "par ecran" avant toute mesure, sinon Windows
# virtualiserait les coordonnees et la fenetre atterrirait a cote sur un poste dont
# les ecrans n'ont pas le meme facteur d'echelle.
#
# Ce code volontairement pauvre ne s'appuie que sur mscorlib et System : pas de
# generiques de collections, pas d'expression lambda. Add-Type compile avec le
# jeu de references par defaut de Windows PowerShell, et celui-ci depend du
# repertoire de travail du processus : lance depuis "C:\Program Files\SPLYT",
# comme le fait l'application installee, il ne resolvait plus System.Core et la
# compilation echouait sur un simple HashSet - le placement de la fenetre etait
# alors perdu alors que tout marchait depuis un autre dossier.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class NovaMoonlightWindow {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2;
        public int dmPanningWidth, dmPanningHeight;
    }

    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string deviceName, int mode, ref DEVMODE devMode);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll")]
    static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

    const int ENUM_CURRENT_SETTINGS = -1;

    static readonly IntPtr PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    /// <summary>A appeler avant toute mesure. Sans effet si une conscience est deja
    /// figee pour ce processus, ce qui n'est pas un probleme : elle ne peut alors
    /// qu'etre deja au moins aussi precise.</summary>
    public static void MakeDpiAware() {
        try { SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2); } catch { }
    }

    /// <summary>Place et taille de l'ecran nomme, en pixels reels. Null s'il
    /// n'existe plus - un ecran peut avoir ete debranche depuis l'affichage de la
    /// fenetre de choix.</summary>
    public static int[] GetMonitorBounds(string deviceName) {
        DEVMODE mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref mode)) return null;
        if (mode.dmPelsWidth <= 0 || mode.dmPelsHeight <= 0) return null;
        return new int[] { mode.dmPositionX, mode.dmPositionY, mode.dmPelsWidth, mode.dmPelsHeight };
    }

    /// <summary>La fenetre du FLUX parmi celles de Moonlight. On la distingue du
    /// lanceur par son titre : celui-ci s'appelle exactement "Moonlight", tandis que
    /// la fenetre de flux porte le nom de l'hote diffuse. IntPtr.Zero tant qu'elle
    /// n'est pas encore apparue.</summary>
    static IntPtr _found;
    static int[] _wantedProcessIds;

    static bool Visit(IntPtr hWnd, IntPtr lParam) {
        if (!IsWindowVisible(hWnd)) return true;

        uint owner;
        GetWindowThreadProcessId(hWnd, out owner);
        bool mine = false;
        for (int i = 0; i < _wantedProcessIds.Length; i++) {
            if ((uint)_wantedProcessIds[i] == owner) { mine = true; break; }
        }
        if (!mine) return true;

        StringBuilder title = new StringBuilder(256);
        GetWindowText(hWnd, title, title.Capacity);
        string text = title.ToString();
        if (text.Length == 0 || text == "Moonlight") return true;

        _found = hWnd;
        return false;
    }

    public static IntPtr FindStreamWindow(int[] processIds) {
        _found = IntPtr.Zero;
        _wantedProcessIds = processIds;
        EnumWindows(new EnumWindowsProc(Visit), IntPtr.Zero);
        return _found;
    }

    /// <summary>Deplace la fenetre SANS la mettre au premier plan : la passer devant
    /// lui ferait capturer la souris de l'hote, qui partirait alors dans la VM.</summary>
    public static bool MoveTo(IntPtr window, int x, int y, int width, int height) {
        return MoveWindow(window, x, y, width, height, true);
    }

    public static IntPtr Foreground() { return GetForegroundWindow(); }

    /// <summary>Vrai si la fenetre au premier plan appartient a ce processus. Sert
    /// a savoir si Moonlight vient de reprendre le focus - et donc la souris de
    /// l'hote - apres qu'on le lui a retire.</summary>
    public static bool ForegroundBelongsTo(int processId) {
        IntPtr front = GetForegroundWindow();
        if (front == IntPtr.Zero) return false;
        uint owner;
        GetWindowThreadProcessId(front, out owner);
        return owner == (uint)processId;
    }

    /// <summary>Redonne le premier plan a une fenetre de l'hote.
    ///
    /// Windows refuse SetForegroundWindow a un processus qui n'est pas deja
    /// devant, pour empecher les applications de voler le focus. Le detour
    /// habituel est de rattacher temporairement notre file d'entree a celle de la
    /// fenetre au premier plan et a celle de la cible : la demande vient alors
    /// "de l'interieur" et passe.</summary>
    public static bool RestoreForeground(IntPtr target) {
        if (target == IntPtr.Zero || !IsWindow(target)) return false;

        uint dummy;
        uint targetThread = GetWindowThreadProcessId(target, out dummy);
        uint currentThread = GetCurrentThreadId();
        IntPtr front = GetForegroundWindow();
        uint frontThread = GetWindowThreadProcessId(front, out dummy);

        AttachThreadInput(currentThread, frontThread, true);
        AttachThreadInput(currentThread, targetThread, true);
        bool ok = SetForegroundWindow(target);
        AttachThreadInput(currentThread, targetThread, false);
        AttachThreadInput(currentThread, frontThread, false);
        return ok;
    }
}
"@

Invoke-NovaAction {
    $moonlightPath = Get-NovaMoonlightPath
    if (-not $moonlightPath) {
        throw "Moonlight est introuvable sur cet ordinateur. Installez-le d'abord (action 'Preparer le streaming')."
    }

    # Resolution/frequence : celles configurees pour cette VM, sauf demande explicite.
    $prefs = Get-NovaVmPreferences -Name $Name
    if ([string]::IsNullOrWhiteSpace($Resolution)) {
        $Resolution = if ($prefs.resolution) { $prefs.resolution } else { "1920x1080" }
    }
    if (-not ($Resolution -match '^(\d+)x(\d+)$')) {
        throw "Resolution invalide : '$Resolution' (format attendu : 1920x1080)."
    }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]

    # Le mode retenu devient la proposition par defaut de la prochaine session : la
    # fenetre de choix repart de la, plutot que de redemander la meme chose a chaque
    # fois. Les autres champs des preferences (GPU, etc.) restent inchanges - voir
    # la fusion par $PSBoundParameters dans Save-NovaVmPreferences.
    Save-NovaVmPreferences -Name $Name -Resolution $Resolution -Hz $Fps

    if ($BitrateKbps -le 0) {
        $BitrateKbps = Get-NovaStreamBitrateKbps -Width $width -Height $height -Fps $Fps
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        Write-NovaProgress "Demarrage de la VM"
        Start-VM -Name $Name -ErrorAction Stop
    }

    # "Demarree" ne veut pas dire "Windows a fini de demarrer" : sans cette attente,
    # Moonlight se lancerait sur un hote injoignable et afficherait une erreur.
    Write-NovaProgress "Attente du demarrage de Windows dans la VM"
    $vmIp = $null
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline -and -not $vmIp) {
        # Par GUID et non par nom traduit - voir Test-NovaVmHeartbeatOk.
        if (Test-NovaVmHeartbeatOk -Name $Name) {
            $vmIp = Get-NovaVmIpAddress -Name $Name
        }
        if (-not $vmIp) { Start-Sleep -Seconds 3 }
    }
    if (-not $vmIp) {
        throw "Windows n'a pas fini de demarrer dans la VM (ou n'a pas d'adresse IP) apres 5 minutes."
    }

    # Sunshine demarre en service, mais quelques secondes apres la session Windows :
    # on attend qu'il accepte reellement les connexions plutot que de lancer Moonlight
    # dans le vide.
    Write-NovaProgress "Attente de Sunshine dans la VM"
    $sunshineReady = $false
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline -and -not $sunshineReady) {
        $test = Test-NetConnection -ComputerName $vmIp -Port 47989 -WarningAction SilentlyContinue -InformationLevel Quiet
        if ($test) { $sunshineReady = $true } else { Start-Sleep -Seconds 3 }
    }
    if (-not $sunshineReady) {
        throw "Sunshine ne repond pas dans la VM ($vmIp). Verifiez qu'il y est bien installe et demarre."
    }

    # Le port de Sunshine s'ouvre des le lancement de son service, donc tres tot
    # dans le demarrage de Windows - bien avant que la session soit ouverte et que
    # l'affichage se soit stabilise. Se connecter a cet instant fait echouer la
    # capture : Sunshine bascule l'ecran virtuel en cours de route, perd l'acces a
    # la duplication (DXGI_ERROR_ACCESS_LOST) et coupe la session au bout de
    # quelques secondes. Vu en vrai : VM demarree a 21:32:10, Sunshine pret a
    # 21:32:13, connexion a 21:32:16, session perdue a 21:32:36.
    #
    # On laisse donc la VM prendre un peu d'age avant de s'y connecter. Le temps
    # deja passe a l'attendre compte : sur une VM qui tournait deja, cette attente
    # est nulle.
    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    $uptime = if ($vm -and $vm.Uptime) { $vm.Uptime.TotalSeconds } else { $minimumUptimeSeconds }
    if ($uptime -lt $minimumUptimeSeconds) {
        $reste = [int]($minimumUptimeSeconds - $uptime)
        Write-NovaProgress "Stabilisation de l'affichage dans la VM ($reste s)"
        Start-Sleep -Seconds $reste
    }

    # Les peripheriques dedies a cette VM doivent l'avoir REJOINTE avant qu'on
    # affiche quoi que ce soit. Quand la VM est eteinte, l'hote les recupere ; a
    # son demarrage, une tache dans l'invite les reprend. Lancer le flux sans
    # attendre cette reprise laisse les deux souris sur l'hote, donc a piloter le
    # meme curseur - exactement le symptome "impossible de les separer".
    $attendus = @()
    if ($prefs -and $prefs.usbBusIds) {
        $attendus = @($prefs.usbBusIds -split ',' | Where-Object { $_ })
    }
    $usbMessage = ""
    if ($attendus.Count -gt 0) {
        $usbipdPath = Get-NovaUsbipdPath
        if ($usbipdPath) {
            Write-NovaProgress "Attente des peripheriques dedies a la VM"
            $manquants = $attendus
            $limiteUsb = (Get-Date).AddSeconds(60)
            while ((Get-Date) -lt $limiteUsb -and $manquants.Count -gt 0) {
                try {
                    $etat = (& $usbipdPath state 2>&1 | Out-String) | ConvertFrom-Json
                    $rattaches = @($etat.Devices | Where-Object { "$($_.ClientIPAddress)" -eq $vmIp } | ForEach-Object { "$($_.BusId)" })
                    $manquants = @($attendus | Where-Object { $rattaches -notcontains $_ })
                } catch {
                    # Etat illisible : on reessaiera au tour suivant.
                }
                if ($manquants.Count -gt 0) { Start-Sleep -Seconds 2 }
            }
            if ($manquants.Count -gt 0) {
                $usbMessage = " Attention : la VM n'a pas repris " + ($manquants -join ', ') +
                              " ; ces peripheriques pilotent encore l'hote."
            }
        }
    } else {
        # Liste inconnue : on apprend de ce qu'on observe. Les peripheriques
        # confies a une VM avant l'existence de cette memoire, ou attribues a la
        # main, seraient sinon ignores pour toujours - et le lancement suivant
        # repartirait sans les attendre.
        $usbipdPath = Get-NovaUsbipdPath
        if ($usbipdPath) {
            try {
                $etat = (& $usbipdPath state 2>&1 | Out-String) | ConvertFrom-Json
                $vus = @($etat.Devices | Where-Object { "$($_.ClientIPAddress)" -eq $vmIp } | ForEach-Object { "$($_.BusId)" })
                if ($vus.Count -gt 0) { Save-NovaVmPreferences -Name $Name -UsbBusIds ($vus -join ',') }
            } catch {
                # Sans etat lisible, il n'y a rien a apprendre ce coup-ci.
            }
        }
    }

    Write-NovaProgress "Ouverture de Moonlight"
    # $AppName entre guillemets : un nom d'application Sunshine peut contenir un
    # espace, et Start-Process colle les elements du tableau sans rien proteger -
    # le nom se couperait en deux arguments (voir Start-NovaVm.ps1, ou le meme
    # defaut empechait toute installation automatique de demarrer).
    $arguments = @(
        "stream", $vmIp, "`"$AppName`"",
        "--resolution", $Resolution,
        "--fps", "$Fps",
        "--bitrate", "$BitrateKbps",
        "--display-mode", "fullscreen",
        "--video-codec", "auto",
        "--yuv444",
        "--frame-pacing",
        "--game-optimization",
        "--no-audio-on-host",
        "--capture-system-keys", "fullscreen"
    )
    # Surtout PAS de -RedirectStandardOutput/-RedirectStandardError ici, malgre
    # l'interet qu'aurait le journal de Moonlight pour le diagnostic : la
    # redirection fait demarrer Moonlight avec l'heritage des handles, et il garde
    # alors ouvert le tuyau de sortie que SPLYT branche sur PowerShell. SPLYT
    # attend la fermeture de ce tuyau pour rendre la main : il resterait bloque sur
    # "Lancement..." pendant toute la session de jeu. Mesure faite, pas supposee.
    #
    # Pour diagnostiquer un lancement qui ne donne rien, Moonlight tient de toute
    # facon son propre journal dans %TEMP%\Moonlight-*.log.
    # La VM a-t-elle ses propres souris/clavier ? Si oui, Moonlight ne doit pas
    # garder le premier plan : en le gardant il capture la souris de l'HOTE, qui
    # part alors elle aussi dans la VM - les deux souris pilotent la meme machine,
    # et l'utilisateur doit faire un Ctrl+Alt+Suppr pour que Moonlight lache prise.
    # Avec un peripherique dedie, l'invite a de quoi etre pilote sans ce vol de
    # focus ; sans peripherique dedie, au contraire, le focus est le SEUL moyen de
    # se servir de la VM, et on le laisse donc a Moonlight.
    [NovaMoonlightWindow]::MakeDpiAware()

    # Question posee DEUX fois, et non une. Apres un demarrage a froid, la tache
    # qui rebranche les peripheriques dans l'invite peut n'avoir pas encore fini
    # quand on arrive ici ; la reponse d'alors serait "non" a tort, et le focus
    # resterait a Moonlight pour toute la session.
    $testVmOwnsInput = {
        $usbipdPath = Get-NovaUsbipdPath
        if (-not $usbipdPath) { return $false }
        try {
            $usbState = (& $usbipdPath state 2>&1 | Out-String) | ConvertFrom-Json
            return @($usbState.Devices | Where-Object { "$($_.ClientIPAddress)" -eq $vmIp }).Count -gt 0
        } catch {
            # Etat illisible : on se comporte comme sans peripherique dedie.
            return $false
        }
    }

    $vmOwnsInput = & $testVmOwnsInput
    $previousForeground = [NovaMoonlightWindow]::Foreground()

    $moonlight = Start-Process -FilePath $moonlightPath -ArgumentList $arguments -PassThru

    # Placement sur l'ecran demande. Best-effort de bout en bout : un flux qui
    # s'affiche sur le mauvais ecran reste un flux qui marche, alors qu'un echec
    # ici ne doit surtout pas faire echouer le lancement.
    $monitorMessage = ""
    $focusMessage = ""
    $wantsPlacement = -not [string]::IsNullOrWhiteSpace($MonitorDeviceName)

    # La redirection USB installee suffit a justifier l'attente de la fenetre :
    # c'est seulement une fois celle-ci apparue qu'on saura si la VM a recupere
    # ses peripheriques. Attendre pour rien coute peu - l'attente s'arrete des que
    # la fenetre existe, soit quelques secondes.
    if ($wantsPlacement -or $vmOwnsInput -or (Get-NovaUsbipdPath)) {
        # La fenetre de flux n'existe qu'une fois la connexion etablie, ce qui
        # prend plusieurs secondes : on la guette au lieu de la chercher une seule
        # fois. Cette attente sert aux deux traitements qui suivent.
        Write-NovaProgress "Attente de la fenetre de Moonlight"
        $window = [IntPtr]::Zero
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $deadline -and $window -eq [IntPtr]::Zero) {
            if ($moonlight.HasExited) { break }
            $window = [NovaMoonlightWindow]::FindStreamWindow(@($moonlight.Id))
            if ($window -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 500 }
        }

        # --- Placement sur l'ecran demande ---------------------------------
        # Best-effort de bout en bout : un flux qui s'affiche sur le mauvais ecran
        # reste un flux qui marche, alors qu'un echec ici ne doit surtout pas
        # faire echouer le lancement.
        if ($wantsPlacement) {
            # "\\.\DISPLAY2" ne dit rien a personne : on parle de l'ecran 2, comme
            # le font la fenetre de choix et les parametres Windows.
            $monitorDigits = ($MonitorDeviceName -replace '\D', '')
            $monitorLabel = if ($monitorDigits) { "l'ecran $monitorDigits" } else { "l'ecran choisi" }

            $bounds = [NovaMoonlightWindow]::GetMonitorBounds($MonitorDeviceName)
            if (-not $bounds) {
                $monitorMessage = " Moonlight reste ou il s'est ouvert : $monitorLabel n'est plus disponible."
            } elseif ($window -eq [IntPtr]::Zero) {
                $monitorMessage = " La fenetre de Moonlight n'a pas ete trouvee a temps : elle reste sur son ecran d'origine."
            } elseif ([NovaMoonlightWindow]::MoveTo($window, $bounds[0], $bounds[1], $bounds[2], $bounds[3])) {
                $monitorMessage = " Affiche sur $monitorLabel."
            } else {
                $monitorMessage = " Le deplacement vers $monitorLabel a echoue."
            }
        }

        # --- Restitution du premier plan a l'hote ---------------------------
        # Seconde interrogation, maintenant que la VM a fini de demarrer et que sa
        # tache de rebranchement a eu le temps de s'executer.
        if (-not $vmOwnsInput) { $vmOwnsInput = & $testVmOwnsInput }

        if ($vmOwnsInput -and $window -ne [IntPtr]::Zero) {
            Write-NovaProgress "Restitution du clavier et de la souris a l'hote"

            # Insister, et ne pas se contenter d'une tentative unique. Moonlight ne
            # prend pas le premier plan une fois pour toutes : il le reprend quand
            # sa fenetre de flux apparait, puis encore lorsqu'elle passe en plein
            # ecran. Une seule restitution, placee au mauvais moment, se faisait
            # donc annuler - d'ou des lancements ou les deux souris restaient liees
            # et ou il fallait un Ctrl+Alt+Suppr pour s'en sortir.
            #
            # On surveille douze secondes au plus, et on ne s'arrete avant que si le
            # premier plan est reste hors de Moonlight QUATRE SECONDES d'affilee.
            # Un arret apres quelques centaines de millisecondes de calme laissait
            # passer la seconde prise de focus, celle du passage en plein ecran :
            # mesure faite, la reprise arrive environ trois secondes apres la
            # premiere. Passe ce delai, cliquer dans la fenetre redonne la main a
            # Moonlight, comme il se doit.
            $rendu = $false
            $calmeDepuis = $null
            $limite = (Get-Date).AddSeconds(12)
            while ((Get-Date) -lt $limite) {
                Start-Sleep -Milliseconds 300
                if ([NovaMoonlightWindow]::ForegroundBelongsTo($moonlight.Id)) {
                    if ([NovaMoonlightWindow]::RestoreForeground($previousForeground)) { $rendu = $true }
                    $calmeDepuis = $null
                } else {
                    $rendu = $true
                    if (-not $calmeDepuis) { $calmeDepuis = Get-Date }
                    elseif (((Get-Date) - $calmeDepuis).TotalSeconds -ge 4) { break }
                }
            }

            if ($rendu) {
                $focusMessage = " La souris et le clavier de l'hote lui restent acquis : la VM a les siens."
            } else {
                $focusMessage = " Attention : Moonlight a garde le clavier et la souris de l'hote. Cliquez hors de sa fenetre pour les recuperer."
            }
        }
    }

    $result = [ordered]@{
        vmIp        = $vmIp
        resolution  = $Resolution
        fps         = $Fps
        bitrateKbps = $BitrateKbps
        appName     = $AppName
        monitor     = $MonitorDeviceName
        message     = "Moonlight lance sur $vmIp en $Resolution a $Fps Hz, debit $([int]($BitrateKbps / 1000)) Mbit/s, 4:4:4 active.$monitorMessage$focusMessage$usbMessage"
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
