<#
    NovaVm.Common.psm1

    Fonctions partagees par tous les scripts du backend "Hyper-V" de NovaVM.

    Contrat de sortie : chaque script *.ps1 de ce dossier ecrit EXACTEMENT une
    ligne JSON sur stdout, de la forme :
        { "success": true|false, "data": <objet|tableau|null>, "error": <string|null> }

    Remarque PowerShell 5.1 (piege verifie empiriquement) : ne jamais envelopper
    un resultat de ConvertFrom-Json avec @(...) - meme indirectement via une
    fonction intermediaire. ConvertFrom-Json marque deja son tableau comme "ne
    pas re-enumerer" ; @(...) l'evalue alors comme un pipeline qui ne voit
    qu'"un seul objet emis" (le tableau lui-meme) et le re-enveloppe dans un
    tableau supplementaire a un seul element. Assigner directement le resultat
    ($x = $raw | ConvertFrom-Json, sans @()) produit le tableau plat attendu,
    pour 0, 1 ou N elements. A l'ecriture, ConvertTo-Json a le probleme
    inverse (aplatit un tableau d'un seul element en objet simple) : c'est
    pour ca que ConvertTo-NovaJsonArray serialise chaque element
    individuellement puis assemble le tableau JSON a la main.

    Les VMs sont de VRAIES VMs Hyper-V (Get-VM/New-VM/Start-VM/...). Seules
    quelques preferences qui n'ont pas d'equivalent Hyper-V direct (GPU-P
    choisi, resolution/frequence souhaitees) sont gardees dans un petit
    fichier JSON local (vm-preferences.json), cle par nom de VM.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# C:\NovaVM (pas un sous-dossier de $PSScriptRoot) : une fois SPLYT installe,
# les scripts vivent sous Program Files, protege en ecriture pour un
# utilisateur non-elevé - y ecrire echouait avec "L'acces au chemin ... est
# refuse". C:\NovaVM est deja la convention pour les autres donnees
# persistantes de l'app (disques de VM, ISO telechargees, settings.json).
$script:DataDir = "C:\NovaVM\Data"

function Get-NovaDataStorePath {
    param([Parameter(Mandatory)][string]$Name)
    Join-Path $script:DataDir "$Name.json"
}

# Serialise un ou plusieurs objets en tableau JSON, sans jamais passer de
# collection a ConvertTo-Json (voir remarque en tete de fichier).
function ConvertTo-NovaJsonArray {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,
        [int]$Depth = 8
    )
    begin {
        $items = New-Object System.Collections.ArrayList
    }
    process {
        if ($null -eq $InputObject) { return }
        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            foreach ($item in $InputObject) { [void]$items.Add($item) }
        } else {
            [void]$items.Add($InputObject)
        }
    }
    end {
        if ($items.Count -eq 0) { return "[]" }
        $parts = foreach ($item in $items) { $item | ConvertTo-Json -Depth $Depth -Compress }
        return "[" + ($parts -join ",") + "]"
    }
}

# Ecrit l'enveloppe JSON standard sur stdout. $DataJson doit deja etre du
# JSON valide (objet, tableau, ou "null"), typiquement produit par
# ConvertTo-Json -Compress (objet unique) ou ConvertTo-NovaJsonArray (liste).
function Write-NovaResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [string]$DataJson = "null",
        [string]$ErrorMessage = $null
    )
    $errJson = if ([string]::IsNullOrEmpty($ErrorMessage)) { "null" } else { ($ErrorMessage | ConvertTo-Json -Compress) }
    $successJson = $Success.ToString().ToLowerInvariant()
    $line = '{"success":' + $successJson + ',"data":' + $DataJson + ',"error":' + $errJson + '}'
    Write-Output $line
}

# Ligne de progression optionnelle, ecrite AVANT le resultat final : un objet
# sans propriete "success", donc ignoree par PowerShellResult.Parse (qui
# cherche la derniere ligne avec "success") mais lisible en temps reel par
# PowerShellRunner.RunWithProgressAsync cote C# pour alimenter une barre de
# progression qui reflete l'avancement reel du script (pas une simulation).
function Write-NovaProgress {
    param([Parameter(Mandatory)][string]$Step)
    Write-Output ('{"progress":' + ($Step | ConvertTo-Json -Compress) + '}')
}

