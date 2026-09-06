<#
.SYNOPSIS
    Processus detache lance par Start-NovaVm.ps1 : envoie Entree en rafale au
    clavier virtuel pendant les toutes premieres secondes du demarrage.

    L'invite firmware "Press any key to boot from CD or DVD..." ne reste active
    qu'une seconde ou deux (confirme empiriquement) : un seul envoi differe de
    quelques secondes (comme la version precedente de ce mecanisme) la rate
    systematiquement. On envoie donc une touche toutes les 200 ms, en
    commencant immediatement, pour couvrir cette fenetre etroite quel que
    soit le moment exact ou elle apparait.

    Fenetre de 45 secondes (pas 10) : le POST UEFI avant meme d'atteindre
    cette invite (verification TPM/Secure Boot, plus de vCPU/RAM sur une VM
    consequente, hote charge) peut largement depasser 10 secondes - dans ce
    cas la fenetre se terminait avant meme que l'invite apparaisse, et la VM
    ne demarrait jamais l'installeur (symptome : "ne boot pas toute seule
    sur l'ISO"). Sans risque une fois l'installeur Windows lance : Entree
    n'a d'effet que sur un controle deja focalise par defaut (ex. "Suivant"),
    jamais sur un champ de saisie ou une case a cocher vide.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

$deadline = (Get-Date).AddSeconds(45)
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
