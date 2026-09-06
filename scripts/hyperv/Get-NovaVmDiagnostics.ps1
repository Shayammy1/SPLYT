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

    $diagnostics = [ordered]@{
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
