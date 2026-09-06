<#
.SYNOPSIS
    Diagnostique et (optionnellement) active/desactive le pilote d'ecran virtuel
    tiers (Virtual Display Driver / VDD) installe manuellement dans la VM pour
    obtenir un vrai 100+ Hz avec Sunshine. VDD bascule automatiquement
    l'affichage principal de Windows sur lui-meme des son activation, ce qui
    coupe vmconnect (Basique ET Amelioree) puisqu'aucun des deux ne suit plus
    le bureau : ecran noir cote hote, mais la VM elle-meme tourne normalement.

    Tentatives abandonnees (toutes deux rapportaient un succes technique sans
    effet reel constate) :
    - Forcer automatiquement l'ecran non-VDD comme ecran principal (API Win32
      ChangeDisplaySettingsEx). Ne persiste de toute facon pas au redemarrage
      (VDD redevient principal a chaque boot).
    - Basculer en mode "Dupliquer" (DisplaySwitch.exe /clone) pour eviter
      qu'une fenetre ouvre sur l'ecran non diffuse par Sunshine : rapportait
      un succes mais les deux ecrans continuaient d'afficher des contenus
      differents en pratique.

    Compromis retenu, simple et fiable : basculer entre VDD actif (streaming
    Sunshine/Moonlight uniquement) et VDD desactive (vmconnect).

    -Disable desactive le peripherique VDD (Disable-PnpDevice), ce qui force
    Windows a retomber sur l'adaptateur reel et restaure immediatement
    vmconnect, sans avoir besoin de redemarrer la VM.

    -Enable active le peripherique VDD (Enable-PnpDevice), pour l'utiliser
    avec Sunshine/Moonlight (vmconnect ne fonctionnera plus tant qu'il est
    actif : utilisez -Disable pour le retrouver).

    Securite : le nom d'utilisateur et le mot de passe sont lus depuis
    l'ENTREE STANDARD (jamais en argument de ligne de commande, jamais
    journalises, jamais ecrits sur disque) - voir PowerShellRunner.RunWithCredentialAsync
    cote C#, qui les ecrit sur stdin du process powershell.exe juste apres
    l'avoir demarre.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Disable = "false",
    [string]$Enable = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# PowerShell ne convertit pas la chaine "true"/"false" recue en ligne de commande
# (via -File) vers [bool] automatiquement - d'ou un [string] ici, converti a la main.
$disableBool = $Disable -eq "true"
$enableBool = $Enable -eq "true"

