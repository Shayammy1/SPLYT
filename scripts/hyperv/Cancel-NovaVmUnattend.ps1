<#
.SYNOPSIS
    Abandonne une installation automatique en cours et rend la VM a
    l'utilisateur : console de nouveau ouvrable, onglets et boutons de retour,
    barre de progression effacee.

    Marche aussi bien sur une VM encore allumee que sur une VM deja eteinte -
    une installation interrompue laisse justement le drapeau leve sur une
    machine a l'arret, et sans ce chemin la VM restait inutilisable (plus aucun
    bouton, pas meme Supprimer).

    N'efface PAS le disque : l'installation reste la ou elle en etait, et un
    demarrage normal la reprendra. Pour se debarrasser de la machine, c'est
    Remove-NovaVm.ps1 qui s'en charge, une fois celle-ci rendue.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "NovaVm.Unattend.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop

    # Coupure franche, pas d'arret propre : pendant une installation, le service
    # d'integration Arret n'est pas en etat de repondre, et un arret normal
    # echouerait en laissant la VM allumee - donc toujours cachee.
    if ($vm.State -ne 'Off') {
        Write-NovaProgress "Arret de la machine"
        Stop-VM -Name $Name -TurnOff -Force -ErrorAction Stop
    }

    # L'ISO de reponses porte le mot de passe du compte Windows, sans autre
    # protection qu'un encodage reversible. Une installation abandonnee n'a
    # aucune raison de la laisser trainer sur le disque.
    Write-NovaProgress "Suppression du fichier de reponses"
    try { Remove-NovaUnattendIso -VmName $Name } catch { }

    Save-NovaVmPreferences -Name $Name -UnattendPending "false" -UnattendStage "cancelled" -UnattendPercent 0

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
