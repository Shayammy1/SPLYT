<#
.SYNOPSIS
    Retourne la liste des VRAIES VMs Hyper-V de la machine.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vms = Get-VM -ErrorAction Stop
    $dtos = foreach ($vm in $vms) { ConvertTo-NovaVmDto -Vm $vm }
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaJsonArray -InputObject $dtos)
}
