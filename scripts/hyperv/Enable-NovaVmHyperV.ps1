<#
.SYNOPSIS
    Active automatiquement la fonctionnalite Windows Hyper-V (necessaire pour
    tout le reste de SPLYT) si elle ne l'est pas deja, et ajoute l'utilisateur
    actuel au groupe local "Hyper-V Administrators" pour que l'application
    n'ait plus besoin d'etre relancee en administrateur ensuite.

    Necessite une elevation (Enable-WindowsOptionalFeature et Add-LocalGroupMember
    l'exigent tous les deux) - voir PowerShellRunner.RunElevatedAsync cote C#.

    Indisponible sur Windows Home (l'edition ne propose pas cette fonctionnalite
    du tout) : detecte ce cas et le signale clairement plutot que d'echouer avec
    une erreur PowerShell peu comprehensible.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    if (-not $feature) {
        $result = [ordered]@{
            editionSupported     = $false
            alreadyEnabled       = $false
            rebootRequired       = $false
            addedToHyperVAdmins  = $false
            message              = "Hyper-V n'est pas disponible sur cette edition de Windows (Windows Home ne propose pas Hyper-V). Une mise a niveau vers Windows 11 Pro, Entreprise ou Education est necessaire."
        }
        Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
        return
    }

    $alreadyEnabled = $feature.State -eq "Enabled"
    $rebootRequired = $false
    if (-not $alreadyEnabled) {
        $enableResult = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart -ErrorAction Stop
        $rebootRequired = [bool]$enableResult.RestartNeeded
    }

    # Ajoute l'utilisateur actuel au groupe "Hyper-V Administrators" (SID bien connu,
    # independant de la langue de Windows - voir la meme remarque dans Enable-NovaVmStreaming.ps1
    # au sujet des noms de groupes/composants localises) pour que SPLYT n'ait plus besoin
    # d'etre relance en administrateur au quotidien une fois Hyper-V active. Best-effort :
    # ne doit jamais faire echouer l'activation elle-meme, qui est le but principal.
    $addedToHyperVAdmins = $false
    try {
        $hyperVAdminsGroup = Get-LocalGroup -SID "S-1-5-32-578" -ErrorAction Stop
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentSid = $currentIdentity.User.Value
        $existingMembers = Get-LocalGroupMember -Group $hyperVAdminsGroup -ErrorAction SilentlyContinue
        $alreadyMember = [bool]($existingMembers | Where-Object { $_.SID.Value -eq $currentSid })
        if (-not $alreadyMember) {
            Add-LocalGroupMember -Group $hyperVAdminsGroup -Member $currentIdentity.Name -ErrorAction Stop
            $addedToHyperVAdmins = $true
        }
    } catch {
        # Non bloquant : l'utilisateur pourra toujours lancer SPLYT en administrateur
        # en attendant - voir le message final.
    }

    $messageLines = @()
    if ($alreadyEnabled) {
        $messageLines += "Hyper-V etait deja active sur ce PC."
    } else {
        $messageLines += "Hyper-V vient d'etre active."
        if ($rebootRequired) {
            $messageLines += "Un redemarrage complet du PC est necessaire pour que Hyper-V devienne utilisable."
        }
    }
    if ($addedToHyperVAdmins) {
        $messageLines += "Votre compte a ete ajoute au groupe 'Hyper-V Administrators' : SPLYT n'aura plus besoin d'etre lance en administrateur."
    }

    $result = [ordered]@{
        editionSupported    = $true
        alreadyEnabled      = $alreadyEnabled
        rebootRequired      = $rebootRequired
        addedToHyperVAdmins = $addedToHyperVAdmins
        message             = ($messageLines -join " ")
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