# Execute $Action et transforme toute exception en enveloppe d'echec
# correctement formee, pour eviter de dupliquer un try/catch dans chaque script.
function Invoke-NovaAction {
    param([Parameter(Mandatory)][scriptblock]$Action)
    try {
        & $Action
    } catch {
        Write-NovaResult -Success $false -ErrorMessage $_.Exception.Message
    }
}

# --- RAM hote reelle -------------------------------------------------------

# RAM physique reelle (pas seulement "visible par l'OS", legerement inferieure)
# + une limite raisonnable pour une VM, en reservant de la memoire pour l'hote.
function Get-NovaHostMemoryInfo {
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalMb = [math]::Round([double]$cs.TotalPhysicalMemory / 1MB, 0)

    $reservedForHostMb = 2048
    $maxVmMemoryMb = [math]::Max(1024, $totalMb - $reservedForHostMb)

    # Coeurs PHYSIQUES et processeurs LOGIQUES (threads) reels, additionnes sur
    # tous les sockets. Hyper-V accepte techniquement jusqu'au nombre de
    # processeurs logiques, mais la GUI borne le curseur vCPU aux coeurs
    # physiques : au-dela, les vCPU se partagent les memes coeurs physiques, ce
    # qui degrade les performances au lieu de les ameliorer (contre-productif
    # pour l'usage vise, du jeu dans la VM) - et 8 coeurs qui proposent 16 vCPU
    # est trompeur. Les deux valeurs sont remontees pour pouvoir afficher le
    # detail ("8 coeurs / 16 threads") plutot qu'un chiffre sans contexte.
    $processors = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $cores = 0
    $logical = 0
    foreach ($cpu in $processors) {
        if ($cpu.NumberOfCores) { $cores += [int]$cpu.NumberOfCores }
        if ($cpu.NumberOfLogicalProcessors) { $logical += [int]$cpu.NumberOfLogicalProcessors }
    }
    # Repli si WMI ne repond pas : [Environment]::ProcessorCount est toujours
    # disponible (processeurs logiques), jamais 0.
    if ($logical -le 0) { $logical = [Environment]::ProcessorCount }
    if ($cores -le 0) { $cores = $logical }

    [ordered]@{
        totalPhysicalMb      = [int64]$totalMb
        maxVmMemoryMb        = [int64]$maxVmMemoryMb
        cpuCores             = [int]$cores
        cpuLogicalProcessors = [int]$logical
    }
}

# Ferme la fenetre de l'Explorateur que Windows ouvre automatiquement au
# montage d'un VHD/VHDX (notification d'arrivee de volume) : elle passe au
# premier plan et vole le focus en pleine operation SPLYT, alors que le volume
# concerne sera demonte quelques secondes/minutes plus tard - la fenetre
# deviendrait morte de toute facon. On ne ferme QUE celles qui pointent vers
# la lettre de lecteur qu'on vient de monter, jamais une fenetre ouverte par
# l'utilisateur ailleurs. Best-effort : ne doit jamais faire echouer
# l'operation en cours.
function Close-NovaMountedVolumeExplorerWindow {
    param([Parameter(Mandatory)][string]$DriveLetter)

    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            try {
                $location = $window.LocationURL
                # LocationURL d'un dossier local ressemble a "file:///E:/..." :
                # on cible la lettre de lecteur exacte, rien d'autre.
                if ($location -and $location -match "^file:///$([regex]::Escape($DriveLetter)):") {
                    $window.Quit()
                }
            } catch {
                # Fenetre disparue entre l'enumeration et l'appel : sans importance.
            }
        }
    } catch {
        # Shell.Application indisponible (session sans Explorateur, par exemple) :
        # il n'y avait alors aucune fenetre a fermer.
    }
}

