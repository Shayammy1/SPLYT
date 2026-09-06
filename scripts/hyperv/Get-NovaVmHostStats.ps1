<#
.SYNOPSIS
    Statistiques d'utilisation de l'hote : CPU, RAM, stockage (donnees REELLES).
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $cpuLoad) { $cpuLoad = 0 }

    # [double] explicite avant chaque [math]::Round : selon les valeurs, une
    # division PowerShell entre deux entiers peut retourner un Int64 plutot
    # qu'un Double, et [math]::Round ne sait pas toujours choisir seul entre
    # ses surcharges (Double, Int32) et (Decimal, Int32) dans ce cas
    # ("Overload not found for 'Round' and the argument count '2'").
    # RAM totale = RAM physique reelle (Win32_ComputerSystem), pas la RAM
    # "visible par l'OS" (Win32_OperatingSystem.TotalVisibleMemorySize, qui
    # est legerement inferieure) : ce chiffre doit correspondre a celui
    # utilise pour valider la RAM attribuable a une VM (Get-NovaHostMemoryInfo).
    $os = Get-CimInstance Win32_OperatingSystem
    $hostMemory = Get-NovaHostMemoryInfo
    $ramTotalGb = [math]::Round([double]$hostMemory.totalPhysicalMb / 1024, 1)
    $ramFreeGb  = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)
    $ramUsedGb  = [math]::Round([double]($ramTotalGb - $ramFreeGb), 1)

    $systemDrive = $env:SystemDrive.TrimEnd(':')
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${systemDrive}:'"
    $diskTotalGb = if ($disk) { [math]::Round([double]$disk.Size / 1GB, 1) } else { 0.0 }
    $diskFreeGb  = if ($disk) { [math]::Round([double]$disk.FreeSpace / 1GB, 1) } else { 0.0 }
    $diskUsedGb  = [math]::Round([double]($diskTotalGb - $diskFreeGb), 1)

    $stats = [ordered]@{
        cpuUsagePercent = [math]::Round([double]$cpuLoad, 1)
        ramUsedGb       = $ramUsedGb
        ramTotalGb      = $ramTotalGb
        storageUsedGb   = $diskUsedGb
        storageTotalGb  = $diskTotalGb
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]$stats | ConvertTo-Json -Depth 4 -Compress)
}
