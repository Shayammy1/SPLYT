<#
.SYNOPSIS
    Installe DANS LA VM le client USB/IP (projet usbip-win2), qui recoit les
    peripheriques USB confies par l'hote, et la tache qui les rebranche tout
    seuls apres un redemarrage.

    Pas besoin de Mode test ni de toucher au Secure Boot de la VM : depuis
    l'Open Source Codesigning Initiative, les pilotes du projet sont signes par
    attestation Microsoft. Les guides plus anciens qui reclament
    "bcdedit /set testsigning on" decrivent un etat revolu.

    Aucun peripherique n'a besoin d'etre branche a ce stade : ce script ne pose
    que la plomberie. Le choix du peripherique vient ensuite
    (Set-NovaUsbShare.ps1 cote hote, puis Set-NovaVmUsbAttach.ps1 cote invite).

    Securite : identifiants lus sur l'ENTREE STANDARD, jamais en argument ni
    dans un journal - voir PowerShellRunner.RunWithCredentialAsync.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Version connue qui fonctionne, utilisee si l'API GitHub est injoignable. Meme
# precaution que pour VDD : une panne de github.com ne doit pas rendre
# l'installation impossible.
$fallbackVersion = "0.9.8.0"

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

    $session = New-PSSession -VMName $Name -Credential $credential -ErrorAction Stop
    try {
        $already = Invoke-Command -Session $session -ScriptBlock {
            Test-Path "C:\Program Files\USBip\usbip.exe"
        }

        if (-not $already) {
            Write-NovaProgress "Telechargement du client USB/IP"

            $downloadUrl = $null
            try {
                $release = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop `
                    -Uri "https://api.github.com/repos/vadimgrn/usbip-win2/releases/latest" `
                    -Headers @{ "User-Agent" = "SPLYT" }
                $asset = $release.assets | Where-Object { $_.name -like "USBip-*-x64.exe" } | Select-Object -First 1
                if ($asset) { $downloadUrl = $asset.browser_download_url }
            } catch {
                # API injoignable ou limitee en debit : on garde la version connue.
            }
            if (-not $downloadUrl) {
                $downloadUrl = "https://github.com/vadimgrn/usbip-win2/releases/download/v.$fallbackVersion/USBip-$fallbackVersion-x64.exe"
            }

            $local = Join-Path $env:TEMP "SPLYT-USBip-client.exe"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $local -UseBasicParsing -ErrorAction Stop

            # Signature verifiee AVANT de deposer quoi que ce soit dans la VM : on
            # installe un pilote noyau chez l'utilisateur, un binaire altere en
            # chemin ne doit pas y arriver.
            $signature = Get-AuthenticodeSignature -FilePath $local
            if ($signature.Status -ne 'Valid') {
                Remove-Item $local -Force -ErrorAction SilentlyContinue
                throw "L'installeur du client USB/IP n'a pas une signature valide ($($signature.Status)) : installation annulee."
            }

            Write-NovaProgress "Installation du client USB/IP dans la VM"
            Copy-Item -Path $local -Destination "C:\Windows\Temp\USBip-setup.exe" -ToSession $session -Force
            Remove-Item $local -Force -ErrorAction SilentlyContinue

            $installed = Invoke-Command -Session $session -ScriptBlock {
                $proc = Start-Process -FilePath "C:\Windows\Temp\USBip-setup.exe" `
                    -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
                Start-Sleep -Seconds 5
                Remove-Item "C:\Windows\Temp\USBip-setup.exe" -Force -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    exitCode = $proc.ExitCode
                    present  = (Test-Path "C:\Program Files\USBip\usbip.exe")
                }
            }
            if (-not $installed.present) {
                throw "L'installation du client USB/IP dans la VM a echoue (code $($installed.exitCode))."
            }
        }

        Write-NovaProgress "Mise en place du rebranchement automatique"
        $taskState = Invoke-Command -Session $session -ScriptBlock {
            # Au demarrage, rebranche ce qui a ete memorise par "usbip port --stash".
            # usbip relance ses tentatives de lui-meme si l'hote n'est pas encore
            # pret, donc pas besoin de temporisation ici.
            $taskName = "SPLYT - Peripheriques USB dedies"
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

            $action = New-ScheduledTaskAction -Execute "C:\Program Files\USBip\usbip.exe" -Argument "attach --persistent"
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings | Out-Null

            (Get-ScheduledTask -TaskName $taskName).State.ToString()
        }

        # Invoke-Command decore ce qu'il renvoie (PSComputerName, RunspaceId...) :
        # sans cette remise a plat, le JSON porte un OBJET la ou le C# attend un
        # texte, et toute la reponse devient indeserialisable.
        $taskState = "$taskState"

        $message = if ($already) {
            "Le client USB/IP etait deja installe dans la VM ; le rebranchement automatique est en place."
        } else {
            "Client USB/IP installe dans la VM, avec rebranchement automatique au demarrage."
        }

        Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
            alreadyInstalled = [bool]$already
            autoReattachTask = $taskState
            message          = $message
        } | ConvertTo-Json -Compress)
    }
    finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}
