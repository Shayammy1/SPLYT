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
    [string]$AppName = "Desktop"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

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
    Start-Process -FilePath $moonlightPath -ArgumentList $arguments | Out-Null

    $result = [ordered]@{
        vmIp        = $vmIp
        resolution  = $Resolution
        fps         = $Fps
        bitrateKbps = $BitrateKbps
        appName     = $AppName
        message     = "Moonlight lance sur $vmIp en $Resolution a $Fps Hz, debit $([int]($BitrateKbps / 1000)) Mbit/s, 4:4:4 active."
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
