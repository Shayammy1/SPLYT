<#
.SYNOPSIS
    Liste les GPU physiques de l'hote (donnees REELLES via WMI), avec un
    partitionSupported determine par une vraie verification croisee avec
    Get-VMHostPartitionableGpu (pas suppose vrai par defaut). La VRAM vient du
    registre (Get-NovaRealGpuVramBytes) : Win32_VideoController.AdapterRAM est
    un DWORD 32 bits qui plafonne/deborde pour tout GPU au-dela de ~4 Go
    (verifie : rapporte 4 Go pour un GPU qui en a reellement 24).
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $partitionableGpus = $null
    $partitionCheckError = $null
    try {
        $partitionableGpus = Get-VMHostPartitionableGpu -ErrorAction Stop
    } catch {
        $partitionCheckError = $_.Exception.Message
    }

    $adapters = Get-CimInstance Win32_VideoController |
        Where-Object { $_.Name -and $_.Name -notmatch "Basic Render|Remote Desktop" } |
        ForEach-Object {
            $realVram = Get-NovaRealGpuVramBytes -PnpDeviceId $_.PNPDeviceID
            [ordered]@{
                name               = $_.Name
                vramBytes          = if ($realVram) { $realVram } elseif ($_.AdapterRAM) { [int64]$_.AdapterRAM } else { 0 }
                driverVersion      = $_.DriverVersion
                partitionSupported = Test-NovaGpuPartitionable -PnpDeviceId $_.PNPDeviceID -PartitionableGpus $partitionableGpus
                partitionCheckError = $partitionCheckError
            }
        }

    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaJsonArray -InputObject $adapters)
}
