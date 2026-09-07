<#
.SYNOPSIS
    Processus detache lance par Start-NovaVm.ps1 : envoie Entree en rafale au
    clavier virtuel pendant les toutes premieres secondes du demarrage.

    L'invite firmware "Press any key to boot from CD or DVD..." ne reste active
    qu'une seconde ou deux, et peut apparaitre en moins de 2 secondes apres
    Start-VM (confirme empiriquement par l'utilisateur) : la duree totale de
    cette boucle importe donc bien moins que le moment ou elle COMMENCE
    reellement a envoyer des touches. C'est pour ca que Start-NovaVm.ps1 lance
    ce script AVANT Start-VM (pas apres) : le cout de demarrage d'un nouveau
    powershell.exe (JIT, chargement des assemblies CIM au premier appel) se
    chevauche alors avec Start-VM au lieu de s'ajouter apres, et la boucle
    ci-dessous est deja chaude - en train de reessayer toutes les 50 ms - au
    moment ou l'invite apparait reellement, quel qu'il soit.
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
        # VM pas encore demarree / clavier pas encore associe : on reessaie au tour suivant.
    }
    Start-Sleep -Milliseconds 50
}
