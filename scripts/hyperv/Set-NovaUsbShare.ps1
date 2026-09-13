<#
.SYNOPSIS
    Partage (ou cesse de partager) un peripherique USB de l'hote, pour qu'une VM
    puisse s'en saisir.

    C'est la moitie "hote" du dedie-a-la-VM, et la seule qui demande l'elevation :
    usbipd pose un pilote de filtre sur le peripherique. Le rattachement cote
    invite se fait ensuite sans elevation (Set-NovaVmUsbAttach.ps1).

    Le partage suit le PORT USB, pas le peripherique : rebranche ailleurs, il
    faudra le repartager. C'est une contrainte d'usbipd, pas un choix de SPLYT.
#>
param(
    [Parameter(Mandatory)][string]$BusId,
    # true = partager, false = rendre le peripherique a l'hote.
    [Parameter(Mandatory)][ValidateSet('true','false')][string]$Share
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $usbipd = Get-NovaUsbipdPath
    if (-not $usbipd) {
        throw "Le serveur USB/IP n'est pas installe sur cet ordinateur. Lancez d'abord la configuration SPLYT de la VM."
    }

    $wantShared = $Share -eq 'true'
    if ($wantShared) {
        Write-NovaProgress "Partage du peripherique $BusId"
        $output = & $usbipd bind --busid $BusId 2>&1 | Out-String
    } else {
        Write-NovaProgress "Restitution du peripherique $BusId a l'hote"
        $output = & $usbipd unbind --busid $BusId 2>&1 | Out-String
    }

    # usbipd rend 0 meme quand il refuse (peripherique deja dans l'etat demande) :
    # on relit l'etat reel plutot que de se fier au code de sortie.
    $state = (& $usbipd state 2>&1 | Out-String) | ConvertFrom-Json
    $device = $state.Devices | Where-Object { $_.BusId -eq $BusId } | Select-Object -First 1
    if (-not $device) {
        throw "Le peripherique $BusId n'est plus branche sur cet ordinateur."
    }

    $isShared = -not [string]::IsNullOrWhiteSpace("$($device.PersistedGuid)")
    if ($isShared -ne $wantShared) {
        throw "Le changement d'etat du peripherique $BusId a echoue. Detail : $($output.Trim())"
    }

    $message = if ($isShared) { "Peripherique partage, pret a etre pris par la VM." }
               else { "Peripherique rendu a l'hote." }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        busId       = $BusId
        description = "$($device.Description)"
        shared      = $isShared
        message     = $message
    } | ConvertTo-Json -Compress)
}
