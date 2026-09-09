<#
.SYNOPSIS
    Configure le streaming de bout en bout pour la meilleure qualite possible sur un
    lien LOCAL, et apparie Sunshine (dans la VM) avec Moonlight (sur l'hote) SANS que
    l'utilisateur ait a taper de code PIN.

    Deux moities, volontairement traitees differemment :

    1. Cote SUNSHINE (dans la VM) - par PowerShell Direct, comme le reste des actions
       invite : ecriture des reglages dans sunshine.conf, definition des identifiants
       de son interface web (necessaires a l'etape 2), redemarrage du service.
       Les seules cles ecrites sont celles verifiees dans la documentation officielle
       (hevc_mode, av1_mode) : une cle inventee serait ignoree en silence, ce qui est
       le pire des resultats.

    2. Cote APPARIEMENT - par l'API web de Sunshine depuis l'hote. Le code PIN n'est
       pas une formalite : c'est l'echange qui etablit les certificats entre client et
       serveur. Rien n'oblige en revanche a ce qu'un HUMAIN le tape, puisque SPLYT
       controle les deux bouts. Le protocole reste donc intact, on retire seulement
       l'humain de la boucle :
         - SPLYT tire un PIN au hasard ;
         - "moonlight pair <ip> --pin <pin>" declenche la demande cote client ;
         - GET /api/pin cote Sunshine donne le pairing_id de la demande en attente ;
         - POST /api/pin le valide avec le meme PIN.

    La QUALITE elle-meme (debit, frequence, resolution, 4:4:4) ne se regle pas ici :
    c'est le client qui la demande a chaque session. Voir Start-NovaVmMoonlight.ps1.

    Securite : identifiants Windows de la VM lus sur l'ENTREE STANDARD uniquement
    (jamais en argument, jamais journalises) - voir RunWithCredentialAsync cote C#.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    # Identifiants de l'interface web de Sunshine, crees/reinitialises par ce script.
    # Ce ne sont PAS les identifiants Windows de la VM.
    [string]$SunshineUser = "splyt"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Appelle l'API web de Sunshine via curl.exe, et NON via Invoke-RestMethod.
#
# Raison verifiee empiriquement (trace curl -v a l'appui) : Sunshine demande une
# RENEGOCIATION TLS en cours de connexion. curl la gere ; la pile HTTP du .NET
# Framework, sur laquelle repose Invoke-RestMethod en PowerShell 5.1, ne sait pas
# la gerer et coupe la connexion avec "La connexion sous-jacente a ete fermee : une
# erreur inattendue s'est produite lors de l'envoi". Ce message ressemble a s'y
# meprendre a un pare-feu, a un service arrete ou a une mauvaise version de TLS -
# ce n'est aucun des trois, et forcer TLS 1.2 ou 1.3 n'y change rien (teste).
# curl.exe est livre avec Windows depuis la version 1803, aucune dependance ajoutee.
#
# Les identifiants passent par un fichier de configuration lu sur l'ENTREE STANDARD
# (-K -), jamais en argument : un argument de processus est lisible par n'importe
# quel autre processus de la machine. Le mot de passe est tire par SPLYT dans
# [0-9A-Za-z] uniquement, donc sans caractere a echapper dans ce format.
function Invoke-NovaSunshineApi {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Password,
        [string]$Method = "GET",
        [string]$JsonBody
    )

    $arguments = @("-K", "-", "-s", "-o", "-", "-w", "|NOVAHTTP=%{http_code}", "--max-time", "20", $Url)
    if ($Method -ne "GET") { $arguments += @("-X", $Method) }
    if ($JsonBody) { $arguments += @("-H", "Content-Type: application/json", "-d", $JsonBody) }

    # "insecure" : Sunshine se presente avec un certificat auto-signe, ce qui est
    # attendu, et la connexion ne quitte pas la machine.
    $config = "user = `"${User}:${Password}`"`ninsecure`n"

    try {
        $raw = ($config | & curl.exe @arguments 2>&1 | Out-String)
    } catch {
        return [pscustomobject]@{ HttpCode = 0; Body = $null; Error = $_.Exception.Message }
    }

    $marker = $raw.LastIndexOf("|NOVAHTTP=")
    if ($marker -lt 0) {
        return [pscustomobject]@{ HttpCode = 0; Body = $raw; Error = "Reponse illisible de curl : $raw" }
    }

    $code = 0
    [void][int]::TryParse($raw.Substring($marker + 10).Trim(), [ref]$code)
    return [pscustomobject]@{
        HttpCode = $code
        Body     = $raw.Substring(0, $marker)
        Error    = if ($code -ge 200 -and $code -lt 300) { $null } else { "code HTTP $code" }
    }
}

Invoke-NovaAction {
    $username = [Console]::In.ReadLine()
    $passwordPlain = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($passwordPlain)) {
        throw "Identifiants manquants (nom d'utilisateur ou mot de passe vide)."
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour configurer le streaming (PowerShell Direct)."
    }

    $moonlightPath = Get-NovaMoonlightPath
    if (-not $moonlightPath) {
        throw "Moonlight est introuvable sur cet ordinateur. Installez-le d'abord (action 'Preparer le streaming')."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    # Mot de passe de l'interface web de Sunshine : tire au hasard et jamais reutilise
    # d'un mot de passe de l'utilisateur. Il ne sert qu'a cette API locale.
    $sunshinePassword = -join ((1..24) | ForEach-Object { [char](Get-Random -InputObject (@(48..57) + @(65..90) + @(97..122))) })

    Write-NovaProgress "Configuration de Sunshine dans la VM"
    $guestOutcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ArgumentList $SunshineUser, $sunshinePassword -ScriptBlock {
        param($WebUser, $WebPassword)

        $sunshineDir = "C:\Program Files\Sunshine"
        $configPath = Join-Path $sunshineDir "config\sunshine.conf"
        $exePath = Join-Path $sunshineDir "sunshine.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            throw "Sunshine n'est pas installe dans cette VM ($exePath introuvable)."
        }

        # Cles verifiees dans la documentation officielle Sunshine. On autorise les
        # codecs les plus efficaces ; c'est le client qui choisira ensuite lequel
        # utiliser selon ce que son decodeur sait faire.
        #   hevc_mode/av1_mode = 3 : profil principal + 10 bits/HDR autorises.
        $desired = @{
            "hevc_mode" = "3"
            "av1_mode"  = "3"
        }

        $lines = @()
        if (Test-Path -LiteralPath $configPath) {
            $lines = @(Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue)
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        }

        # Remplace la cle si elle existe deja, sinon l'ajoute : ne jamais reecrire le
        # fichier entier, il contient aussi csrf_allowed_origins (voir
        # Install-NovaVmSunshineViaCredential.ps1) et les reglages de l'utilisateur.
        foreach ($key in $desired.Keys) {
            $replaced = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "^\s*$key\s*=") {
                    $lines[$i] = "$key = $($desired[$key])"
                    $replaced = $true
                    break
                }
            }
            if (-not $replaced) { $lines += "$key = $($desired[$key])" }
        }
        Set-Content -LiteralPath $configPath -Value $lines -Encoding UTF8

        # Identifiants de l'interface web : indispensables pour que l'hote puisse
        # valider l'appariement par l'API. Les (re)definir est sans effet de bord :
        # Sunshine n'a pas d'autre usage de ce compte.
        #
        # Ecart assume a la regle du projet "jamais de secret en argument de
        # ligne de commande" : "sunshine.exe --creds" n'offre aucune entree
        # standard, c'est sa seule interface non interactive. Le secret concerne
        # est tire au hasard par SPLYT, ne sert qu'a cette API locale, et n'est
        # visible que depuis l'interieur de cette VM - contrairement au mot de
        # passe Windows de l'utilisateur, lui toujours passe par stdin.
        $credProcess = Start-Process -FilePath $exePath -ArgumentList "--creds", $WebUser, $WebPassword `
            -Wait -PassThru -WindowStyle Hidden
        if ($credProcess.ExitCode -ne 0) {
            throw "Sunshine a refuse de definir les identifiants de son interface web (code $($credProcess.ExitCode))."
        }

        Restart-Service -Name "SunshineService" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5

        [ordered]@{ configPath = $configPath; keysApplied = @($desired.Keys) -join ", " }
    }

    # --- Appariement automatique -------------------------------------------
    Write-NovaProgress "Recherche de l'adresse IP de la VM"
    $vmIp = $null
    for ($attempt = 0; $attempt -lt 20 -and -not $vmIp; $attempt++) {
        $vmIp = Get-NovaVmIpAddress -Name $Name
        if (-not $vmIp) { Start-Sleep -Seconds 3 }
    }
    if (-not $vmIp) {
        throw "Impossible d'obtenir l'adresse IP de la VM (services d'integration Hyper-V). Sunshine est configure, mais l'appariement automatique n'a pas pu demarrer."
    }

    $baseUrl = "https://${vmIp}:47990"

    # Deux tests distincts, et surtout PAS un seul : /api/configLocale ne demande
    # aucune authentification (voir la documentation de l'API), il repond donc des
    # que Sunshine ecoute. Sonder directement un endpoint authentifie confondait
    # deux pannes tres differentes - "Sunshine n'est pas demarre" et "mes
    # identifiants sont refuses" - en un seul "n'a pas repondu" inexploitable.
    Write-NovaProgress "Attente de l'interface de Sunshine"
    $listening = $false
    $lastError = $null
    for ($attempt = 0; $attempt -lt 30 -and -not $listening; $attempt++) {
        $probe = Invoke-NovaSunshineApi -Url "$baseUrl/api/configLocale" -User $SunshineUser -Password $sunshinePassword
        if ($probe.HttpCode -eq 200) {
            $listening = $true
        } else {
            $lastError = $probe.Error
            Start-Sleep -Seconds 2
        }
    }
    if (-not $listening) {
        throw "Sunshine n'ecoute pas sur $baseUrl (derniere erreur : $lastError). Verifiez qu'il est bien demarre dans la VM, et que le pare-feu de la VM autorise le port 47990."
    }

    Write-NovaProgress "Verification des identifiants de l'interface Sunshine"
    $authProbe = Invoke-NovaSunshineApi -Url "$baseUrl/api/config" -User $SunshineUser -Password $sunshinePassword
    if ($authProbe.HttpCode -ne 200) {
        throw "Sunshine repond sur $baseUrl mais refuse les identifiants definis par SPLYT (code $($authProbe.HttpCode)). L'appariement automatique est impossible ; appariez manuellement depuis cette adresse."
    }

    Write-NovaProgress "Appariement de Moonlight avec Sunshine"
    $pin = "{0:D4}" -f (Get-Random -Minimum 0 -Maximum 10000)

    # Moonlight reste en attente pendant l'echange : on le lance sans bloquer,
    # puis on valide sa demande cote Sunshine.
    $pairProcess = Start-Process -FilePath $moonlightPath -ArgumentList "pair", $vmIp, "--pin", $pin `
        -PassThru -WindowStyle Hidden

    $paired = $false
    $pairError = $null
    for ($attempt = 0; $attempt -lt 30 -and -not $paired; $attempt++) {
        Start-Sleep -Seconds 2
        $pendingResponse = Invoke-NovaSunshineApi -Url "$baseUrl/api/pin" -User $SunshineUser -Password $sunshinePassword
        if ($pendingResponse.HttpCode -ne 200 -or -not $pendingResponse.Body) {
            $pairError = $pendingResponse.Error
            continue
        }

        # L'identifiant d'appariement fait exactement 32 caracteres hexadecimaux
        # (verifie dans le source de Sunshine, qui le valide ainsi). On le cherche
        # tel quel dans la reponse brute plutot que de supposer un nom de champ :
        # la forme de cette reponse a change selon les versions.
        $pairingId = $null
        $match = [regex]::Match($pendingResponse.Body, '\b[0-9a-fA-F]{32}\b')
        if ($match.Success) { $pairingId = $match.Value }
        if (-not $pairingId) { continue }

        $body = @{ pairing_id = $pairingId; pin = $pin; name = "SPLYT" } | ConvertTo-Json -Compress
        $postResponse = Invoke-NovaSunshineApi -Url "$baseUrl/api/pin" -User $SunshineUser `
            -Password $sunshinePassword -Method "POST" -JsonBody $body
        if ($postResponse.HttpCode -ge 200 -and $postResponse.HttpCode -lt 300) {
            $paired = $true
        } else {
            $pairError = "$($postResponse.Error) - $($postResponse.Body)"
        }
    }

    if (-not $paired -and -not $pairProcess.HasExited) {
        try { $pairProcess.Kill() } catch { }
    }

    $result = [ordered]@{
        vmIp            = $vmIp
        sunshineWebUrl  = $baseUrl
        configPath      = $guestOutcome.configPath
        keysApplied     = $guestOutcome.keysApplied
        paired          = $paired
        pairError       = $pairError
        message         = if ($paired) {
            "Sunshine configure (codecs HEVC/AV1 autorises) et apparie automatiquement avec Moonlight : plus aucun code PIN a saisir. Utilisez 'Lancer avec Moonlight' pour demarrer une session."
        } else {
            "Sunshine est configure, mais l'appariement automatique n'a pas abouti$(if ($pairError) { " ($pairError)" }). Vous pouvez apparier manuellement depuis $baseUrl (identifiant : $SunshineUser)."
        }
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
