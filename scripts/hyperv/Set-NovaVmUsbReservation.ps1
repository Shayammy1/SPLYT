<#
.SYNOPSIS
    Reserve (ou libere) un peripherique USB pour une VM, SANS la contacter.

    Sert au cas ou la VM est eteinte : "usbip attach" tourne dans l'invite et va
    chercher le peripherique par le reseau, une machine a l'arret ne peut donc
    rien recevoir. Ce script se contente de noter l'intention ; SPLYT rattache
    ensuite les peripheriques reserves des que la VM est prete.

    Ne touche pas au partage cote hote : c'est Set-NovaUsbShare.ps1 qui s'en
    charge, et l'appelant enchaine les deux (le partage demande l'elevation, pas
    cette ecriture-ci).

    La meme liste sert deja au lancement du mode jeu, qui attend que la VM ait
    repris ses peripheriques avant de brancher le flux.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$BusId,
    # true = reserver pour cette VM, false = ne plus la lui reserver.
    [Parameter(Mandatory)][ValidateSet('true','false')][string]$Reserved
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    # Verifie que la VM existe, pour ne pas ecrire une preference orpheline.
    $null = Get-VM -Name $Name -ErrorAction Stop

    $wantReserved = $Reserved -eq 'true'
    $prefs = Get-NovaVmPreferences -Name $Name

    $reserves = @()
    if ($prefs -and $prefs.usbBusIds) {
        $reserves = @($prefs.usbBusIds -split ',' | Where-Object { $_ })
    }

    $reserves = if ($wantReserved) {
        @($reserves + $BusId | Select-Object -Unique)
    } else {
        @($reserves | Where-Object { $_ -ne $BusId })
    }

    Save-NovaVmPreferences -Name $Name -UsbBusIds ($reserves -join ',')

    $message = if ($wantReserved) {
        "Peripherique reserve pour cette VM. Il lui sera confie des qu'elle sera prete."
    } else {
        "Peripherique plus reserve pour cette VM."
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        busId     = $BusId
        reserved  = $wantReserved
        usbBusIds = ($reserves -join ',')
        message   = $message
    } | ConvertTo-Json -Compress)
}
