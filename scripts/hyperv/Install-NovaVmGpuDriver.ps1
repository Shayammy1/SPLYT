<#
.SYNOPSIS
    Prepare le GPU-P pour qu'il fonctionne reellement dans l'invite, en suivant
    la procedure officielle Microsoft ("GPU paravirtualization - Windows
    drivers", learn.microsoft.com/windows-hardware/drivers/display/gpu-paravirtualization) :

    1. Copie la TOTALITE du magasin de pilotes hote (System32\DriverStore) vers
       System32\HostDriverStore dans le disque de la VM. Le pilote UMD paravirtualise
       resout ses DLL via ce chemin precis (traduction documentee par Microsoft :
       System32\DriverStore\... sur l'hote -> System32\HostDriverStore\... dans la VM).
       Copier TOUT le magasin (pas seulement le paquet du GPU vise) est la methode
       documentee par Microsoft elle-meme (script officiel `xcopy /s ... driverstore\* ... hostdriverstore\`) :
       les paquets ne se "melangent" pas puisqu'il s'agit du meme instantane coherent
       du magasin de pilotes de CET hote, juste copie integralement.
    2. Copie la cle de registre de la classe d'affichage du GPU hote
       (HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-...}\<index>) dans le
       registre SYSTEM hors-ligne de la VM : sans elle, le pilote installe cote VM
       n'a pas les memes valeurs de configuration que celui de l'hote (cause
       frequente du symbole d'avertissement/Code 43 dans le Gestionnaire de
       peripheriques malgre un pilote "installe").
    3. Enregistre aussi le pilote via DISM (Add-WindowsDriver) pour le Plug-and-Play
       normal (associe le bon INF au GPU-P au demarrage).

    Necessite une elevation (DISM l'exige). La VM doit etre eteinte (montage
    hors-ligne de son VHDX + de son registre SYSTEM).
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Off') {
        throw "La VM doit etre arretee pour preparer le GPU-P hors-ligne."
    }

    $prefs = Get-NovaVmPreferences -Name $Name
    $gpuName = $prefs.gpuName
    if ([string]::IsNullOrWhiteSpace($gpuName)) {
        throw "Aucun GPU-P n'est configure pour cette VM. Configurez d'abord le GPU-P avant de preparer son pilote."
    }

    Write-NovaProgress "Recherche du pilote et du GPU hote"
    $driverInfo = Find-NovaHostGpuDriverPackage -GpuName $gpuName

    $realGpu = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -eq $gpuName } | Select-Object -First 1
    if (-not $realGpu) { throw "GPU '$gpuName' introuvable sur cet hote (Win32_VideoController)." }

    # Boucle foreach classique (pas ForEach-Object) : une scriptblock de pipeline
    # a sa propre portee, une simple affectation dedans ne remonte pas au-dessus
    # (piege verifie empiriquement) - foreach classique partage la portee englobante.
    $classKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $registryIndex = $null
    $classEntries = Get-ChildItem -Path $classKeyPath -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue }
    foreach ($entry in $classEntries) {
        if ($entry.MatchingDeviceId -and $realGpu.PNPDeviceID -like "*$($entry.MatchingDeviceId)*") {
            $registryIndex = $entry.PSChildName
            break
        }
    }
    if (-not $registryIndex) {
        throw "Impossible de trouver l'index de registre de la classe d'affichage pour '$gpuName' (sous $classKeyPath)."
    }

    $hardDrive = Get-VMHardDiskDrive -VMName $Name -ErrorAction Stop | Select-Object -First 1
    if (-not $hardDrive) { throw "Aucun disque dur trouve pour cette VM." }

    Write-NovaProgress "Montage du disque de la VM"
    Mount-VHD -Path $hardDrive.Path -ErrorAction Stop | Out-Null
    $hiveLoaded = $false
    try {
        $partition = Get-VHD -Path $hardDrive.Path -ErrorAction Stop |
            Get-Disk | Get-Partition | Where-Object { $_.DriveLetter } | Select-Object -First 1
        if (-not $partition) {
            throw "Aucune partition Windows (avec lettre de lecteur) trouvee sur le disque de la VM une fois monte."
        }
        $volumeRoot = "$($partition.DriveLetter):\"

        # Windows ouvre une fenetre d'Explorateur au premier plan des que le
        # volume apparait, en plein milieu de l'operation : on la referme.
        Close-NovaMountedVolumeExplorerWindow -DriveLetter $partition.DriveLetter

        # --- Etape 1 : copie complete du magasin de pilotes vers HostDriverStore ---
        Write-NovaProgress "Copie du magasin de pilotes complet (environ 2 a 3 Go, peut prendre plusieurs minutes)"
        $sourceRepo = "$env:SystemRoot\System32\DriverStore\FileRepository"
        $destRepo = Join-Path $volumeRoot "Windows\System32\HostDriverStore\FileRepository"
        New-Item -ItemType Directory -Path $destRepo -Force | Out-Null

        $robocopyArgs = @($sourceRepo, $destRepo, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS", "/NP", "/R:1", "/W:1")
        & robocopy.exe @robocopyArgs | Out-Null
        # Robocopy : codes de sortie 0-7 = succes (voir sa documentation), 8+ = echec reel.
        if ($LASTEXITCODE -ge 8) {
            throw "La copie du magasin de pilotes (robocopy) a echoue avec le code $LASTEXITCODE."
        }

        # --- Etape 1bis : fichiers "en vrac" du pilote dans System32 -----------
        # Le magasin de pilotes ne suffit pas : l'INF d'un pilote graphique
        # installe aussi une serie de DLL directement dans System32 (et
        # System32\drivers) - cote AMD amdxc64.dll/atiumd64.dll, cote NVIDIA
        # nvapi64.dll, etc. Sans elles dans l'invite, le pilote paravirtualise
        # ne peut pas se charger et le GPU n'apparait PAS DU TOUT dans le
        # Gestionnaire de peripheriques (pas meme en peripherique inconnu :
        # l'adaptateur GPU-P n'est pas un peripherique PCI, il n'existe cote
        # invite que si son pilote se charge). C'est l'etape que la
        # documentation Microsoft passe sous silence mais que toutes les
        # implementations qui fonctionnent reellement effectuent.
        #
        # Methode : pour chaque fichier du paquet de pilote hote, s'il existe
        # aussi un fichier de meme nom dans System32 (ou System32\drivers) de
        # l'hote, c'est que l'INF l'y a installe - on le copie au meme endroit
        # dans l'invite.
        Write-NovaProgress "Copie des fichiers de pilote de System32"
        $hostSystem32 = Join-Path $env:SystemRoot "System32"
        $guestSystem32 = Join-Path $volumeRoot "Windows\System32"
        $guestDrivers = Join-Path $guestSystem32 "drivers"
        New-Item -ItemType Directory -Path $guestDrivers -Force | Out-Null

        $looseFilesCopied = 0
        $packageFileNames = Get-ChildItem -Path $driverInfo.packageFolder -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name -Unique
        foreach ($fileName in $packageFileNames) {
            foreach ($pair in @(
                @{ Source = Join-Path $hostSystem32 $fileName;             Dest = $guestSystem32 },
                @{ Source = Join-Path $hostSystem32 "drivers\$fileName";   Dest = $guestDrivers }
            )) {
                if (Test-Path -LiteralPath $pair.Source -PathType Leaf) {
                    # -Force : ecrase une version precedente (mise a jour du pilote
                    # hote). Best-effort par fichier : un seul fichier verrouille ou
                    # refuse ne doit pas faire echouer toute la preparation.
                    try {
                        Copy-Item -LiteralPath $pair.Source -Destination $pair.Dest -Force -ErrorAction Stop
                        $looseFilesCopied++
                    } catch { }
                }
            }
        }

        # --- Etape 2 : copie de la cle de registre de la classe d'affichage ---
        Write-NovaProgress "Copie de la configuration registre du pilote"
        $systemHivePath = Join-Path $volumeRoot "Windows\System32\config\SYSTEM"
        $loadResult = & reg.exe load "HKLM\NovaVmOfflineSystem" $systemHivePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de charger le registre SYSTEM hors-ligne de la VM : $loadResult"
        }
        $hiveLoaded = $true

        $currentCcs = (Get-ItemProperty "HKLM:\NovaVmOfflineSystem\Select" -Name Current -ErrorAction Stop).Current
        $ccsName = "ControlSet{0:D3}" -f $currentCcs
        $destKeyPath = "HKLM\NovaVmOfflineSystem\$ccsName\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\$registryIndex"

        $copyResult = & reg.exe copy "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\$registryIndex" $destKeyPath /s /f 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible de copier la cle de registre du pilote dans la VM : $copyResult"
        }

        & reg.exe unload "HKLM\NovaVmOfflineSystem" 2>&1 | Out-Null
        $hiveLoaded = $false

        # --- Etape 3 : enregistrement Plug-and-Play normal (DISM) ---
        Write-NovaProgress "Verification du pilote deja enregistre (PnP)"
        $existingDrivers = Get-WindowsDriver -Path $volumeRoot -ErrorAction Stop
        $alreadyPresent = $existingDrivers | Where-Object {
            $_.ClassName -eq 'Display' -and $_.ProviderName -eq $driverInfo.providerName -and $_.Version -eq $driverInfo.driverVersion
        } | Select-Object -First 1

        $pnpInstalled = $null
        if (-not $alreadyPresent) {
            Write-NovaProgress "Enregistrement Plug-and-Play du pilote (DISM)"
            $addResult = Add-WindowsDriver -Path $volumeRoot -Driver $driverInfo.infFile -ErrorAction Stop
            $pnpInstalled = $addResult.Driver
        }

        $result = [ordered]@{
            gpuName            = $gpuName
            driverVersion      = $driverInfo.driverVersion
            providerName       = $driverInfo.providerName
            registryIndex      = $registryIndex
            hostDriverStorePath = $destRepo
            system32FilesCopied = $looseFilesCopied
            pnpAlreadyPresent  = [bool]$alreadyPresent
            pnpInstalledDriver = $pnpInstalled
            message            = "HostDriverStore synchronise (magasin complet), $looseFilesCopied fichier(s) de pilote copie(s) dans System32, configuration registre copiee (classe $registryIndex), enregistrement Plug-and-Play " + $(if ($alreadyPresent) { "deja a jour" } else { "effectue ($pnpInstalled)" }) + ". Redemarrez la VM pour verifier dans le Gestionnaire de peripheriques."
        }
        Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
    } finally {
        if ($hiveLoaded) { & reg.exe unload "HKLM\NovaVmOfflineSystem" 2>&1 | Out-Null }
        Write-NovaProgress "Demontage du disque"
        Dismount-VHD -Path $hardDrive.Path -ErrorAction SilentlyContinue
    }
}