# Vrai quand le heartbeat Hyper-V de la VM repond : c'est LA preuve qu'un systeme a
# demarre normalement a l'interieur, services d'integration compris.
#
# Le filtre se fait sur le GUID du composant, JAMAIS sur son nom : les noms des
# services d'integration sont TRADUITS par Windows ("Heartbeat" en anglais mais
# "Pulsation" en francais). Un "Get-VMIntegrationService -Name 'Heartbeat'" ne
# renvoie donc rien du tout sur un Windows francais - sans erreur, ce qui donne un
# echec parfaitement silencieux : SPLYT concluait "Windows n'est pas installe" sur
# une VM parfaitement demarree. Meme raison que le SID en dur pour les groupes
# locaux et que le GUID de l'interface de services invite dans
# Enable-NovaVmStreaming.ps1.
function Test-NovaVmHeartbeatOk {
    param([Parameter(Mandatory)][string]$Name)

    $heartbeat = Get-VMIntegrationService -VMName $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -like "*84EAAE65-2F2E-45F5-9BB5-0E857DC8EB47*" } |
        Select-Object -First 1

    return [bool]($heartbeat -and $heartbeat.PrimaryStatusDescription -eq 'OK')
}

# --- Streaming (Sunshine dans la VM / Moonlight sur l'hote) ----------------

# Premiere adresse IPv4 utilisable de la VM, telle que rapportee par les services
# d'integration Hyper-V (la VM doit donc etre demarree, avec ses services actifs).
# Les adresses de lien-local (169.254.x) sont ecartees : elles apparaissent quand la
# VM n'a pas encore obtenu de bail DHCP et ne sont joignables par rien.
function Get-NovaVmIpAddress {
    param([Parameter(Mandatory)][string]$Name)

    $adapters = Get-VMNetworkAdapter -VMName $Name -ErrorAction SilentlyContinue
    foreach ($adapter in $adapters) {
        foreach ($ip in $adapter.IPAddresses) {
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -and $ip -ne '127.0.0.1' -and $ip -notlike '169.254.*') {
                return $ip
            }
        }
    }
    return $null
}

# Moonlight installe sur l'HOTE (c'est lui le client d'affichage). Chemins usuels du
# paquet officiel ; retourne $null si absent, a l'appelant de le signaler clairement.
function Get-NovaMoonlightPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Moonlight Game Streaming\Moonlight.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Moonlight Game Streaming\Moonlight.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Moonlight Game Streaming\Moonlight.exe")
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    return $null
}

# Debit video conseille, en kbit/s, pour un flux LOCAL (l'hote et la VM sont la meme
# machine : pas de reseau physique a menager). Les valeurs par defaut de Moonlight
# sont calibrees pour du Wi-Fi domestique et laissent enormement de qualite sur la
# table ici. On vise ~0,5 bit par pixel affiche, plafonne pour ne pas noyer le
# decodeur sans gain visible.
function Get-NovaStreamBitrateKbps {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][int]$Fps
    )
    $bitsPerPixel = 0.5
    $kbps = [int]([double]$Width * $Height * $Fps * $bitsPerPixel / 1000)
    return [Math]::Max(20000, [Math]::Min(150000, $kbps))
}

# --- Preferences par VM (GPU-P choisi, resolution/Hz) ----------------------
# Pas d'equivalent Hyper-V simple pour ces reglages : garde en local, cle par
# nom de VM, decouple de l'identite/l'etat reel de la VM (qui vient de Get-VM).

