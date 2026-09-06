<#
.SYNOPSIS
    Diagnostic GPU-P complet et honnete pour une VM : compatibilite du GPU
    hote, presence reelle d'un adaptateur GPU-P attache a la VM, et etat de la
    partition. N'affirme jamais qu'un GPU-P fonctionne sans verification reelle
    (Get-VMHostPartitionableGpu / Get-VMGpuPartitionAdapter) ; remonte les
    messages d'erreur PowerShell/Hyper-V tels quels.

    Ne verifie PAS le pilote a l'interieur de l'invite ici : cette verification
    utilise DISM (Get-WindowsDriver), qui necessite une elevation. Elle est
    faite par Install-NovaVmGpuDriver.ps1 (lance elevé), qui rapporte aussi si
    le pilote est deja a jour sans rien modifier.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop

    $generationOk = ($vm.Generation -eq 2)

    $realGpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'Basic Render|Remote Desktop' } |
        Select-Object -First 1

    $partitionableGpus = $null
    $hostGpuError = $null
    try {
        $partitionableGpus = Get-VMHostPartitionableGpu -ErrorAction Stop
    } catch {
        $hostGpuError = $_.Exception.Message
    }
    $hostGpuCompatible = [bool]($partitionableGpus -and $partitionableGpus.Count -gt 0)

    $isHostGpuActuallyPartitionable = $false
    if ($realGpu -and $partitionableGpus) {
        $isHostGpuActuallyPartitionable = Test-NovaGpuPartitionable -PnpDeviceId $realGpu.PNPDeviceID -PartitionableGpus $partitionableGpus
    }

    $adapter = $null
    $adapterError = $null
    try {
        $adapter = Get-VMGpuPartitionAdapter -VMName $Name -ErrorAction Stop | Select-Object -First 1
    } catch {
        $adapterError = $_.Exception.Message
    }
    $adapterAttached = [bool]$adapter

    $issues = New-Object System.Collections.ArrayList
    if (-not $generationOk) {
        [void]$issues.Add("La VM est en Generation $($vm.Generation) : GPU-P necessite une VM Generation 2.")
    }
    if (-not $hostGpuCompatible) {
        $msg = "Aucun GPU partitionnable rapporte par Hyper-V sur cet hote (Get-VMHostPartitionableGpu)."
        if ($hostGpuError) { $msg += " Erreur : $hostGpuError" }
        [void]$issues.Add($msg)
    } elseif (-not $isHostGpuActuallyPartitionable) {
        [void]$issues.Add("Le GPU detecte ('$($realGpu.Name)') ne correspond a aucun des GPU rapportes partitionnables par Hyper-V.")
    }
    if (-not $adapterAttached) {
        $msg = "Aucun adaptateur GPU-P n'est attache a cette VM (Get-VMGpuPartitionAdapter)."
        if ($adapterError) { $msg += " Erreur : $adapterError" }
        [void]$issues.Add($msg)
    }

    $result = [ordered]@{
        vmName                        = $Name
        vmGeneration                  = $vm.Generation
        generationOk                  = $generationOk
        hostGpuName                   = if ($realGpu) { $realGpu.Name } else { $null }
        hostGpuDriverVersion          = if ($realGpu) { $realGpu.DriverVersion } else { $null }
        hostGpuCompatible             = ($hostGpuCompatible -and $isHostGpuActuallyPartitionable)
        hostGpuError                  = $hostGpuError
        adapterAttached               = $adapterAttached
        adapterError                  = $adapterError
        adapterMinPartitionVRAM       = if ($adapter) { $adapter.MinPartitionVRAM } else { $null }
        adapterMaxPartitionVRAM       = if ($adapter) { $adapter.MaxPartitionVRAM } else { $null }
        adapterOptimalPartitionVRAM   = if ($adapter) { $adapter.OptimalPartitionVRAM } else { $null }
        driverCheckNote               = "Verification du pilote invite non incluse ici (necessite une elevation) : utilisez l'action d'installation du pilote, qui verifie sans rien casser si deja a jour."
        issuesText                    = ($issues -join " | ")
        overallOk                     = ($issues.Count -eq 0)
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Depth 6 -Compress)
}
