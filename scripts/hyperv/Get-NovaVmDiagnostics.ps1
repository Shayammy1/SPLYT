<#
.SYNOPSIS
    Diagnostics reels de l'environnement Hyper-V/GPU-P pour la page Parametres :
    module Hyper-V present, droits suffisants pour lister les VMs/GPU, elevation.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $hyperVModule = Get-Module -ListAvailable -Name Hyper-V | Select-Object -First 1

    $canListVms = $true
    $vmError = $null
    try { Get-VM -ErrorAction Stop | Out-Null } catch { $canListVms = $false; $vmError = $_.Exception.Message }

    $canListGpus = $true
    $gpuError = $null
    try { Get-VMHostPartitionableGpu -ErrorAction Stop | Out-Null } catch { $canListGpus = $false; $gpuError = $_.Exception.Message }

    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    # Identite exacte de la machine et de Windows : c'est ce qui manque le plus
    # dans un rapport de bug GPU-P, ou deux pannes de causes totalement
    # differentes donnent le meme symptome vu de l'exterieur. Voir le rapport de
    # diagnostic copiable (DiagnosticReportBuilder cote C#).
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $displayVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion

    $diagnostics = [ordered]@{
        osCaption                = if ($os) { $os.Caption } else { $null }
        osDisplayVersion         = $displayVersion
        osBuild                  = if ($os) { $os.BuildNumber } else { $null }
        cpuName                  = if ($cpu) { $cpu.Name } else { $null }
        hyperVModuleInstalled    = [bool]$hyperVModule
        hyperVModuleVersion      = if ($hyperVModule) { $hyperVModule.Version.ToString() } else { $null }
        canListVms               = $canListVms
        vmPermissionError        = $vmError
        canListPartitionableGpus = $canListGpus
        gpuPermissionError       = $gpuError
        isElevated               = [bool]$isElevated
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]$diagnostics | ConvertTo-Json -Depth 4 -Compress)
}