function Get-NovaVmPreferences {
    param([Parameter(Mandatory)][string]$Name)

    $default = [ordered]@{ name = $Name; gpuName = $null; gpuVramMb = 0; resolution = "1920x1080"; hz = 60; osInstalled = $false }
    $mutex = New-Object System.Threading.Mutex($false, "Global\NovaVM_PreferencesStore")
    try {
        [void]$mutex.WaitOne(5000)
        $path = Get-NovaDataStorePath -Name "vm-preferences"
        if (-not (Test-Path $path)) { return [pscustomobject]$default }

        $raw = Get-Content -Path $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$default }

        $all = $raw | ConvertFrom-Json
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i].name -eq $Name) { return $all[$i] }
        }
        return [pscustomobject]$default
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# Ecrit les preferences d'une VM en FUSIONNANT avec ce qui existe deja : seuls les
# parametres reellement passes par l'appelant sont modifies, les autres gardent leur
# valeur enregistree. Sans ca, chaque appelant devrait repasser TOUS les champs sous
# peine d'effacer silencieusement ceux qu'il ne connait pas (par exemple
# Set-NovaVmGpuPartition.ps1 remettrait osInstalled a faux en changeant le GPU).
# Meme lecon que AppSettingsStore cote C#.
function Save-NovaVmPreferences {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$GpuName = $null,
        [int]$GpuVramMb = 0,
        [string]$Resolution = "1920x1080",
        [int]$Hz = 60,
        # "true"/"false" ; non passe = inchange (voir la remarque sur les chaines
        # booleennes dans les autres scripts).
        [string]$OsInstalled = ""
    )
    $mutex = New-Object System.Threading.Mutex($false, "Global\NovaVM_PreferencesStore")
    try {
        [void]$mutex.WaitOne(5000)
        $path = Get-NovaDataStorePath -Name "vm-preferences"

        $all = @()
        if (Test-Path $path) {
            $raw = Get-Content -Path $path -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $all = $raw | ConvertFrom-Json
            }
        }

        $existing = $null
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i].name -eq $Name) { $existing = $all[$i]; break }
        }

        # $PSBoundParameters distingue "valeur par defaut du parametre" de "valeur
        # explicitement fournie par l'appelant" : c'est ce qui permet de fusionner
        # plutot que de remplacer. Chaque champ garde donc sa valeur enregistree
        # tant que l'appelant ne la fournit pas lui-meme.
        $gpuNameValue    = if ($PSBoundParameters.ContainsKey('GpuName'))    { $GpuName }    elseif ($existing) { $existing.gpuName }    else { $null }
        $gpuVramMbValue  = if ($PSBoundParameters.ContainsKey('GpuVramMb'))  { $GpuVramMb }  elseif ($existing) { $existing.gpuVramMb }  else { 0 }
        $resolutionValue = if ($PSBoundParameters.ContainsKey('Resolution')) { $Resolution } elseif ($existing) { $existing.resolution } else { "1920x1080" }
        $hzValue         = if ($PSBoundParameters.ContainsKey('Hz'))         { $Hz }         elseif ($existing) { $existing.hz }         else { 60 }

        $osInstalledValue = if ($OsInstalled -ne "") {
            ($OsInstalled -eq "true")
        } elseif ($existing -and $null -ne $existing.osInstalled) {
            [bool]$existing.osInstalled
        } else {
            $false
        }

        $entry = [ordered]@{
            name        = $Name
            gpuName     = $gpuNameValue
            gpuVramMb   = $gpuVramMbValue
            resolution  = $resolutionValue
            hz          = $hzValue
            osInstalled = $osInstalledValue
        }

        $updated = New-Object System.Collections.ArrayList
        $found = $false
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i].name -eq $Name) {
                [void]$updated.Add($entry)
                $found = $true
            } else {
                [void]$updated.Add($all[$i])
            }
        }
        if (-not $found) { [void]$updated.Add($entry) }

        New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        Set-Content -Path $path -Value (ConvertTo-NovaJsonArray -InputObject $updated) -Encoding UTF8
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

function Remove-NovaVmPreferences {
    param([Parameter(Mandatory)][string]$Name)
    $mutex = New-Object System.Threading.Mutex($false, "Global\NovaVM_PreferencesStore")
    try {
        [void]$mutex.WaitOne(5000)
        $path = Get-NovaDataStorePath -Name "vm-preferences"
        if (-not (Test-Path $path)) { return }
        $raw = Get-Content -Path $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        $all = $raw | ConvertFrom-Json
        $remaining = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i].name -ne $Name) { [void]$remaining.Add($all[$i]) }
        }
        Set-Content -Path $path -Value (ConvertTo-NovaJsonArray -InputObject $remaining) -Encoding UTF8
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# --- Conversion VM reelle -> DTO JSON attendu par la GUI -------------------

