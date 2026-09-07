<#
.SYNOPSIS
    Active automatiquement la fonctionnalite Windows Hyper-V (necessaire pour
    tout le reste de SPLYT) si elle ne l'est pas deja, et ajoute l'utilisateur
    actuel au groupe local "Hyper-V Administrators" pour que l'application
    n'ait plus besoin d'etre relancee en administrateur ensuite.

    Necessite une elevation (Enable-WindowsOptionalFeature, DISM et
    Add-LocalGroupMember l'exigent tous les trois) - voir
    PowerShellRunner.RunElevatedAsync cote C#.

    Sur Windows Home, Get-WindowsOptionalFeature ne propose meme pas
    Microsoft-Hyper-V-All (edition non licenciee pour cette fonctionnalite) :
    dans ce cas, tente Enable-NovaVmHyperVUnofficial ci-dessous - voir sa
    documentation pour le detail et les limites de cette methode.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# --- Methode non-officielle pour Windows Home ------------------------------
#
# BIDOUILLE COMMUNAUTAIRE, NON OFFICIELLE - meme esprit que
# Install-NovaVmNvidiaPatchedDriver.ps1 : Microsoft ne licencie pas Hyper-V
# sur Windows Home, mais les fichiers de composants (manifestes .mum) sont
# neanmoins presents sur le disque sous %SystemRoot%\servicing\Packages\,
# car Home et Pro partagent la meme image Windows - seule la liste des
# fonctionnalites proposees differe. Cette technique, documentee
# publiquement par la communaute Windows depuis Windows 10 (nombreux
# gists/forums, ex. TenForums "Enable or Disable Hyper-V in Windows 10 Home"),
# consiste a enregistrer ces paquets directement aupres de DISM (qui ne
# verifie pas la meme restriction d'edition que Enable-WindowsOptionalFeature),
# puis a activer la fonctionnalite par ce biais.
#
# FRAGILITE ASSUMEE, comme pour le pilote NVIDIA patche : cette technique
# n'est pas garantie sur toutes les versions/mises a jour de Windows 11 Home
# (Microsoft peut changer l'organisation de ces paquets a tout moment,
# puisque rien ne la garantit officiellement). Si les fichiers attendus sont
# introuvables ou si DISM echoue, cette fonction s'arrete proprement et le
# rapporte clairement plutot que de pretendre un succes.
function Enable-NovaVmHyperVUnofficial {
    $packagesDir = Join-Path $env:SystemRoot "servicing\Packages"
    $mumFiles = Get-ChildItem -Path $packagesDir -Filter "*Hyper-V*.mum" -ErrorAction SilentlyContinue

    if (-not $mumFiles -or $mumFiles.Count -eq 0) {
        return [ordered]@{
            unofficialSucceeded = $false
            rebootRequired      = $false
            message             = "Windows Home ne licencie pas officiellement Hyper-V, et la methode non-officielle habituelle (paquets de composants) n'a trouve aucun fichier compatible sur ce PC - probablement une version de Windows ou cette technique ne fonctionne plus. Hyper-V restera indisponible ici ; une mise a niveau vers Windows 11 Pro, Entreprise ou Education est necessaire."
        }
    }

    foreach ($mum in $mumFiles) {
        # Non bloquant par fichier : certains paquets listes ne s'appliquent pas a
        # toutes les configurations (ex. variantes ARM64) et DISM le signale sans
        # que ce soit une vraie erreur - seul le resultat final (Enable-Feature
        # ci-dessous) determine le succes reel.
        & dism.exe /Online /NoRestart /Add-Package:"$($mum.FullName)" 2>&1 | Out-Null
    }

    & dism.exe /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-All /All /NoRestart /LimitAccess 2>&1 | Out-Null
    $enableExitCode = $LASTEXITCODE

    # 0 = succes immediat, 3010 = succes mais redemarrage necessaire (le cas
    # normal ici, un composant hyperviseur ne s'active jamais a chaud) - tout
    # le reste est un echec reel de DISM, pas suppose autrement.
    if ($enableExitCode -ne 0 -and $enableExitCode -ne 3010) {
        return [ordered]@{
            unofficialSucceeded = $false
            rebootRequired      = $false
            message             = "La methode non-officielle a echoue (DISM a retourne le code $enableExitCode). Hyper-V reste indisponible sur cette edition de Windows."
        }
    }

    # Filet de securite : Enable-WindowsOptionalFeature positionne normalement
    # ce reglage lui-meme, mais l'enregistrement manuel des paquets via DISM
    # pourrait ne pas le faire dans tous les cas - sans lui, l'hyperviseur ne
    # demarre pas au prochain amorcage meme si la fonctionnalite est "activee".
    # Best-effort : ne fait jamais echouer l'operation globale.
    try { & bcdedit.exe /set hypervisorlaunchtype auto 2>&1 | Out-Null } catch { }

    return [ordered]@{
        unofficialSucceeded = $true
        rebootRequired      = $true
        message             = "Hyper-V vient d'etre installe via une methode non-officielle (Windows Home ne le licencie pas normalement) : cette technique n'est pas garantie sur toutes les versions de Windows et pourrait cesser de fonctionner apres une future mise a jour, mais a reussi sur ce PC. Un redemarrage complet est necessaire pour la rendre effective."
    }
}

Invoke-NovaAction {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue

    if (-not $feature) {
        $unofficial = Enable-NovaVmHyperVUnofficial

        $addedToHyperVAdmins = $false
        if ($unofficial.unofficialSucceeded) {
            # Meme ajout au groupe que le chemin officiel ci-dessous (voir son
            # commentaire) - dupliquer ces quelques lignes plutot que factoriser
            # reste plus lisible ici que de complexifier le flux principal pour
            # un cas particulier.
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
                # Non bloquant : voir la meme remarque dans le chemin officiel.
            }
        }

        $result = [ordered]@{
            editionSupported     = $false
            unofficialMethodUsed = $true
            alreadyEnabled       = $false
            rebootRequired       = $unofficial.rebootRequired
            addedToHyperVAdmins  = $addedToHyperVAdmins
            message              = $unofficial.message
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
        editionSupported     = $true
        unofficialMethodUsed = $false
        alreadyEnabled        = $alreadyEnabled
        rebootRequired        = $rebootRequired
        addedToHyperVAdmins   = $addedToHyperVAdmins
        message               = ($messageLines -join " ")
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
