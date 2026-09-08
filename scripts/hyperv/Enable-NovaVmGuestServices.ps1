<#
.SYNOPSIS
    Active le composant d'integration "Interface de services invite" d'une VM, qui
    permet de deposer un fichier dedans sans reseau (Copy-VMFile) - indispensable
    pour y apporter l'installeur Sunshine.

    Pourquoi un script a part : ce composant n'est utilisable qu'apres un
    redemarrage COMPLET de la VM (le service correspondant cote invite ne demarre
    qu'a l'amorcage). L'activer depuis Enable-NovaVmStreaming.ps1, qui exige une VM
    demarree, obligeait donc l'utilisateur a redemarrer puis relancer l'action a la
    main. Appele ici pendant que la VM est deja arretee - au milieu de
    l'enchainement du bouton SPLYT, qui la redemarre juste apres - il devient
    utilisable sans aucun aller-retour.

    Sans effet si le composant est deja actif.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    # Par GUID et non par nom : ces noms sont traduits par Windows (voir
    # Test-NovaVmHeartbeatOk pour le detail de ce piege).
    $guestServiceInterface = Get-VMIntegrationService -VMName $Name -ErrorAction Stop |
        Where-Object { $_.Id -like "*6C09BB55-D683-4DA0-8931-C9BF705F6480*" } | Select-Object -First 1
    if (-not $guestServiceInterface) {
        throw "Le composant d'integration 'Interface de services invite' est introuvable sur cette VM."
    }

    $alreadyEnabled = [bool]$guestServiceInterface.Enabled
    if (-not $alreadyEnabled) {
        # Passer l'objet et non -Name, pour la meme raison de localisation.
        Enable-VMIntegrationService -VMIntegrationService $guestServiceInterface -ErrorAction Stop
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    $result = [ordered]@{
        alreadyEnabled = $alreadyEnabled
        # Utilisable tout de suite si la VM est eteinte (elle demarrera avec) ; sinon
        # il faudra attendre son prochain demarrage complet.
        restartNeeded  = (-not $alreadyEnabled) -and ($vm.State -ne 'Off')
        message        = if ($alreadyEnabled) {
            "Interface de services invite deja active."
        } else {
            "Interface de services invite activee."
        }
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