function ConvertTo-NovaVmDto {
    param([Parameter(Mandatory)]$Vm)

    $prefs = Get-NovaVmPreferences -Name $Vm.Name

    # "Windows est installe dans cette VM" : le heartbeat Hyper-V ne repond que
    # lorsqu'un systeme a demarre normalement, donc le voir OK une seule fois
    # suffit a le prouver - mais il retombe des que la VM s'eteint. On memorise
    # donc le fait une fois pour toutes (osInstalled dans les preferences), ce
    # qui couvre aussi les VMs installees avant l'existence de ce champ ou
    # importees de l'exterieur : la premiere fois qu'elles demarrent, elles se
    # marquent elles-memes.
    $osInstalled = [bool]$prefs.osInstalled
    if (-not $osInstalled -and $Vm.State -eq 'Running' -and (Test-NovaVmHeartbeatOk -Name $Vm.Name)) {
        $osInstalled = $true
        Save-NovaVmPreferences -Name $Vm.Name -OsInstalled "true"
    }

    $isoPath = $null
    $dvd = Get-VMDvdDrive -VMName $Vm.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dvd -and $dvd.Path) { $isoPath = $dvd.Path }

    # Vrai seulement si le lecteur DVD est a la fois monte ET premier peripherique
    # de demarrage (voir Watch-NovaVmInstallComplete.ps1 : une fois l'installation
    # terminee, le disque dur repasse premier, meme si l'ISO reste montee) - c'est
    # le signal cote GUI (NovaVmService) pour savoir s'il faut simuler un appui
    # clavier dans la fenetre vmconnect apres l'ouverture de la console (voir
    # StartVmAsync). Sans cette distinction, la GUI enverrait des touches dans une
    # session Windows deja installee et utilisee normalement a chaque demarrage.
    $needsBootKeyPress = $false
    if ($dvd -and $dvd.Path) {
        # Le premier element de BootOrder expose ses infos de controleur sur sa
        # propriete .Device (pas directement) - verifie via Get-Member.
        $firstBootDevice = (Get-VMFirmware -VMName $Vm.Name -ErrorAction SilentlyContinue).BootOrder | Select-Object -First 1
        if ($firstBootDevice -and $firstBootDevice.BootType -eq 'Drive' -and $firstBootDevice.Device -and
            $firstBootDevice.Device.ControllerType -eq $dvd.ControllerType -and
            $firstBootDevice.Device.ControllerNumber -eq $dvd.ControllerNumber -and
            $firstBootDevice.Device.ControllerLocation -eq $dvd.ControllerLocation) {
            $needsBootKeyPress = $true
        }
    }

    $diskPath = $null
    $diskSizeGb = 0
    $hardDrive = Get-VMHardDiskDrive -VMName $Vm.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hardDrive) {
        $diskPath = $hardDrive.Path
        try {
            $vhd = Get-VHD -Path $hardDrive.Path -ErrorAction Stop
            $diskSizeGb = [math]::Round([double]$vhd.Size / 1GB, 1)
        } catch {
            # VHD inaccessible (rare) : on garde le chemin, taille a 0.
        }
    }

    [ordered]@{
        id                    = $Vm.Id.ToString()
        name                  = $Vm.Name
        state                 = $Vm.State.ToString()
        cpu                   = $Vm.ProcessorCount
        memoryMb              = [int64]([double]$Vm.MemoryStartup / 1MB)
        dynamicMemoryEnabled  = [bool]$Vm.DynamicMemoryEnabled
        gpuName               = $prefs.gpuName
        gpuVramMb             = $prefs.gpuVramMb
        resolution            = $prefs.resolution
        hz                    = $prefs.hz
        diskPath              = $diskPath
        diskSizeGb            = $diskSizeGb
        isoPath               = $isoPath
        needsBootKeyPress     = $needsBootKeyPress
        osInstalled           = $osInstalled
        lastError             = $null
    }
}

# --- GPU-P : compatibilite et localisation du pilote hote -----------------

# Compare un PNPDeviceID (Win32_VideoController) aux GPU reellement rapportes
# comme partitionnables par Hyper-V (Get-VMHostPartitionableGpu). Les deux
# identifiants different en forme ("PCI\VEN_..\6&xxx" vs "\\?\PCI#VEN_..#6&xxx#{guid}\GPUPARAV")
# mais partagent le meme coeur VEN/DEV/SUBSYS/REV + instance : on normalise et
# on cherche une sous-chaine (comparaison -like, insensible a la casse).
function Test-NovaGpuPartitionable {
    param([string]$PnpDeviceId, $PartitionableGpus)
    if ([string]::IsNullOrWhiteSpace($PnpDeviceId) -or -not $PartitionableGpus) { return $false }
    $normalized = $PnpDeviceId -replace '\\', '#'
    foreach ($gpu in $PartitionableGpus) {
        if ($gpu.Name -like "*$normalized*") { return $true }
    }
    return $false
}

