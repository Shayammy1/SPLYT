<#
.SYNOPSIS
    Rattache (ou detache) dans la VM un peripherique USB deja partage par l'hote.

    C'est la moitie "invite" du dedie-a-la-VM. Une fois rattache, le peripherique
    disparait completement de l'hote et devient un vrai materiel USB pour
    l'invite : une souris y bouge le curseur de la VM, meme dans un jeu, et plus
    du tout celui de l'hote.

    Le rattachement est memorise ("stash") pour que la tache posee par
    Install-NovaVmUsbGuest.ps1 le retablisse apres un redemarrage de la VM.

    Securite : identifiants lus sur l'ENTREE STANDARD, jamais en argument ni
    dans un journal.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$BusId,
    # true = donner a la VM, false = rendre a l'hote.
    [Parameter(Mandatory)][ValidateSet('true','false')][string]$Attach
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $username = [Console]::In.ReadLine()
    $passwordPlain = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($passwordPlain)) {
        throw "Identifiants manquants (nom d'utilisateur ou mot de passe vide)."
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour lui confier un peripherique."
    }

    $vmIp = Get-NovaVmIpAddress -Name $Name
    if (-not $vmIp) {
        throw "La VM n'a pas encore d'adresse IP : attendez que Windows ait fini de demarrer."
    }

    $hostIp = Get-NovaHostAddressForVm -VmIpAddress $vmIp
    if (-not $hostIp) {
        throw "Impossible de determiner l'adresse de l'hote vue par la VM (VM en $vmIp)."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    $wantAttached = $Attach -eq 'true'

    $session = New-PSSession -VMName $Name -Credential $credential -ErrorAction Stop
    try {
        $outcome = Invoke-Command -Session $session -ArgumentList $hostIp, $BusId, $wantAttached -ScriptBlock {
            param($hostIp, $busId, $wantAttached)

            $usbip = "C:\Program Files\USBip\usbip.exe"
            if (-not (Test-Path $usbip)) {
                return [pscustomobject]@{ ok = $false; error = "Le client USB/IP n'est pas installe dans cette VM." }
            }

            if ($wantAttached) {
                # low-latency : les evenements d'une souris sont minuscules et
                # frequents, c'est le mode fait pour ca.
                $out = & $usbip attach -r $hostIp -b $busId --receive-mode low-latency 2>&1 | Out-String
                Start-Sleep -Seconds 5
                $ports = & $usbip port 2>&1 | Out-String
                if ($ports -notmatch [regex]::Escape("/$busId")) {
                    return [pscustomobject]@{ ok = $false; error = "Rattachement refuse. Detail : $($out.Trim())" }
                }
                # Memorise pour le rebranchement automatique apres redemarrage.
                & $usbip port --stash 2>&1 | Out-Null
                return [pscustomobject]@{ ok = $true; ports = $ports.Trim() }
            }

            # Detachement : retrouver le numero de port qui porte ce busId.
            $ports = & $usbip port 2>&1 | Out-String
            $portNumber = $null
            foreach ($line in ($ports -split "`r?`n")) {
                if ($line -match '^\s*Port\s+(\d+)\s*:') { $candidate = $Matches[1] }
                if ($line -match [regex]::Escape("/$busId") -and $candidate) { $portNumber = $candidate; break }
            }
            if (-not $portNumber) {
                return [pscustomobject]@{ ok = $true; ports = "deja detache" }
            }

            $out = & $usbip detach -p $portNumber 2>&1 | Out-String
            Start-Sleep -Seconds 3
            # Re-memorise l'etat courant, sinon la tache de demarrage rebrancherait
            # le peripherique qu'on vient tout juste de rendre.
            & $usbip port --stash 2>&1 | Out-Null
            return [pscustomobject]@{ ok = $true; ports = $out.Trim() }
        }

        if (-not $outcome.ok) { throw $outcome.error }

        # On note quels peripheriques appartiennent a cette VM. Sans cette liste,
        # le lancement du mode jeu n'a aucun moyen de savoir qu'il doit les
        # attendre : il partait des que Sunshine repondait, parfois avant que
        # l'invite ait recupere sa souris - et les deux souris se retrouvaient
        # alors a piloter le meme curseur.
        $prefs = Get-NovaVmPreferences -Name $Name
        $connus = @()
        if ($prefs -and $prefs.usbBusIds) {
            $connus = @($prefs.usbBusIds -split ',' | Where-Object { $_ })
        }
        $connus = if ($wantAttached) {
            @($connus + $BusId | Select-Object -Unique)
        } else {
            @($connus | Where-Object { $_ -ne $BusId })
        }
        Save-NovaVmPreferences -Name $Name -UsbBusIds ($connus -join ',')

        $message = if ($wantAttached) {
            "Peripherique confie a la VM. Il a disparu de l'hote et y reviendra si vous le rendez."
        } else {
            "Peripherique rendu a l'hote."
        }

        Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
            busId    = $BusId
            attached = $wantAttached
            hostIp   = $hostIp
            message  = $message
        } | ConvertTo-Json -Compress)
    }
    finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}
