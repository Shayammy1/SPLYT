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

    [ordered]@{
        totalPhysicalMb = [int64]$totalMb
        maxVmMemoryMb   = [int64]$maxVmMemoryMb
    }
}

# --- Preferences par VM (GPU-P choisi, resolution/Hz) ----------------------
# Pas d'equivalent Hyper-V simple pour ces reglages : garde en local, cle par
# nom de VM, decouple de l'identite/l'etat reel de la VM (qui vient de Get-VM).

function Get-NovaVmPreferences {
    param([Parameter(Mandatory)][string]$Name)

    $default = [ordered]@{ name = $Name; gpuName = $null; gpuVramMb = 0; resolution = "1920x1080"; hz = 60 }
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

function Save-NovaVmPreferences {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$GpuName = $null,
        [int]$GpuVramMb = 0,
        [string]$Resolution = "1920x1080",
        [int]$Hz = 60
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

        $entry = [ordered]@{
            name = $Name; gpuName = $GpuName; gpuVramMb = $GpuVramMb
            resolution = $Resolution; hz = $Hz
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

    $isoPath = $null
    $dvd = Get-VMDvdDrive -VMName $Vm.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dvd -and $dvd.Path) { $isoPath = $dvd.Path }

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
    Get-NovaVmPreferences, `
    Save-NovaVmPreferences, `
    Remove-NovaVmPreferences, `
    Test-NovaGpuPartitionable, `
    Find-NovaHostGpuDriverPackage, `
    Get-NovaRealGpuVramBytes, `
    ConvertTo-NovaVmDto
