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
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
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
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref mode)) return null;
        if (mode.dmPelsWidth <= 0 || mode.dmPelsHeight <= 0) return null;
        return new int[] { mode.dmPositionX, mode.dmPositionY, mode.dmPelsWidth, mode.dmPelsHeight };
    }

    /// <summary>La fenetre du FLUX parmi celles de Moonlight. On la distingue du
    /// lanceur par son titre : celui-ci s'appelle exactement "Moonlight", tandis que
    /// la fenetre de flux porte le nom de l'hote diffuse. IntPtr.Zero tant qu'elle
    /// n'est pas encore apparue.</summary>
    public static IntPtr FindStreamWindow(int[] processIds) {
        IntPtr found = IntPtr.Zero;
        var wanted = new HashSet<uint>();
        foreach (int id in processIds) wanted.Add((uint)id);

        EnumWindows((hWnd, _) => {
            if (!IsWindowVisible(hWnd)) return true;
            uint owner;
            GetWindowThreadProcessId(hWnd, out owner);
            if (!wanted.Contains(owner)) return true;

            var title = new StringBuilder(256);
            GetWindowText(hWnd, title, title.Capacity);
            string text = title.ToString();
            if (text.Length == 0 || text == "Moonlight") return true;

            found = hWnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    public static bool MoveTo(IntPtr window, int x, int y, int width, int height) {
        bool moved = MoveWindow(window, x, y, width, height, true);
        if (moved) SetForegroundWindow(window);
        return moved;
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

    Write-NovaProgress "Ouverture de Moonlight"
    $arguments = @(
        "stream", $vmIp, $AppName,
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
    $moonlight = Start-Process -FilePath $moonlightPath -ArgumentList $arguments -PassThru

    # Placement sur l'ecran demande. Best-effort de bout en bout : un flux qui
    # s'affiche sur le mauvais ecran reste un flux qui marche, alors qu'un echec
    # ici ne doit surtout pas faire echouer le lancement.
    $monitorMessage = ""
    if (-not [string]::IsNullOrWhiteSpace($MonitorDeviceName)) {
        # "\\.\DISPLAY2" ne dit rien a personne : on parle de l'ecran 2, comme le
        # font la fenetre de choix et les parametres Windows.
        $monitorDigits = ($MonitorDeviceName -replace '\D', '')
        $monitorLabel = if ($monitorDigits) { "l'ecran $monitorDigits" } else { "l'ecran choisi" }

        Write-NovaProgress "Placement sur l'ecran choisi"
        [NovaMoonlightWindow]::MakeDpiAware()
        $bounds = [NovaMoonlightWindow]::GetMonitorBounds($MonitorDeviceName)
        if (-not $bounds) {
            $monitorMessage = " Moonlight reste ou il s'est ouvert : $monitorLabel n'est plus disponible."
        } else {
            # La fenetre de flux n'existe qu'une fois la connexion etablie, ce qui
            # prend plusieurs secondes : on la guette au lieu de la chercher une
            # seule fois.
            $window = [IntPtr]::Zero
            $deadline = (Get-Date).AddSeconds(45)
            while ((Get-Date) -lt $deadline -and $window -eq [IntPtr]::Zero) {
                if ($moonlight.HasExited) { break }
                $window = [NovaMoonlightWindow]::FindStreamWindow(@($moonlight.Id))
                if ($window -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 500 }
            }

            if ($window -eq [IntPtr]::Zero) {
                $monitorMessage = " La fenetre de Moonlight n'a pas ete trouvee a temps : elle reste sur son ecran d'origine."
            } elseif ([NovaMoonlightWindow]::MoveTo($window, $bounds[0], $bounds[1], $bounds[2], $bounds[3])) {
                $monitorMessage = " Affiche sur $monitorLabel."
            } else {
                $monitorMessage = " Le deplacement vers $monitorLabel a echoue."
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
        message     = "Moonlight lance sur $vmIp en $Resolution a $Fps Hz, debit $([int]($BitrateKbps / 1000)) Mbit/s, 4:4:4 active.$monitorMessage"
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
