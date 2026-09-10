<#
.SYNOPSIS
    Installe Sunshine SILENCIEUSEMENT a l'interieur de la VM via PowerShell
    Direct (Invoke-Command -VMName), en utilisant les identifiants Windows de
    la VM fournis par l'utilisateur. Sans identifiants, il n'existe aucun
    moyen d'installer un logiciel a l'interieur d'un Windows invite : c'est
    une exigence de securite de Windows lui-meme, pas une limite de NovaVM.

    Securite : le nom d'utilisateur et le mot de passe sont lus depuis
    l'ENTREE STANDARD (jamais en argument de ligne de commande, jamais
    journalises, jamais ecrits sur disque) - voir PowerShellRunner.RunWithCredentialAsync
    cote C#, qui les ecrit sur stdin du process powershell.exe juste apres
    l'avoir demarre.

    Ne fait PAS l'appairage Sunshine<->Moonlight (code PIN) : c'est une
    protection volontaire de Sunshine contre le streaming non consenti,
    delibfrement non contournee ici.
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
    try {
        $installOutcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ScriptBlock {
            # Deja installe (ex. relance pour appliquer le correctif CSRF ci-dessous) : on
            # evite de relancer msiexec, qui peut renvoyer un code d'echec (ex. 1638) sur une
            # installation deja presente avec la meme version.
            $exitCode = 0
            $service = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
            if (-not $service) {
                $installerPath = "C:\Users\Public\Desktop\Installer-Sunshine.msi"
                if (-not (Test-Path -LiteralPath $installerPath)) {
                    throw "Installeur Sunshine introuvable sur le Bureau de la VM ($installerPath). Utilisez d'abord l'action 'Preparer le streaming 100+ Hz'."
                }

                $process = Start-Process -FilePath "msiexec.exe" `
                    -ArgumentList "/i", "`"$installerPath`"", "/qn", "/norestart" `
                    -Wait -PassThru
                # 0 = succes ; 3010 = succes, redemarrage souhaitable (pas obligatoire ici).
                if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
                    throw "L'installation de Sunshine a echoue dans la VM (code msiexec $($process.ExitCode))."
                }
                $exitCode = $process.ExitCode

                Start-Sleep -Seconds 5
                $service = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
            }

            # Sunshine rejette par defaut l'interface web quand elle est ouverte via une
            # adresse IP (erreur "CSRF Protection Error") : seuls localhost/127.0.0.1 sont
            # trouble par defaut. On ajoute automatiquement toutes les IPv4 reelles de la VM
            # a 'csrf_allowed_origins' dans sunshine.conf pour que l'ouverture automatique de
            # l'interface web (via l'IP de la VM) fonctionne sans manipulation manuelle.
            $configPath = "C:\Program Files\Sunshine\config\sunshine.conf"
            $csrfConfigured = $false
            for ($attempt = 0; $attempt -lt 10 -and -not (Test-Path -LiteralPath $configPath); $attempt++) {
                Start-Sleep -Seconds 2
            }
            if (Test-Path -LiteralPath $configPath) {
                $guestIps = @()
                $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
                foreach ($ipAddress in $ipAddresses) {
                    if ($ipAddress.IPAddress -ne '127.0.0.1' -and $ipAddress.IPAddress -notlike '169.254.*') {
                        $guestIps += $ipAddress.IPAddress
                    }
                }

                if ($guestIps.Count -gt 0) {
                    $newOrigins = @($guestIps | ForEach-Object { "https://${_}:47990" })

                    $existingLines = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
                    if (-not $existingLines) { $existingLines = @() }

                    $csrfLineIndex = -1
                    $existingOrigins = @()
                    for ($i = 0; $i -lt $existingLines.Count; $i++) {
                        if ($existingLines[$i] -match '^\s*csrf_allowed_origins\s*=\s*(.*)$') {
                            $csrfLineIndex = $i
                            # Extraction par motif plutot que par decoupage sur la virgule :
                            # les versions precedentes ont pu ecrire une ligne ou les origines
                            # sont COLLEES les unes aux autres (voir le @() ci-dessous), et un
                            # simple split la laisserait telle quelle a jamais. Repartir des
                            # adresses reellement reconnues repare la ligne au passage.
                            $existingOrigins = @([regex]::Matches($Matches[1], 'https?://[^,\s]+?:\d+') |
                                ForEach-Object { $_.Value })
                            break
                        }
                    }

                    # Le @() autour de la concatenation n'est pas decoratif : quand une seule
                    # origine etait deja presente, PowerShell rendait $existingOrigins sous
                    # forme de CHAINE et non de tableau, et "+" concatenait alors du texte au
                    # lieu de fusionner deux listes. La ligne ecrite devenait
                    # "https://a:47990https://b:47990" - une origine unique et invalide, donc
                    # une protection CSRF qui refusait justement l'adresse qu'on venait
                    # d'autoriser.
                    $allOrigins = @(@($existingOrigins) + @($newOrigins) | Select-Object -Unique)
                    $newLine = "csrf_allowed_origins = $($allOrigins -join ',')"

                    if ($csrfLineIndex -ge 0) {
                        $existingLines[$csrfLineIndex] = $newLine
                    } else {
                        $existingLines += $newLine
                    }

                    [System.IO.File]::WriteAllLines($configPath, [string[]]$existingLines, [System.Text.UTF8Encoding]::new($false))
                    Restart-Service -Name "SunshineService" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    $csrfConfigured = $true
                }
            }

            [pscustomobject]@{
                ExitCode       = $exitCode
                ServiceFound   = [bool]$service
                ServiceStatus  = if ($service) { $service.Status.ToString() } else { $null }
                CsrfConfigured = $csrfConfigured
            }
        }
    } catch {
        throw "Echec de la connexion/installation via PowerShell Direct : $($_.Exception.Message)"
    }

    Write-NovaProgress "Recuperation de l'adresse de la VM"
    $vmIp = (Get-VMNetworkAdapter -VMName $Name -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1

    $result = [ordered]@{
        exitCode        = $installOutcome.ExitCode
        serviceFound    = $installOutcome.ServiceFound
        serviceStatus   = $installOutcome.ServiceStatus
        csrfConfigured  = $installOutcome.CsrfConfigured
        vmIpAddress     = $vmIp
        sunshineWebUiUrl = if ($vmIp) { "https://${vmIp}:47990" } else { $null }
        message         = "Sunshine installe automatiquement dans la VM" + $(if ($installOutcome.CsrfConfigured) { " (protection CSRF configuree pour l'IP de la VM)" } else { "" }) + ". Ouvrez son interface web pour creer son compte (1ere fois), puis appairez avec Moonlight (code PIN affiche par Sunshine) : cette derniere etape ne peut pas etre automatisee (protection volontaire contre le streaming non consenti)."
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
