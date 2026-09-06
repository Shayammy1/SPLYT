<#
.SYNOPSIS
    Corrige le blocage de la Session Amelioree (vmconnect) sur l'ecran de
    verrouillage flou : RDP (utilise en interne par la Session Amelioree) ne
    sait pas gerer Windows Hello, ce qui bloque la transition d'ouverture de
    session ("DesktopLocked", erreur 0x8007139F) quand le compte de la VM
    exige Windows Hello pour se connecter.

    Desactive le parametre Windows "Pour ameliorer la securite, autoriser
    uniquement la connexion Windows Hello pour les comptes Microsoft sur cet
    appareil", ce qui restaure la possibilite de se connecter par mot de
    passe - le seul mode que RDP/Session Amelioree sait gerer.

    Securite : le nom d'utilisateur et le mot de passe sont lus depuis
    l'ENTREE STANDARD (jamais en argument de ligne de commande, jamais
    journalises, jamais ecrits sur disque) - voir PowerShellRunner.RunWithCredentialAsync
    cote C#, qui les ecrit sur stdin du process powershell.exe juste apres
    l'avoir demarre.
#>
param(
    [Parameter(Mandatory)][string]$Name
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
        throw "La VM doit etre demarree pour s'y connecter (PowerShell Direct)."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    Write-NovaProgress "Connexion a la VM (PowerShell Direct)"
    $fixOutcome = $null
    try {
        $fixOutcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ScriptBlock {
            $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
            $valueName = "DevicePasswordLessBuildVersion"

            if (-not (Test-Path -LiteralPath $keyPath)) {
                New-Item -Path $keyPath -Force | Out-Null
            }

            $previous = (Get-ItemProperty -LiteralPath $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
            Set-ItemProperty -LiteralPath $keyPath -Name $valueName -Value 0 -Type DWord -Force

            [pscustomobject]@{
                PreviousValue = $previous
                NewValue      = 0
                AlreadyOff    = ($previous -eq 0)
            }
        }
    } catch {
        throw "Echec de la connexion/correction via PowerShell Direct : $($_.Exception.Message)"
    }

    $result = [ordered]@{
        previousValue = $fixOutcome.PreviousValue
        newValue      = $fixOutcome.NewValue
        alreadyOff    = $fixOutcome.AlreadyOff
        message       = if ($fixOutcome.AlreadyOff) {
            "Le parametre etait deja desactive. Si la Session Amelioree bloque toujours, deconnectez/reconnectez la session Windows dans la VM (session Basique) puis reessayez."
        } else {
            "Connexion Windows Hello obligatoire desactivee. Deconnectez la session Windows dans la VM (menu Demarrer, ou session Basique) puis reconnectez-vous en Session Amelioree - RDP peut maintenant utiliser le mot de passe."
        }
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
