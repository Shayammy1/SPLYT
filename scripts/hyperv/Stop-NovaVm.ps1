<#
.SYNOPSIS
    Arrete une VRAIE VM Hyper-V.

    -Force "false" (par defaut) : arret normal, via le service d'integration
    Arret (Shutdown), equivalent a demander a Windows de s'eteindre proprement
    depuis le menu Demarrer. Necessite ce service d'integration actif dans la
    VM - si absent/non reactif, cette commande echoue clairement plutot que
    de silencieusement forcer l'arret.

    -Force "true" : coupure franche (Stop-VM -TurnOff), equivalent a rester
    appuye sur le bouton d'alimentation. A utiliser si l'arret normal ne
    repond pas.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Force = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# PowerShell ne convertit pas la chaine "true"/"false" recue en ligne de commande
# (via -File) vers [bool] automatiquement - d'ou un [string] ici, converti a la main.
$forceBool = $Force -eq "true"

Invoke-NovaAction {
    if ($forceBool) {
        Stop-VM -Name $Name -TurnOff -Force -ErrorAction Stop
    } else {
        try {
            Stop-VM -Name $Name -Force -ErrorAction Stop
        } catch {
            throw "Echec de l'arret normal (le service d'integration Arret n'est peut-etre pas actif dans la VM) : $($_.Exception.Message). Utilisez l'arret force a la place."
        }
    }

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
