<#
.SYNOPSIS
    Configure un VRAI adaptateur GPU-P sur une VM Hyper-V (pas une simple
    preference locale) : supprime tout adaptateur existant, en ajoute un
    nouveau, applique les valeurs de partition et les reglages MMIO requis,
    puis verifie avec Get-VMGpuPartitionAdapter que la partition est bien
    attachee. N'affirme jamais un succes sans cette verification reelle.

    La VM doit etre eteinte (Add/Remove/Set-VMGpuPartitionAdapter et les
    reglages MMIO ne peuvent pas s'appliquer a chaud).
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$GpuName = "",
    [int]$GpuVramMb = 0
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop

    # --- Retrait du GPU-P : GpuName vide = "Aucun" ------------------------
    if ([string]::IsNullOrWhiteSpace($GpuName)) {
        Remove-VMGpuPartitionAdapter -VMName $Name -ErrorAction SilentlyContinue
        $prefs = Get-NovaVmPreferences -Name $Name
        Save-NovaVmPreferences -Name $Name -GpuName $null -GpuVramMb 0 -Resolution $prefs.resolution -Hz $prefs.hz
        $updated = Get-VM -Name $Name
        Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $updated | ConvertTo-Json -Depth 8 -Compress)
        return
    }

    if ($vm.State -ne 'Off') {
        throw "La VM doit etre arretee pour configurer le GPU-P (Add/Remove/Set-VMGpuPartitionAdapter ne s'appliquent pas a chaud)."
    }

    $realGpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -eq $GpuName } | Select-Object -First 1
    if (-not $realGpu) {
        throw "GPU '$GpuName' introuvable sur cet hote (Win32_VideoController)."
    }

    $partitionableGpus = Get-VMHostPartitionableGpu -ErrorAction Stop
    if (-not (Test-NovaGpuPartitionable -PnpDeviceId $realGpu.PNPDeviceID -PartitionableGpus $partitionableGpus)) {
        throw "'$GpuName' n'est pas rapporte comme partitionnable par Hyper-V (Get-VMHostPartitionableGpu). GPU-P impossible avec ce materiel/pilote."
    }

    # --- Proportion VRAM demandee / VRAM reelle du GPU ---------------------
    # Set-VMGpuPartitionAdapter utilise une echelle abstraite sur 1 milliard
    # (voir TotalVRAM de Get-VMHostPartitionableGpu), pas des Mo litteraux :
    # on calcule donc une proportion a partir de la VRAM REELLE du GPU (pas
    # Win32_VideoController.AdapterRAM, qui plafonne a ~4 Go pour tout GPU
    # au-dela : voir Get-NovaRealGpuVramBytes) et on l'applique a l'echelle.
    $realVramBytes = Get-NovaRealGpuVramBytes -PnpDeviceId $realGpu.PNPDeviceID
    $requestedBytes = [int64]$GpuVramMb * 1MB
    $scale = 1000000000
    if ($realVramBytes -and $realVramBytes -gt 0) {
        $fraction = [math]::Min(1.0, $requestedBytes / $realVramBytes)
    } else {
        $fraction = 0.5 # VRAM reelle non determinee : 50% par defaut, prudent.
    }
    $partitionValue = [int64]([math]::Max(1, [math]::Round($scale * $fraction)))

    # --- Remplacement propre de tout adaptateur existant --------------------
    Remove-VMGpuPartitionAdapter -VMName $Name -ErrorAction SilentlyContinue
    Add-VMGpuPartitionAdapter -VMName $Name -ErrorAction Stop

    Set-VMGpuPartitionAdapter -VMName $Name `
        -MinPartitionVRAM 1 -MaxPartitionVRAM $partitionValue -OptimalPartitionVRAM $partitionValue `
        -MinPartitionEncode 1 -MaxPartitionEncode $partitionValue -OptimalPartitionEncode $partitionValue `
        -MinPartitionDecode 1 -MaxPartitionDecode $partitionValue -OptimalPartitionDecode $partitionValue `
        -MinPartitionCompute 1 -MaxPartitionCompute $partitionValue -OptimalPartitionCompute $partitionValue `
        -ErrorAction Stop

    # Reglages requis par Microsoft pour GPU-P : sans un espace MMIO suffisant,
    # l'adaptateur peut s'attacher mais le GPU apparait en erreur (triangle orange,
    # type Code 43) cote invite plutot que de fonctionner. LowMemoryMappedIoSpace a
    # 1GB (pas les 3GB de l'exemple officiel Microsoft) : confirme empiriquement par
    # un utilisateur sur un GPU integre AMD (Radeon 8060S) - avec 3GB, le triangle
    # orange restait present ; passe a 1GB, le GPU-P fonctionne. La fenetre "low"
    # (sous 4 Go) est une ressource contrainte que se partagent tous les
    # peripheriques de la VM ; les gros BARs d'un GPU vivent de toute facon dans la
    # fenetre "high" (au-dessus de 4 Go) juste en dessous - une demande "low" plus
    # petite laisse plus de marge sans rien retirer a ce qui compte vraiment.
    Set-VM -VMName $Name -GuestControlledCacheTypes $true -ErrorAction Stop
    Set-VM -VMName $Name -LowMemoryMappedIoSpace 1GB -ErrorAction Stop
    Set-VM -VMName $Name -HighMemoryMappedIoSpace 32GB -ErrorAction Stop

    # Points de controle automatiques : actives par defaut par Hyper-V cote client
    # (verifie sur cette machine - un fichier .avhdx apparaissait des le premier
    # demarrage). Hyper-V refuse de capturer une VM porteuse d'un adaptateur GPU-P,
    # et faire tourner la VM depuis un disque de differenciation fausse en plus la
    # preparation hors-ligne du pilote (Install-NovaVmGpuDriver.ps1 monte le disque
    # attache, qui serait alors le .avhdx et non le disque de base). De meme,
    # "sauvegarder l'etat" a l'arret de l'hote est incompatible avec un GPU
    # partitionne : on bascule sur un arret franc.
    Set-VM -VMName $Name -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
    Set-VM -VMName $Name -CheckpointType Disabled -ErrorAction SilentlyContinue
    Set-VM -VMName $Name -AutomaticStopAction TurnOff -ErrorAction SilentlyContinue

    # --- Verification reelle : ne jamais affirmer un succes sans ca ---------
    $attached = Get-VMGpuPartitionAdapter -VMName $Name -ErrorAction Stop | Select-Object -First 1
    if (-not $attached) {
        throw "L'adaptateur GPU-P a ete ajoute mais Get-VMGpuPartitionAdapter ne le retrouve pas apres coup : configuration incoherente."
    }

    $prefs = Get-NovaVmPreferences -Name $Name
    Save-NovaVmPreferences -Name $Name -GpuName $GpuName -GpuVramMb $GpuVramMb -Resolution $prefs.resolution -Hz $prefs.hz

    $updated = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $updated | ConvertTo-Json -Depth 8 -Compress)
}
