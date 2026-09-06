<#
.SYNOPSIS
    Cree une VRAIE VM Hyper-V (Generation 2, UEFI), avec disque VHDX et ISO de
    demarrage optionnelle. Emet une ligne de progression (Write-NovaProgress)
    avant chaque etape reelle, pour alimenter une barre de progression cote GUI.

    Si une etape echoue APRES que la VM ait ete creee (New-VM), la VM partielle
    est automatiquement supprimee avant de remonter l'erreur : sans ca, un echec
    intermittent (ex. New-VHD qui echoue parfois sous charge) laisse une "VM
    fantome" sans disque qui bloque ensuite toute recreation sous le meme nom.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [int]$Cpu = 2,
    [long]$MemoryMb = 4096,
    [int]$DiskSizeGb = 64,
    [string]$GpuName = "",
    [int]$GpuVramMb = 0,
    [string]$IsoPath = "",
    # "true"/"false" (jamais [bool] directement : PowerShell ne convertit pas
    # une chaine "true"/"false" recue en ligne de commande - voir tous les
    # autres scripts de ce dossier). Statique par defaut : la RAM configuree
    # dans SPLYT reste toujours entierement assignee a la VM, sans surprise.
    [string]$DynamicMemoryEnabled = "false"
)

$dynamicMemoryBool = $DynamicMemoryEnabled -eq "true"

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

function New-NovaVhdWithRetry {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int64]$SizeBytes)
    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            New-VHD -Path $Path -SizeBytes $SizeBytes -Dynamic -ErrorAction Stop | Out-Null
            return
        } catch {
            $lastError = $_
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
        }
    }
    throw $lastError
}

Invoke-NovaAction {
    Write-NovaProgress "Validation des parametres"

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Le nom de la VM est obligatoire."
    }
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        throw "Une VM nommee '$Name' existe deja."
    }
    if (-not [string]::IsNullOrWhiteSpace($IsoPath) -and -not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        throw "Le fichier ISO est introuvable : $IsoPath"
    }
    $hostMemory = Get-NovaHostMemoryInfo
    if ($MemoryMb -gt $hostMemory.maxVmMemoryMb) {
        throw "La RAM demandee ($MemoryMb Mo) depasse la limite raisonnable pour cet ordinateur ($($hostMemory.maxVmMemoryMb) Mo, sur $($hostMemory.totalPhysicalMb) Mo physiques)."
    }

    Write-NovaProgress "Creation de la VM"
    New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryMb * 1MB) -NoVHD -ErrorAction Stop | Out-Null

    # A partir d'ici, la VM existe : toute erreur doit la nettoyer avant de
    # remonter, pour ne jamais laisser de VM incomplete bloquer ce nom.
    try {
        # Secure Boot reste active (defaut Hyper-V, modele MicrosoftWindows) et un
        # TPM virtuel local est ajoute : Windows 11 exige les deux (TPM 2.0 +
        # Secure Boot) au moment de l'installation, sinon Setup refuse de continuer
        # avec "Le PC doit prendre en charge TPM 2.0". -NewLocalKeyProtector ne
        # necessite pas de Host Guardian Service : fonctionne sur un hote autonome.
        Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector -ErrorAction Stop
        Enable-VMTPM -VMName $Name -ErrorAction Stop

        Write-NovaProgress "Creation du disque virtuel"
        $diskDir = "C:\NovaVM\Disks"
        New-Item -ItemType Directory -Path $diskDir -Force | Out-Null
        $vhdPath = Join-Path $diskDir "$Name.vhdx"
        New-NovaVhdWithRetry -Path $vhdPath -SizeBytes ([int64]$DiskSizeGb * 1GB)
        Add-VMHardDiskDrive -VMName $Name -Path $vhdPath -ErrorAction Stop

        Write-NovaProgress "Montage de l'image ISO"
        $dvd = $null
        if (-not [string]::IsNullOrWhiteSpace($IsoPath)) {
            $dvd = Add-VMDvdDrive -VMName $Name -Path $IsoPath -Passthru -ErrorAction Stop
        }

        Write-NovaProgress "Configuration du processeur et de la memoire"
        Set-VMProcessor -VMName $Name -Count $Cpu -ErrorAction Stop

        # New-VM active en realite la memoire DYNAMIQUE par defaut (verifie
        # empiriquement : DynamicMemoryEnabled=True, MaximumBytes=1 To) - il faut
        # donc toujours repasser explicitement Set-VMMemory dans les DEUX cas, pas
        # seulement quand la memoire dynamique est demandee, sinon "statique par
        # defaut" restait dynamique en pratique (Set-VMMemory ne touche que les
        # parametres fournis, meme raison que Set-NovaVmResources.ps1). Si la
        # memoire dynamique est demandee, le plafond (MaximumBytes) est
        # volontairement egal a la RAM configuree (pas de valeur enorme par defaut
        # type 1 To) : "X Go" dans SPLYT reste le maximum reel, la VM peut
        # simplement en utiliser moins au repos.
        if ($dynamicMemoryBool) {
            $minimumBytes = [Math]::Min(512MB, $MemoryMb * 1MB)
            Set-VMMemory -VMName $Name -DynamicMemoryEnabled $true `
                -MinimumBytes $minimumBytes -StartupBytes ($MemoryMb * 1MB) -MaximumBytes ($MemoryMb * 1MB) `
                -ErrorAction Stop
        } else {
            Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false -StartupBytes ($MemoryMb * 1MB) -ErrorAction Stop
        }

        # Sans commutateur virtuel, la carte reseau n'a aucun chemin reseau : Windows
        # Setup ne peut pas se connecter a internet (et rapporte parfois ca comme un
        # probleme de pilote). "Default Switch" fournit un acces internet via NAT
        # sans configuration hote supplementaire ; a defaut, on prend le premier
        # commutateur disponible. Best-effort : l'absence de reseau ne doit pas
        # empecher la creation de la VM (utilisable hors-ligne quand meme).
        $switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
        if (-not $switch) { $switch = Get-VMSwitch | Select-Object -First 1 }
        if ($switch) {
            Get-VMNetworkAdapter -VMName $Name | Connect-VMNetworkAdapter -VMSwitch $switch -ErrorAction SilentlyContinue
        }

        Write-NovaProgress "Configuration du demarrage"
        if ($dvd) {
            Set-VMFirmware -VMName $Name -FirstBootDevice $dvd -ErrorAction Stop
        }

        Write-NovaProgress "Finalisation"
        $gpu = if ([string]::IsNullOrWhiteSpace($GpuName)) { $null } else { $GpuName }
        Save-NovaVmPreferences -Name $Name -GpuName $gpu -GpuVramMb $(if ($gpu) { $GpuVramMb } else { 0 }) `
            -Resolution "1920x1080" -Hz 60
    } catch {
        Remove-VM -Name $Name -Force -ErrorAction SilentlyContinue
        if ($vhdPath -and (Test-Path -LiteralPath $vhdPath)) {
            Remove-Item -LiteralPath $vhdPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
