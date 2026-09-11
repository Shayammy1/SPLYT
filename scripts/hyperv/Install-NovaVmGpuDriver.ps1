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
        # Methode : on demande a Windows la LISTE REELLE des fichiers du pilote
        # (Win32_PNPSignedDriverCIMDataFile), c'est-a-dire exactement ce
        # qu'affiche le Gestionnaire de peripheriques sous "Details des fichiers
        # du pilote", puis on recopie chaque fichier au MEME chemin dans l'invite.
        #
        # La version precedente devinait cette liste : elle prenait les NOMS des
        # fichiers du paquet et cherchait un homonyme dans System32 et
        # System32\drivers. Deux trous, corriges ici :
        #   - SysWOW64 n'etait jamais copie, donc les DLL 32 bits du pilote
        #     (amdxc32.dll, nvapi.dll...) manquaient : pas d'acceleration pour ce
        #     qui tourne en 32 bits dans la VM ;
        #   - tout fichier range ailleurs etait ignore, typiquement
        #     System32\drivers\Nvidia Corporation\.
        # Et un fichier System32 sans rapport portant le meme nom qu'un fichier du
        # paquet pouvait etre ecrase. Partir de la liste officielle supprime
        # l'heuristique et ses trois defauts d'un coup.
        Write-NovaProgress "Copie des fichiers de pilote hors magasin (System32, SysWOW64...)"

        # Get-WmiObject et non Get-CimInstance, a dessein : en CIM, Antecedent et
        # Dependent sont des OBJETS (leur texte vaut "CIM_DataFile (Name = ...)"),
        # la comparaison ci-dessous ne trouve alors jamais rien - et
        # Get-CimAssociatedInstance sur cette association ne renvoie rien non plus
        # (les deux verifies ici : 0 fichier). L'ancienne API rend bien des chaines.
        #
        # La reference se construit a la main, avec les antislashs du DeviceID
        # doubles : \\NOM-MACHINE\ROOT\cimv2:Win32_PnPSignedDriver.DeviceID="PCI\\VEN_..."
        $escapedDeviceId = $realGpu.PNPDeviceID -replace '\\', '\\'
        $antecedent = "\\" + $env:COMPUTERNAME + "\ROOT\cimv2:Win32_PnPSignedDriver.DeviceID=`"$escapedDeviceId`""
        $driverFiles = @(Get-WmiObject Win32_PNPSignedDriverCIMDataFile -ErrorAction SilentlyContinue |
            Where-Object { $_.Antecedent -eq $antecedent })

        $looseFilesCopied = 0
        $looseFilesSkipped = 0
        foreach ($entry in $driverFiles) {
            # Dependent se presente sous la forme
            # \\MACHINE\ROOT\cimv2:CIM_DataFile.Name="c:\\windows\\system32\\amdxc64.dll"
            # On en extrait le chemin, entre guillemets, et on le denormalise.
            $dependent = [string]$entry.Dependent
            $match = [regex]::Match($dependent, 'Name="(.+)"')
            if (-not $match.Success) { continue }
            $hostPath = $match.Groups[1].Value -replace '\\\\', '\'
            if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { continue }

            # Ce qui est dans le magasin de pilotes est deja couvert par la copie
            # complete de l'etape 1, vers HostDriverStore.
            if ($hostPath -like "$env:SystemRoot\System32\DriverStore\*") {
                $looseFilesSkipped++
                continue
            }

            # Meme chemin relatif dans l'invite que sur l'hote.
            #
            # [IO.Path]::Combine et non Join-Path : ce dernier VALIDE le lecteur
            # aupres de PowerShell et echoue sur une lettre qu'il ne connait pas,
            # ce qui est exactement le cas d'un volume de VM monte en cours de
            # route. Ici on assemble du texte, on ne resout rien.
            if (-not $hostPath.StartsWith("$env:SystemDrive\", [StringComparison]::OrdinalIgnoreCase)) { continue }
            $relativePath = $hostPath.Substring("$env:SystemDrive\".Length)
            $guestPath = [System.IO.Path]::Combine($volumeRoot, $relativePath)
            $guestFolder = [System.IO.Path]::GetDirectoryName($guestPath)

            # Best-effort par fichier : un seul fichier verrouille ou refuse ne doit
            # pas faire echouer toute la preparation. -Force ecrase la version
            # precedente, ce qui est exactement ce qu'il faut apres une mise a jour
            # du pilote de l'hote.
            try {
                if (-not (Test-Path -LiteralPath $guestFolder)) {
                    New-Item -ItemType Directory -Path $guestFolder -Force | Out-Null
                }
                Copy-Item -LiteralPath $hostPath -Destination $guestPath -Force -ErrorAction Stop
                $looseFilesCopied++
            } catch { }
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

        # --- Etape 4 : concordance des versions de Windows hote/invite --------
        #
        # Le pilote paravirtualise est celui de l'hote, execute dans l'invite : les
        # deux Windows doivent etre de la meme version. Un ecart provoque des
        # incompatibilites, voire des ecrans bleus dans la VM - c'est un prerequis
        # que les implementations de reference posent noir sur blanc. On ne bloque
        # pas pour autant : on le signale, parce qu'un ecart mineur passe souvent.
        $guestBuild = $null
        $softwareHive = Join-Path $volumeRoot "Windows\System32\config\SOFTWARE"
        if (Test-Path -LiteralPath $softwareHive) {
            $softwareLoaded = $false
            try {
                & reg.exe load "HKLM\NovaVmOfflineSoftware" $softwareHive 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $softwareLoaded = $true
                    $guestCurrent = Get-ItemProperty "HKLM:\NovaVmOfflineSoftware\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
                    if ($guestCurrent) {
                        $guestBuild = "$($guestCurrent.CurrentBuild).$($guestCurrent.UBR)"
                    }
                }
            } catch {
            } finally {
                if ($softwareLoaded) { & reg.exe unload "HKLM\NovaVmOfflineSoftware" 2>&1 | Out-Null }
            }
        }

        $hostCurrent = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
        $hostBuild = if ($hostCurrent) { "$($hostCurrent.CurrentBuild).$($hostCurrent.UBR)" } else { $null }
        # Seul le numero de build majeur compte vraiment ; la revision (UBR) bouge a
        # chaque mise a jour mensuelle et differer dessus n'a jamais pose probleme.
        $buildsMatch = $true
        if ($guestBuild -and $hostBuild) {
            $buildsMatch = ($guestBuild.Split('.')[0] -eq $hostBuild.Split('.')[0])
        }

        # Version du pilote hote retenue : c'est elle qui servira a detecter la
        # derive quand l'hote mettra son pilote a jour (voir le diagnostic GPU).
        Save-NovaVmPreferences -Name $Name -GpuDriverVersion $driverInfo.driverVersion

        $buildWarning = if (-not $buildsMatch) {
            " ATTENTION : l'hote est en build Windows $hostBuild et la VM en $guestBuild. Le pilote paravirtualise est celui de l'hote : un ecart de version de Windows peut provoquer des instabilites, voire des ecrans bleus dans la VM. Mettez les deux au meme niveau."
        } else { "" }

        $result = [ordered]@{
            gpuName            = $gpuName
            driverVersion      = $driverInfo.driverVersion
            providerName       = $driverInfo.providerName
            registryIndex      = $registryIndex
            hostDriverStorePath = $destRepo
            system32FilesCopied = $looseFilesCopied
            driverStoreFilesSkipped = $looseFilesSkipped
            hostWindowsBuild   = $hostBuild
            guestWindowsBuild  = $guestBuild
            windowsBuildsMatch = $buildsMatch
            pnpAlreadyPresent  = [bool]$alreadyPresent
            pnpInstalledDriver = $pnpInstalled
            message            = "HostDriverStore synchronise (magasin complet), $looseFilesCopied fichier(s) de pilote copie(s) hors magasin (System32, SysWOW64...), configuration registre copiee (classe $registryIndex), enregistrement Plug-and-Play " + $(if ($alreadyPresent) { "deja a jour" } else { "effectue ($pnpInstalled)" }) + ". Redemarrez la VM pour verifier dans le Gestionnaire de peripheriques." + $buildWarning
        }
        Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
    } finally {
        if ($hiveLoaded) { & reg.exe unload "HKLM\NovaVmOfflineSystem" 2>&1 | Out-Null }
        Write-NovaProgress "Demontage du disque"
        Dismount-VHD -Path $hardDrive.Path -ErrorAction SilentlyContinue
    }
}