# Localise, pour un nom de GPU donne (ex. "AMD Radeon RX 7900 XTX"), le paquet
# de pilote reellement installe sur l'hote : version, nom d'INF publie/d'origine,
# et surtout le DOSSIER COMPLET dans le magasin de pilotes (DriverStore\FileRepository)
# a copier tel quel (jamais des fichiers individuels pioches a la main : un
# paquet pilote reference ses propres fichiers entre eux par nom exact).
#
# Necessite une elevation (Get-WindowsDriver est un cmdlet DISM) : appele par
# des scripts lances elevés (voir Install-NovaVmGpuDriver.ps1). Volontairement
# pas de repli non-elevé : parser la sortie texte localisee de pnputil s'est
# revele trop fragile (accents/encodage) pour etre fiable.
function Find-NovaHostGpuDriverPackage {
    param([Parameter(Mandatory)][string]$GpuName)

    $signedDriver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceName -eq $GpuName } |
        Select-Object -First 1

    if (-not $signedDriver) {
        throw "Aucun pilote signe trouve pour le peripherique d'affichage '$GpuName' (Win32_PnPSignedDriver)."
    }

    $publishedInf = $signedDriver.InfName

    $dismDriver = Get-WindowsDriver -Online -ErrorAction Stop |
        Where-Object { $_.Driver -eq $publishedInf } |
        Select-Object -First 1

    if (-not $dismDriver -or [string]::IsNullOrWhiteSpace($dismDriver.OriginalFileName)) {
        throw "Get-WindowsDriver -Online n'a pas retrouve le paquet correspondant a '$publishedInf' pour '$GpuName'."
    }

    $infFile = $dismDriver.OriginalFileName
    $folder = Split-Path -Parent $infFile
    if (-not (Test-Path -LiteralPath $folder)) {
        throw "Le dossier de pilote rapporte par DISM est introuvable : $folder"
    }

    $files = Get-ChildItem -Path $folder -Recurse -File

    [ordered]@{
        gpuName       = $GpuName
        driverVersion = $signedDriver.DriverVersion
        providerName  = $dismDriver.ProviderName
        publishedInf  = $publishedInf
        packageFolder = $folder
        infFile       = $infFile
        fileCount     = $files.Count
        sizeBytes     = [int64]($files | Measure-Object -Property Length -Sum).Sum
    }
}

# Win32_VideoController.AdapterRAM est un DWORD 32 bits : il plafonne/deborde
# pour tout GPU au-dela de ~4 Go (constate sur cette machine : rapporte 4 Go
# pour un GPU qui en a reellement 24). La vraie taille se trouve dans le
# registre du pilote d'affichage (HardwareInformation.qwMemorySize, QWORD).
function Get-NovaRealGpuVramBytes {
    param([Parameter(Mandatory)][string]$PnpDeviceId)
    $classKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"

    # -ErrorAction SilentlyContinue (pas Stop) est essentiel ici : certaines
    # sous-cles de cette classe de registre refusent l'acces meme a un
    # administrateur non-eleve (verifie empiriquement), mais ce sont TOUJOURS
    # d'autres sous-cles que celle du GPU visee. Avec -Stop, la toute premiere
    # sous-cle protegee interrompt l'enumeration entiere et on perd la bonne
    # reponse ; avec SilentlyContinue, on saute juste celle-la et on continue.
    $entries = Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue }

    foreach ($entry in $entries) {
        if ($entry.MatchingDeviceId -and $PnpDeviceId -like "*$($entry.MatchingDeviceId)*") {
            $qwSize = $entry.'HardwareInformation.qwMemorySize'
            if ($qwSize) { return [int64]$qwSize }
        }
    }
    return $null
}

Export-ModuleMember -Function `
    ConvertTo-NovaJsonArray, `
    Write-NovaResult, `
    Write-NovaProgress, `
    Invoke-NovaAction, `
    Get-NovaDataStorePath, `
    Get-NovaHostMemoryInfo, `
    Close-NovaMountedVolumeExplorerWindow, `
    Test-NovaVmHeartbeatOk, `
    Get-NovaVmIpAddress, `
    Get-NovaMoonlightPath, `
    Get-NovaStreamBitrateKbps, `
    Get-NovaVmPreferences, `
    Save-NovaVmPreferences, `
    Remove-NovaVmPreferences, `
    Test-NovaGpuPartitionable, `
    Find-NovaHostGpuDriverPackage, `
    Get-NovaRealGpuVramBytes, `
    ConvertTo-NovaVmDto