Invoke-NovaAction {
    $username = [Console]::In.ReadLine()
    $passwordPlain = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($passwordPlain)) {
        throw "Identifiants manquants (nom d'utilisateur ou mot de passe vide)."
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour s'y connecter (PowerShell Direct)."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    Write-NovaProgress "Connexion a la VM (PowerShell Direct)"
    $outcome = $null
    try {
        $outcome = Invoke-Command -VMName $Name -Credential $credential -ArgumentList $disableBool, $enableBool -ErrorAction Stop -ScriptBlock {
            param($doDisable, $doEnable)

            $displayDevices = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                Select-Object FriendlyName, InstanceId, Status, Problem

            $vdd = $displayDevices | Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' }

            $unexpectedShutdowns = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008 } -MaxEvents 6 -ErrorAction SilentlyContinue |
                Select-Object TimeCreated, Id, Message

            $lsmErrors = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Level = 2 } -MaxEvents 6 -ErrorAction SilentlyContinue |
                Select-Object TimeCreated, Id, Message

            $disableResult = $null
            if ($doDisable) {
                if ($vdd) {
                    try {
                        Disable-PnpDevice -InstanceId $vdd.InstanceId -Confirm:$false -ErrorAction Stop
                        $disableResult = "Virtual Display Driver desactive avec succes."
                    } catch {
                        $disableResult = "Echec de la desactivation : $($_.Exception.Message)"
                    }
                } else {
                    $disableResult = "Aucun peripherique 'Virtual Display Driver' trouve (pas installe, ou deja retire)."
                }
            }

            $enableResult = $null
            if ($doEnable) {
                if ($vdd) {
                    try {
                        Enable-PnpDevice -InstanceId $vdd.InstanceId -Confirm:$false -ErrorAction Stop
                        $enableResult = "Virtual Display Driver active avec succes."
                    } catch {
                        $enableResult = "Echec de l'activation : $($_.Exception.Message)"
                    }
                } else {
                    $enableResult = "Aucun peripherique 'Virtual Display Driver' trouve (pas installe)."
                }
            }

            # Re-interroge l'etat APRES action (Enable/Disable-PnpDevice) : l'etat capture
            # plus haut, avant l'action, ne refletait que la situation de depart et pretait
            # a confusion (ex. "Error" affiche juste apres une activation reussie, alors que
            # c'etait l'etat "desactive" d'avant l'action).
            if ($doDisable -or $doEnable) {
                $displayDevices = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                    Select-Object FriendlyName, InstanceId, Status, Problem
                $vdd = $displayDevices | Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' }
            }

            [pscustomobject]@{
                DisplayDevices       = $displayDevices
                VddPresent           = [bool]$vdd
                VddStatus            = if ($vdd) { $vdd.Status.ToString() } else { $null }
                UnexpectedShutdowns  = $unexpectedShutdowns
                LsmErrors            = $lsmErrors
                DisableApplied       = $doDisable
                DisableResult        = $disableResult
                EnableApplied        = $doEnable
                EnableResult         = $enableResult
            }
        }
    } catch {
        throw "Echec de la connexion/diagnostic via PowerShell Direct : $($_.Exception.Message)"
    }

    $deviceLines = @()
    foreach ($device in $outcome.DisplayDevices) {
        $line = "$($device.FriendlyName) : $($device.Status.ToString())"
        if ($device.FriendlyName -eq 'Virtual Display Driver' -and $device.Problem -and $device.Problem.ToString() -ne 'CM_PROB_NONE') {
            $line += " (probleme : $($device.Problem.ToString()))"
        }
        $deviceLines += $line
    }
    $shutdownCount = @($outcome.UnexpectedShutdowns).Count
    $lsmErrorCount = @($outcome.LsmErrors).Count

    $summaryLines = @()
    $summaryLines += "Peripheriques d'affichage :"
    $summaryLines += $deviceLines
    $summaryLines += ""
    $summaryLines += "Redemarrages non planifies recents (Kernel-Power) : $shutdownCount"
    $summaryLines += "Erreurs recentes du gestionnaire de sessions RDP : $lsmErrorCount"
    if ($outcome.DisableApplied) {
        $summaryLines += ""
        $summaryLines += $outcome.DisableResult
    } elseif ($outcome.EnableApplied) {
        $summaryLines += ""
        $summaryLines += $outcome.EnableResult
        $summaryLines += "vmconnect (Basique ET Amelioree) va cesser de fonctionner tant que VDD est actif - utilisez Sunshine/Moonlight pour voir/controler la VM. Cliquez 'Desactiver VDD' pour retrouver vmconnect."
    } elseif ($outcome.VddPresent -and $outcome.VddStatus -eq 'OK') {
        $summaryLines += ""
        $summaryLines += "VDD est actif : vmconnect ne fonctionnera pas tant qu'il n'est pas desactive. Utilisez Sunshine/Moonlight, ou le bouton de desactivation pour retrouver vmconnect."
    }

    $result = [ordered]@{
        vddPresent      = $outcome.VddPresent
        vddStatus       = $outcome.VddStatus
        shutdownCount   = $shutdownCount
        lsmErrorCount   = $lsmErrorCount
        disableApplied  = $outcome.DisableApplied
        disableResult   = $outcome.DisableResult
        enableApplied   = $outcome.EnableApplied
        enableResult    = $outcome.EnableResult
        message         = ($summaryLines -join "`n")
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
