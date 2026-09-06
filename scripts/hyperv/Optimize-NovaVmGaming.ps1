<#
.SYNOPSIS
    Applique des optimisations Windows courantes pour le jeu/streaming a
    l'interieur de la VM, via PowerShell Direct avec les identifiants Windows
    de la VM fournis par l'utilisateur. Reprend les reglages habituels des
    outils de "debloat" Windows grand public (ex. WinToys) : reglages
    Registre et powercfg standards et documentes, aucun outil tiers requis.

    -Performance applique :
    - Active le profil d'alimentation "Ultimate Performance" (supprime la
      mise en veille des coeurs CPU, contrairement au profil "Performances
      elevees").
    - Active le Hardware-accelerated GPU scheduling (HAGS) si la cle existe
      (depend du pilote GPU - non disponible partout).
    - Desactive la securite basee sur la virtualisation (VBS).
    - Desactive le demarrage rapide (Fast Startup).
    HAGS, VBS et le demarrage rapide sont des reglages de demarrage : un
    redemarrage complet de la VM est necessaire pour qu'ils prennent effet.

    -Privacy applique :
    - Reduit la telemetrie Windows au minimum et desactive le service
      "Connected User Experiences and Telemetry" (DiagTrack).
    - Desactive l'identifiant publicitaire.
    - Desactive la localisation de facon permanente (strategie de groupe -
      l'utilisateur ne peut plus la reactiver depuis les Parametres).

    Chaque reglage est applique independamment (l'echec de l'un n'empeche pas
    les autres) et rapporte individuellement dans le resultat.

    Necessite que le compte Windows de la VM soit administrateur (ecriture
    dans HKEY_LOCAL_MACHINE + gestion de services).

    Securite : le nom d'utilisateur et le mot de passe sont lus depuis
    l'ENTREE STANDARD (jamais en argument de ligne de commande, jamais
    journalises, jamais ecrits sur disque) - voir PowerShellRunner.RunWithCredentialAsync
    cote C#, qui les ecrit sur stdin du process powershell.exe juste apres
    l'avoir demarre.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Performance = "false",
    [string]$Privacy = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

$performanceBool = $Performance -eq "true"
$privacyBool = $Privacy -eq "true"

