<#
.SYNOPSIS
    Installe automatiquement et silencieusement le pilote d'ecran virtuel tiers
    (Virtual Display Driver / VDD, projet open-source
    github.com/VirtualDrivers/Virtual-Display-Driver) a l'interieur de la VM,
    via PowerShell Direct avec les identifiants Windows de la VM fournis par
    l'utilisateur.

    Reproduit exactement la methode d'installation silencieuse documentee et
    fournie par le projet lui-meme (dossier "Community Scripts/silent-install.ps1"
    du depot officiel) :
    1. Telecharge NefCon (nefarius/nefcon - outil signe permettant d'installer
       un peripherique "root-enumerated", c'est-a-dire sans materiel physique
       associe, sans avoir besoin de devcon.exe ni d'activer le Mode test).
    2. Telecharge le paquet "pilote seul" de VDD (derniere version publiee sur
       GitHub ; retombe sur une version connue si l'API GitHub est injoignable).
    3. Extrait le certificat de signature du pilote (mttvdd.cat) et l'importe
       dans le magasin Editeurs de confiance de la VM (Cert:\LocalMachine\TrustedPublisher),
       pour que Windows fasse confiance au pilote sans Mode test ni desactivation
       de Secure Boot (le pilote est officiellement signe par le projet).
    4. Installe le pilote et cree le peripherique via NefCon (equivalent
       moderne de "devcon install" pour les peripheriques logiciels).

    Necessite que le compte Windows de la VM soit administrateur (import de
    certificat dans le magasin machine + installation de pilote l'exigent),
    et que la VM ait acces a Internet (telechargement depuis GitHub).

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
    $outcome = $null
    try {
        $outcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ScriptBlock {
            # Etape en cours, remontee telle quelle en cas d'echec : sans elle, toutes
            # les pannes se ressemblent ("Acces refuse") alors qu'elles n'ont pas du
            # tout les memes causes ni les memes remedes.
            $step = "verification d'un VDD deja present"

            # PowerShell Direct ouvre une session AVEC le jeton filtre par le controle
            # de compte d'utilisateur quand le compte est LOCAL : le compte a beau etre
            # administrateur, la session n'a pas ses privileges. Or importer un
            # certificat dans le magasin machine et installer un pilote les exigent -
            # d'ou un "Acces refuse" impossible a interpreter sans cette information.
            $isElevated = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)

            $existing = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' }
            if ($existing) {
                return [pscustomobject]@{
                    AlreadyInstalled = $true
                    Success          = $true
                    VddStatus        = $existing.Status.ToString()
                    ErrorMessage     = $null
                }
            }

            # Version connue et testee par le projet lui-meme (utilisee par son propre
            # script d'installation silencieuse) - conservee comme filet de securite si
            # l'API GitHub ci-dessous est injoignable depuis la VM.
            $nefConUrl = "https://github.com/nefarius/nefcon/releases/download/v1.14.0/nefcon_v1.14.0.zip"
            $driverUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/25.7.23/VirtualDisplayDriver-x86.Driver.Only.zip"
            try {
                $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/VirtualDrivers/Virtual-Display-Driver/releases/latest" -UseBasicParsing -TimeoutSec 8
                $asset = $latest.assets | Where-Object { $_.name -match '(?i)^VirtualDisplayDriver-x(86|64)\.Driver\.Only\.zip$' } | Select-Object -First 1
                if ($asset) { $driverUrl = $asset.browser_download_url }
            } catch {
                # Pas grave : on retombe sur l'URL figee ci-dessus.
            }

            $tempDir = Join-Path $env:TEMP "NovaVM-VDDInstall"
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $nefconZip = Join-Path $tempDir "nefcon.zip"
                Invoke-WebRequest -Uri $nefConUrl -OutFile $nefconZip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -Path $nefconZip -DestinationPath $tempDir -Force -ErrorAction Stop
                $nefconExe = Join-Path $tempDir "x64\nefconw.exe"
                if (-not (Test-Path -LiteralPath $nefconExe)) {
                    throw "nefconw.exe introuvable apres extraction de NefCon."
                }

                $driverZip = Join-Path $tempDir "driver.zip"
                Invoke-WebRequest -Uri $driverUrl -OutFile $driverZip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -Path $driverZip -DestinationPath $tempDir -Force -ErrorAction Stop
                $infPath = Join-Path $tempDir "VirtualDisplayDriver\MttVDD.inf"
                $catPath = Join-Path $tempDir "VirtualDisplayDriver\mttvdd.cat"
                if (-not (Test-Path -LiteralPath $infPath) -or -not (Test-Path -LiteralPath $catPath)) {
                    throw "Fichiers du pilote VDD introuvables apres extraction ($infPath)."
                }

                $step = "import du certificat du pilote dans le magasin machine"
                $catBytes = [System.IO.File]::ReadAllBytes($catPath)
                $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
                $certCollection.Import($catBytes)
                foreach ($cert in $certCollection) {
                    $certFile = Join-Path $tempDir "$($cert.Thumbprint).cer"
                    [System.IO.File]::WriteAllBytes($certFile, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
                    Import-Certificate -FilePath $certFile -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" -ErrorAction Stop | Out-Null
                }

                $step = "installation du pilote VDD (NefCon)"
                Push-Location $tempDir
                try {
                    $nefconOutput = & $nefconExe install ".\VirtualDisplayDriver\MttVDD.inf" "Root\MttVDD" 2>&1 | Out-String
                    $nefconExitCode = $LASTEXITCODE
                } finally {
                    Pop-Location
                }

                Start-Sleep -Seconds 8

                $installed = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                    Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' }

                if (-not $installed) {
                    throw "Le peripherique 'Virtual Display Driver' n'apparait pas apres l'installation (code NefCon $nefconExitCode). Sortie : $nefconOutput"
                }

                [pscustomobject]@{
                    AlreadyInstalled = $false
                    Success          = $true
                    VddStatus        = $installed.Status.ToString()
                    ErrorMessage     = $null
                }
            } catch {
                # Le "pourquoi" compte autant que le "quoi" : etape exacte, et si la
                # session invite avait ou non les privileges administrateur reels.
                $detail = "Echec a l'etape : $step. Detail : $($_.Exception.Message)"
                if (-not $isElevated) {
                    $detail += " La session ouverte dans la VM N'A PAS les privileges administrateur reels" +
                        " (jeton filtre par le controle de compte d'utilisateur), ce qui explique un refus d'acces" +
                        " sur l'import de certificat ou l'installation du pilote, meme avec un compte administrateur."
                }
                [pscustomobject]@{
                    AlreadyInstalled = $false
                    Success          = $false
                    VddStatus        = $null
                    IsElevated       = $isElevated
                    FailedStep       = $step
                    ErrorMessage     = $detail
                }
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        throw "Echec de la connexion/installation via PowerShell Direct : $($_.Exception.Message)"
    }

    if (-not $outcome -or -not $outcome.Success) {
        $detail = if ($outcome) { $outcome.ErrorMessage } else { "aucune reponse de la VM." }
        throw "Echec de l'installation automatique de VDD dans la VM : $detail`nVerifiez que le compte Windows utilise est administrateur et que la VM a acces a Internet (telechargement depuis GitHub)."
    }

    $messageLines = @()
    if ($outcome.AlreadyInstalled) {
        $messageLines += "Virtual Display Driver est deja installe dans cette VM (statut : $($outcome.VddStatus))."
    } else {
        $messageLines += "Virtual Display Driver installe automatiquement avec succes (statut : $($outcome.VddStatus))."
        $messageLines += "VDD devient l'ecran principal des son activation, ce qui coupe vmconnect : utilisez 'Desactiver VDD' pour le retrouver, ou Sunshine/Moonlight pour continuer a voir la VM pendant que VDD est actif."
    }
    $messageLines += "Si le pilote reste en erreur, verifiez que 'Microsoft Visual C++ Redistributable' est installe dans la VM (erreur vcruntime140.dll)."

    $result = [ordered]@{
        alreadyInstalled = $outcome.AlreadyInstalled
        vddStatus        = $outcome.VddStatus
        message          = ($messageLines -join "`n")
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
