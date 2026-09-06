<#
.SYNOPSIS
    RAM physique reelle de l'hote + limite raisonnable pour une VM. Utilise
    par la GUI pour borner les curseurs de RAM (creation et onglet Ressources).
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $info = Get-NovaHostMemoryInfo
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$info | ConvertTo-Json -Depth 4 -Compress)
}
