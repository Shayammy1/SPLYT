<#
.SYNOPSIS
    Processus detache lance par Start-NovaVm.ps1 : envoie Entree en rafale au
    clavier virtuel pendant les toutes premieres secondes du demarrage.

    L'invite firmware "Press any key to boot from CD or DVD..." ne reste active
    qu'une seconde ou deux (confirme empiriquement) : un seul envoi differe de
    quelques secondes (comme la version precedente de ce mecanisme) la rate
    systematiquement. On envoie donc une touche toutes les 200 ms pendant 10
    secondes, en commencant immediatement, pour couvrir cette fenetre etroite
    quel que soit le moment exact ou elle apparait.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    try {
        $cimVm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem `
            -Filter "ElementName='$Name'" -ErrorAction Stop
        $keyboard = Get-CimAssociatedInstance -InputObject $cimVm -ResultClassName Msvm_Keyboard -ErrorAction Stop
        if ($keyboard) {
            Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } -ErrorAction Stop | Out-Null
        }
    } catch {
        # VM pas encore prete / clavier pas encore associe : on reessaie au tour suivant.
    }
    Start-Sleep -Milliseconds 200
}
