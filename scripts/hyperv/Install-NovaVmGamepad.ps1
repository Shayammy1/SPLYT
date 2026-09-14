<#
.SYNOPSIS
    Installe DANS LA VM la prise en charge des manettes pour le mode jeu, en y
    posant le pilote de manette virtuelle ViGEmBus (projet nefarius/ViGEmBus).

    A quoi ca sert : Moonlight transmet deja l'entree de la manette dans le flux,
    c'est son fonctionnement normal. A l'autre bout, Sunshine doit recreer une
    manette dans l'invite - et pour ca il lui faut un pilote de peripherique
    virtuel, que son propre installeur NE FOURNIT PAS. Verifie sur le paquet
    telecharge par SPLYT : 136 fichiers, aucun .sys/.inf/.cat, et son script de
    configuration n'installe aucun pilote. Sunshine le dit lui-meme quand il
    manque : "libvirtualhid gamepad support is unavailable and ViGEmBus fallback
    is not installed or running".

    ViGEmBus plutot que libvirtualhid, l'autre pilote reconnu par Sunshine :
    ViGEmBus est gratuit et sous licence libre, la ou libvirtualhid renvoie vers
    une page de licence. Il emule une manette Xbox 360 ou une DualShock 4, ce qui
    couvre ce que Windows et les jeux attendent.

    Pas de Mode test ni de Secure Boot a desactiver : le pilote est signe, comme
    le client USB/IP.

    La manette n'a pas besoin d'etre branchee a ce stade, ni meme d'exister :
    c'est une manette VIRTUELLE qui est creee dans la VM au moment du jeu.

    Securite : identifiants lus sur l'ENTREE STANDARD, jamais en argument ni
    dans un journal - voir PowerShellRunner.RunWithCredentialAsync.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Derniere version publiee du projet (novembre 2023). Le depot n'a pas bouge
# depuis, ce qui ne pose pas de probleme ici : le pilote est stable et signe.
# Sert de filet si l'API GitHub est injoignable depuis la VM.
$fallbackUrl = "https://github.com/nefarius/ViGEmBus/releases/download/v1.22.0/ViGEmBus_1.22.0_x64_x86_arm64.exe"

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
    $outcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ArgumentList $fallbackUrl -ScriptBlock {
        param($fallbackUrl)

        # Etape en cours, remontee telle quelle en cas d'echec : sans elle, toutes
        # les pannes se ressemblent alors qu'elles n'ont ni les memes causes ni les
        # memes remedes (meme lecon que pour le pilote d'ecran virtuel).
        $step = "verification d'une installation existante"

        # Le pilote s'enregistre comme service noyau. Le chercher la plutot que par
        # Get-PnpDevice : tant qu'aucune manette virtuelle n'est creee, aucun
        # peripherique n'est visible, alors que le service existe des l'installation.
        $service = Get-Service -Name "ViGEmBus" -ErrorAction SilentlyContinue
        if ($service) {
            return [pscustomobject]@{
                AlreadyInstalled  = $true
                Success           = $true
                DriverState       = $service.Status.ToString()
                SunshineRestarted = $false
                ErrorMessage      = $null
                Step              = $null
            }
        }

        $tempDir = Join-Path $env:TEMP "NovaVM-Gamepad"
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $step = "recherche de la derniere version de ViGEmBus"
            $url = $fallbackUrl
            try {
                $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/nefarius/ViGEmBus/releases/latest" -UseBasicParsing -TimeoutSec 10
                $asset = $latest.assets | Where-Object { $_.name -match '(?i)^ViGEmBus_.*\.exe$' } | Select-Object -First 1
                if ($asset) { $url = $asset.browser_download_url }
            } catch {
                # Pas grave : on retombe sur l'URL figee.
            }

            $step = "telechargement du pilote depuis GitHub (necessite un acces internet DANS la VM)"
            $installer = Join-Path $tempDir "ViGEmBus.exe"
            Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -ErrorAction Stop

            $step = "installation silencieuse du pilote"
            # Paquet WiX : /quiet pour ne rien afficher, /norestart parce qu'un
            # redemarrage surprise de la VM serait pire que le probleme qu'on
            # resout. Le pilote est utilisable sans redemarrer.
            $p = Start-Process -FilePath $installer -ArgumentList "/quiet", "/norestart" -Wait -PassThru
            # 3010 = installe, un redemarrage serait souhaitable. Ce n'est pas un echec.
            if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
                throw "L'installeur a rendu le code $($p.ExitCode)."
            }

            $step = "verification du pilote installe"
            $service = Get-Service -Name "ViGEmBus" -ErrorAction SilentlyContinue
            if (-not $service) {
                throw "Le service ViGEmBus est absent apres l'installation."
            }
            if ($service.Status -ne 'Running') {
                try { Start-Service -Name "ViGEmBus" -ErrorAction Stop } catch { }
                $service = Get-Service -Name "ViGEmBus" -ErrorAction SilentlyContinue
            }

            # Sunshine interroge le pilote au demarrage de son service : sans ce
            # redemarrage, la manette ne serait vue qu'a la prochaine relance de la
            # VM. Best-effort, et seulement si le service existe - s'il n'est pas
            # la, c'est que Sunshine n'est pas encore installe, ce qui se dit
            # ailleurs dans l'interface.
            $step = "redemarrage du service Sunshine"
            $sunshine = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
            $sunshineRestarted = $false
            if ($sunshine -and $sunshine.Status -eq 'Running') {
                try {
                    Restart-Service -Name "SunshineService" -Force -ErrorAction Stop
                    $sunshineRestarted = $true
                } catch { }
            }

            return [pscustomobject]@{
                AlreadyInstalled  = $false
                Success           = $true
                DriverState       = $(if ($service) { $service.Status.ToString() } else { "inconnu" })
                SunshineRestarted = $sunshineRestarted
                ErrorMessage      = $null
                Step              = $null
            }
        } catch {
            return [pscustomobject]@{
                AlreadyInstalled  = $false
                Success           = $false
                DriverState       = $null
                SunshineRestarted = $false
                ErrorMessage      = $_.Exception.Message
                Step              = $step
            }
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $outcome.Success) {
        throw "Echec a l'etape '$($outcome.Step)' dans la VM : $($outcome.ErrorMessage)"
    }

    $message = if ($outcome.AlreadyInstalled) {
        "La prise en charge des manettes etait deja installee dans cette VM (pilote $($outcome.DriverState))."
    } elseif ($outcome.SunshineRestarted) {
        "Prise en charge des manettes installee (pilote $($outcome.DriverState)), Sunshine redemarre. Branchez votre manette sur cet ordinateur et lancez le mode jeu."
    } else {
        "Prise en charge des manettes installee (pilote $($outcome.DriverState)). Branchez votre manette sur cet ordinateur et lancez le mode jeu."
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        alreadyInstalled = [bool]$outcome.AlreadyInstalled
        driverState      = "$($outcome.DriverState)"
        message          = $message
    } | ConvertTo-Json -Compress)
}