Invoke-NovaAction {
    if (-not $performanceBool -and -not $privacyBool) {
        throw "Aucune optimisation demandee."
    }

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
        $outcome = Invoke-Command -VMName $Name -Credential $credential -ArgumentList $performanceBool, $privacyBool -ErrorAction Stop -ScriptBlock {
            param($doPerformance, $doPrivacy)

            $steps = New-Object System.Collections.Generic.List[object]
            function Add-Step {
                param([string]$StepName, [bool]$StepSuccess, [string]$Detail)
                $steps.Add([pscustomobject]@{ Name = $StepName; Success = $StepSuccess; Detail = $Detail })
            }

            if ($doPerformance) {
                try {
                    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
                    $existingLine = powercfg -list | Select-String "Ultimate Performance"
                    if ($existingLine -and ($existingLine.Line -match $guidPattern)) {
                        $ultimateGuid = $Matches[0]
                    } else {
                        $dupOutput = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61) -join ' '
                        if ($dupOutput -match $guidPattern) {
                            $ultimateGuid = $Matches[0]
                        } else {
                            throw "Le profil 'Ultimate Performance' n'a pas pu etre cree (sortie powercfg inattendue)."
                        }
                    }
                    powercfg -setactive $ultimateGuid | Out-Null
                    Add-Step "Profil d'alimentation Ultimate Performance" $true "Cree (si necessaire) et active."
                } catch {
                    Add-Step "Profil d'alimentation Ultimate Performance" $false $_.Exception.Message
                }

                try {
                    $graphicsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
                    $hasHagsValue = $null -ne (Get-ItemProperty -LiteralPath $graphicsKey -Name "HwSchMode" -ErrorAction SilentlyContinue)
                    if ($hasHagsValue) {
                        Set-ItemProperty -LiteralPath $graphicsKey -Name "HwSchMode" -Value 2 -Type DWord -Force
                        Add-Step "Hardware-accelerated GPU scheduling (HAGS)" $true "Active (redemarrage necessaire)."
                    } else {
                        Add-Step "Hardware-accelerated GPU scheduling (HAGS)" $false "Non disponible sur cette VM (cle HwSchMode absente - pilote GPU trop ancien, ou GPU-P inactif)."
                    }
                } catch {
                    Add-Step "Hardware-accelerated GPU scheduling (HAGS)" $false $_.Exception.Message
                }

                try {
                    $deviceGuardKey = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
                    if (-not (Test-Path -LiteralPath $deviceGuardKey)) { New-Item -Path $deviceGuardKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $deviceGuardKey -Name "EnableVirtualizationBasedSecurity" -Value 0 -Type DWord -Force

                    $policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"
                    if (Test-Path -LiteralPath $policyKey) {
                        Set-ItemProperty -LiteralPath $policyKey -Name "EnableVirtualizationBasedSecurity" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                    Add-Step "Securite basee sur la virtualisation (VBS)" $true "Desactivee (redemarrage necessaire)."
                } catch {
                    Add-Step "Securite basee sur la virtualisation (VBS)" $false $_.Exception.Message
                }

                try {
                    $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
                    Set-ItemProperty -LiteralPath $powerKey -Name "HiberbootEnabled" -Value 0 -Type DWord -Force
                    Add-Step "Demarrage rapide (Fast Startup)" $true "Desactive (redemarrage necessaire)."
                } catch {
                    Add-Step "Demarrage rapide (Fast Startup)" $false $_.Exception.Message
                }
            }

            if ($doPrivacy) {
                try {
                    $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                    if (-not (Test-Path -LiteralPath $dataCollectionKey)) { New-Item -Path $dataCollectionKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force

                    foreach ($serviceName in @("DiagTrack", "dmwappushservice")) {
                        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($svc) {
                            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                            Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
                        }
                    }
                    Add-Step "Telemetrie Windows" $true "Reduite au minimum, service DiagTrack desactive."
                } catch {
                    Add-Step "Telemetrie Windows" $false $_.Exception.Message
                }

                try {
                    $adInfoUserKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
                    if (-not (Test-Path -LiteralPath $adInfoUserKey)) { New-Item -Path $adInfoUserKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $adInfoUserKey -Name "Enabled" -Value 0 -Type DWord -Force

                    $adInfoPolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
                    if (-not (Test-Path -LiteralPath $adInfoPolicyKey)) { New-Item -Path $adInfoPolicyKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $adInfoPolicyKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

                    Add-Step "Identifiant publicitaire" $true "Desactive."
                } catch {
                    Add-Step "Identifiant publicitaire" $false $_.Exception.Message
                }

                try {
                    $locationPolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
                    if (-not (Test-Path -LiteralPath $locationPolicyKey)) { New-Item -Path $locationPolicyKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $locationPolicyKey -Name "DisableLocation" -Value 1 -Type DWord -Force

                    $consentKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
                    if (Test-Path -LiteralPath $consentKey) {
                        Set-ItemProperty -LiteralPath $consentKey -Name "Value" -Value "Deny" -Type String -Force -ErrorAction SilentlyContinue
                    }
                    Add-Step "Localisation" $true "Desactivee de facon permanente (strategie de groupe)."
                } catch {
                    Add-Step "Localisation" $false $_.Exception.Message
                }
            }

            [pscustomobject]@{ Steps = $steps }
        }
    } catch {
        throw "Echec de la connexion/optimisation via PowerShell Direct : $($_.Exception.Message)"
    }

    $lines = foreach ($step in $outcome.Steps) {
        $icon = if ($step.Success) { "[OK]" } else { "[NON APPLIQUE]" }
        "$icon $($step.Name) : $($step.Detail)"
    }
    if ($performanceBool) {
        $lines += ""
        $lines += "HAGS, VBS et le demarrage rapide ne prennent effet qu'apres un redemarrage complet de la VM (Arreter puis Demarrer)."
    }

    $result = [ordered]@{
        steps             = $outcome.Steps
        rebootRecommended = $performanceBool
        message           = ($lines -join "`n")
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Depth 6 -Compress)
}
