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
         - POST /api/pin cote Sunshine la valide avec le meme PIN.

       Deux generations d'API cohabitent chez les utilisateurs et se distinguent
       par la presence d'un GET sur /api/pin (voir le detail dans le corps du
       script) : jusqu'a Sunshine 2026.5 le POST se suffit a lui-meme, depuis
       2026.9 il faut d'abord lire le "pairing_id" de la demande en attente.

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

    # Piege du BOM, verifie empiriquement et tres couteux a diagnostiquer.
    #
    # .NET cree l'entree standard d'un processus enfant avec l'encodage de la
    # console ([Console]::InputEncoding) et met AutoFlush a vrai : le simple fait
    # de creer le processus ECRIT DEJA le prefixe de cet encodage dans le tube.
    # Quand la console est en UTF-8 (option "Beta : utiliser UTF-8" de Windows 11,
    # ou terminal qui a fait chcp 65001), ce prefixe est un BOM. curl le prend
    # alors pour le debut du nom de l'option et rejette tout le fichier :
    #   config file option 'user' is unknown
    #   option -K: found an unknown config option
    # Plus aucun appel a l'API Sunshine ne passe, et le message n'evoque ni
    # encodage ni BOM. Ni $OutputEncoding, ni un StreamWriter en UTF-8 sans BOM
    # n'y changent quoi que ce soit (teste) : le prefixe est ecrit avant nous.
    # Seul le basculement de l'encodage de la console avant la creation du
    # processus l'empeche - on le restaure aussitot.
    $previousInputEncoding = $null
    try {
        $previousInputEncoding = [Console]::InputEncoding
        [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch {
        # Pas de console attachee : rien a corriger, l'encodage par defaut ne
        # comporte alors pas de prefixe.
        $previousInputEncoding = $null
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "curl.exe"
    $startInfo.Arguments = ($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    try {
        $curl = [System.Diagnostics.Process]::Start($startInfo)
        $curl.StandardInput.Write($config)
        $curl.StandardInput.Close()

        $raw = $curl.StandardOutput.ReadToEnd()
        $stdErr = $curl.StandardError.ReadToEnd()
        $curl.WaitForExit()
    } catch {
        return [pscustomobject]@{ HttpCode = 0; Body = $null; Error = $_.Exception.Message }
    } finally {
        if ($previousInputEncoding) {
            try { [Console]::InputEncoding = $previousInputEncoding } catch { }
        }
    }

    $marker = $raw.LastIndexOf("|NOVAHTTP=")
    if ($marker -lt 0) {
        $detail = if ($stdErr.Trim()) { $stdErr.Trim() } else { $raw }
        return [pscustomobject]@{ HttpCode = 0; Body = $raw; Error = "Reponse illisible de curl : $detail" }
    }

    $code = 0
    [void][int]::TryParse($raw.Substring($marker + 10).Trim(), [ref]$code)
    return [pscustomobject]@{
        HttpCode = $code
        Body     = $raw.Substring(0, $marker)
        Error    = if ($code -ge 200 -and $code -lt 300) { $null } else { "code HTTP $code" }
    }
}

# Moonlight est-il DEJA appaire avec cet hote ?
#
# On le demande a Moonlight lui-meme plutot qu'a Sunshine : c'est le client qui
# detient le certificat, et c'est lui qui refusera de reappairer. "list" rend 0
# quand l'hote est appaire et joignable, -1 sinon (verifie dans les deux etats).
# On se fie a ce code et non au texte affiche : Moonlight est traduit, son message
# depend de la langue de Windows. Sa sortie standard, elle, est vide dans les deux
# cas - elle ne peut donc pas servir de critere.
function Test-NovaMoonlightPaired {
    param(
        [Parameter(Mandatory)][string]$MoonlightPath,
        [Parameter(Mandatory)][string]$HostAddress
    )

    $outFile = Join-Path $env:TEMP "splyt-moonlight-list.out"
    $errFile = Join-Path $env:TEMP "splyt-moonlight-list.err"
    try {
        # Sorties dirigees vers des FICHIERS et non des tubes : un tube que
        # personne ne vide bloquerait Moonlight des qu'il le remplit, et on ne
        # peut pas le lire tout en surveillant un delai d'attente.
        $process = Start-Process -FilePath $MoonlightPath -ArgumentList "list", $HostAddress `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        # Lire .Handle tout de suite : sans cet acces, PowerShell ne conserve pas
        # le descripteur du processus et .ExitCode revient VIDE apres la fin
        # (piege verifie - c'est ce qui rendait le code de sortie inexploitable).
        $null = $process.Handle

        if (-not $process.WaitForExit(30000)) {
            try { $process.Kill() } catch { }
            return $false
        }
        return ($process.ExitCode -eq 0)
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

# Derniere ligne utile de la sortie de Moonlight, pour expliquer un echec.
# Les avertissements Qt/SDL sont ecartes : ils sont presents a chaque lancement,
# meme quand tout se passe bien, et masqueraient la vraie cause.
function Get-NovaMoonlightFailureReason {
    param([string]$OutFile, [string]$ErrorFile)

    $lines = @()
    foreach ($file in @($ErrorFile, $OutFile)) {
        if ($file -and (Test-Path -LiteralPath $file)) {
            $lines += @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)
        }
    }
    $useful = $lines | Where-Object {
        $_ -and $_.Trim() -and $_ -notmatch 'Qt (Warning|Info)|SDL Info|DPI_AWARENESS|doc\.qt\.io'
    }
    if (-not $useful) { return $null }
    return ($useful | Select-Object -Last 1).Trim()
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

        # --- Ecran virtuel VDD : les modes doivent d'abord EXISTER ------------
        #
        # Le pilote VDD n'expose que les couples resolution/frequence listes dans
        # C:\VirtualDisplayDriver\vdd_settings.xml (chemin lu dans les chaines de
        # MttVDD.dll, aux cotes de l'ancien option.txt). Sans ce fichier il
        # fonctionne sur ses valeurs codees en dur, ou le 120 Hz n'est pas garanti :
        # Sunshine aurait beau demander 120 Hz, Windows refuserait le mode.
        #
        # <g_refresh_rate> s'applique a TOUTES les resolutions listees : une seule
        # declaration par frequence suffit donc a couvrir toute la grille.
        # Cette liste doit rester alignee sur celle proposee par la fenetre de
        # lancement Moonlight (MoonlightLaunchDialogViewModel) : une resolution
        # proposee mais absente d'ici serait simplement refusee par l'invite.
        $vddResolutions = @(
            @{ w = 1280; h = 720 }, @{ w = 1920; h = 1080 }, @{ w = 2560; h = 1440 },
            @{ w = 3440; h = 1440 }, @{ w = 3840; h = 2160 }
        )
        $vddRefreshRates = @(60, 90, 100, 120, 144)

        $xml = New-Object System.Text.StringBuilder
        [void]$xml.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
        [void]$xml.AppendLine('<!-- Genere par SPLYT - modifie a chaque configuration du streaming. -->')
        [void]$xml.AppendLine('<vdd_settings>')
        [void]$xml.AppendLine('  <monitors><count>1</count></monitors>')
        [void]$xml.AppendLine('  <gpu><friendlyname>default</friendlyname></gpu>')
        [void]$xml.AppendLine('  <global>')
        foreach ($rate in $vddRefreshRates) { [void]$xml.AppendLine("    <g_refresh_rate>$rate</g_refresh_rate>") }
        [void]$xml.AppendLine('  </global>')
        [void]$xml.AppendLine('  <resolutions>')
        foreach ($res in $vddResolutions) {
            [void]$xml.AppendLine('    <resolution>')
            [void]$xml.AppendLine("      <width>$($res.w)</width>")
            [void]$xml.AppendLine("      <height>$($res.h)</height>")
            [void]$xml.AppendLine('      <refresh_rate>60</refresh_rate>')
            [void]$xml.AppendLine('    </resolution>')
        }
        [void]$xml.AppendLine('  </resolutions>')
        [void]$xml.AppendLine('</vdd_settings>')

        # Ecriture SANS BOM. "Set-Content -Encoding UTF8" en ajoute un sous
        # PowerShell 5.1, et un BOM en tete d'un fichier de configuration se colle
        # au premier element/cle : Sunshine lisait ainsi une cle nommee
        # "<BOM>csrf_allowed_origins", donc inconnue et silencieusement ignoree
        # (constate dans son journal). Meme precaution ici pour le XML du pilote.
        $vddDir = "C:\VirtualDisplayDriver"
        New-Item -ItemType Directory -Path $vddDir -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $vddDir "vdd_settings.xml"), $xml.ToString(), (New-Object System.Text.UTF8Encoding($false)))

        # Le pilote ne relit son fichier qu'au demarrage du peripherique : sans ce
        # cycle desactivation/activation, la nouvelle grille de modes n'existe pas
        # encore quand Sunshine essaie de l'appliquer.
        $vddDevice = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' } | Select-Object -First 1
        $vddPresent = $null -ne $vddDevice
        if ($vddPresent) {
            try {
                Disable-PnpDevice -InstanceId $vddDevice.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-PnpDevice -InstanceId $vddDevice.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 5
            } catch {
                # Le VDD reste sur ses anciens modes : c'est degrade, pas bloquant.
                $vddPresent = $false
            }
        }

        # --- Identification de l'ecran VDD pour Sunshine ----------------------
        #
        # Sunshine attend dans "output_name" l'identifiant stable de l'ecran
        # (un GUID sous Windows). Il est impossible de l'obtenir depuis ici par les
        # voies habituelles : PowerShell Direct s'execute en session 0, sans bureau,
        # et dxgi-info.exe y renvoie une liste d'ecrans VIDE (verifie - l'adaptateur
        # apparait, la section OUTPUT est vide). Seul un processus de la session
        # interactive voit les ecrans.
        #
        # Sunshine, lui, EST dans cette session : il enumere les ecrans a chaque
        # demarrage et ecrit le resultat en JSON dans son journal. On le redemarre
        # donc pour obtenir un inventaire frais, et on le lit. C'est le seul canal
        # disponible, et il est fiable parce qu'on vient de provoquer l'ecriture.
        $vddDeviceId = $null
        $vddFriendlyName = $null
        if ($vddPresent) {
            Restart-Service -Name "SunshineService" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 10

            $logPath = Join-Path $sunshineDir "config\sunshine.log"
            if (Test-Path -LiteralPath $logPath) {
                $log = Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue
                $marker = $log.LastIndexOf("Currently available display devices:")
                if ($marker -ge 0) {
                    $start = $log.IndexOf('[', $marker)
                    # Fin du tableau JSON : premiere ligne ne contenant que "]".
                    $end = [regex]::Match($log.Substring($start), '(?m)^\]').Index
                    if ($start -ge 0 -and $end -gt 0) {
                        try {
                            $devices = $log.Substring($start, $end + 1) | ConvertFrom-Json
                            # Le VDD se reconnait a son identifiant fabricant EDID "MTT"
                            # (Virtual-Display-Driver), avec le nom convivial en secours.
                            $match = $devices | Where-Object {
                                $_.edid.manufacturer_id -eq 'MTT' -or $_.friendly_name -match 'VDD'
                            } | Select-Object -First 1
                            if ($match) {
                                $vddDeviceId = $match.device_id
                                $vddFriendlyName = $match.friendly_name
                            }
                        } catch {
                            $vddDeviceId = $null
                        }
                    }
                }
            }
        }

        # Cles verifiees dans la documentation officielle Sunshine. On autorise les
        # codecs les plus efficaces ; c'est le client qui choisira ensuite lequel
        # utiliser selon ce que son decodeur sait faire.
        #   hevc_mode/av1_mode = 3 : profil principal + 10 bits/HDR autorises.
        $desired = @{
            "hevc_mode" = "3"
            "av1_mode"  = "3"
        }

        if ($vddDeviceId) {
            # Capture l'ecran VDD et non l'ecran Hyper-V. Les options "dd_" sont
            # celles de la configuration d'affichage de Sunshine (documentation
            # officielle) :
            #   ensure_only_display : pendant la session, le VDD devient le SEUL
            #     ecran de l'invite. C'est ce qui met reellement le bureau, la barre
            #     des taches et les fenetres sur l'ecran diffuse ; se contenter de
            #     l'activer streamerait un bureau vide, tout etant reste sur l'ecran
            #     Hyper-V.
            #   auto : Sunshine applique la resolution et la frequence DEMANDEES PAR
            #     LE CLIENT. C'est la piece qui manquait : SPLYT ne peut pas changer
            #     le mode d'affichage de l'invite depuis l'hote (session 0), mais
            #     Sunshine tourne dans la session interactive et en a le droit.
            #   revert_on_disconnect : l'ecran Hyper-V revient a la fin de la
            #     session. Sans cela, l'invite resterait sur un ecran invisible
            #     depuis la console.
            $desired["output_name"] = $vddDeviceId
            $desired["dd_configuration_option"] = "ensure_only_display"
            $desired["dd_resolution_option"] = "auto"
            $desired["dd_refresh_rate_option"] = "auto"
            $desired["dd_config_revert_on_disconnect"] = "enabled"
            $desired["dd_config_revert_delay"] = "3000"
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
        # Sans BOM, pour la meme raison que le XML du pilote ci-dessus : Sunshine
        # prenait le BOM pour le debut du nom de la premiere cle du fichier.
        [System.IO.File]::WriteAllLines($configPath, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

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

        [ordered]@{
            configPath      = $configPath
            keysApplied     = @($desired.Keys) -join ", "
            vddPresent      = $vddPresent
            vddDeviceId     = $vddDeviceId
            vddFriendlyName = $vddFriendlyName
            vddModes        = "$(@($vddResolutions | ForEach-Object { "$($_.w)x$($_.h)" }) -join ', ') a $($vddRefreshRates -join '/') Hz"
        }
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

    # Deja appaire ? Moonlight refuse de reappairer un hote qu'il connait deja :
    # sa commande "pair" rend la main tout de suite sans jamais contacter
    # Sunshine, et la boucle ci-dessous attendrait une demande qui n'arriverait
    # jamais - on annoncerait un echec sur une configuration pourtant complete
    # (typiquement en relancant la configuration automatique). L'etat est lu par
    # "moonlight list" et non dans un message d'erreur : Moonlight est traduit,
    # son texte depend de la langue de Windows.
    $paired = Test-NovaMoonlightPaired -MoonlightPath $moonlightPath -HostAddress $vmIp
    $alreadyPaired = $paired
    $pairError = $null

    if (-not $paired) {
        $pin = "{0:D4}" -f (Get-Random -Minimum 0 -Maximum 10000)

        # Moonlight reste en attente pendant l'echange : on le lance sans bloquer,
        # puis on valide sa demande cote Sunshine. Sa sortie est capturee pour
        # pouvoir la citer si l'appariement echoue - sans elle, une panne cote
        # client (hote injoignable, port bloque) est indiscernable d'une panne
        # cote serveur.
        $pairOutFile = Join-Path $env:TEMP "splyt-moonlight-pair.out"
        $pairErrFile = Join-Path $env:TEMP "splyt-moonlight-pair.err"
        $pairProcess = Start-Process -FilePath $moonlightPath -ArgumentList "pair", $vmIp, "--pin", $pin `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $pairOutFile -RedirectStandardError $pairErrFile

        for ($attempt = 0; $attempt -lt 30 -and -not $paired; $attempt++) {
            Start-Sleep -Seconds 2

            # Deux generations d'API coexistent chez les utilisateurs, et elles ne
            # s'appellent pas de la meme facon. La difference se lit sur GET
            # /api/pin (verifie empiriquement : 404 = route absente, exactement
            # comme une URL inventee ; 401 = route presente mais authentifiee) :
            #
            #   - jusqu'a 2026.5 : POST { pin, name } suffit. Sunshine valide la
            #     seule demande en attente, aucun identifiant n'est a fournir -
            #     et il n'existe aucun moyen d'en obtenir un.
            #   - depuis 2026.9 : plusieurs demandes peuvent etre en attente. Il
            #     faut GET /api/pin pour lire leur "pairing_id", puis le renvoyer
            #     dans POST { pairing_id, pin, name }.
            #
            # Ne faire que le second cas renvoyait 404 sur toutes les versions
            # anterieures, donc "l'appariement automatique n'a pas abouti" sans
            # qu'aucune demande n'ait jamais ete envoyee.
            $payload = @{ pin = $pin; name = "SPLYT" }

            $pendingResponse = Invoke-NovaSunshineApi -Url "$baseUrl/api/pin" -User $SunshineUser -Password $sunshinePassword
            if ($pendingResponse.HttpCode -eq 200) {
                # L'identifiant fait exactement 32 caracteres hexadecimaux (Sunshine
                # le valide ainsi). On le cherche tel quel dans la reponse brute
                # plutot que de supposer un nom de champ.
                $match = [regex]::Match($pendingResponse.Body, '\b[0-9a-fA-F]{32}\b')
                if (-not $match.Success) {
                    # Moonlight n'a pas encore depose sa demande.
                    $pairError = "aucune demande d'appariement en attente cote Sunshine"
                    continue
                }
                $payload["pairing_id"] = $match.Value
            } elseif ($pendingResponse.HttpCode -ne 404) {
                $pairError = $pendingResponse.Error
                continue
            }

            $postResponse = Invoke-NovaSunshineApi -Url "$baseUrl/api/pin" -User $SunshineUser `
                -Password $sunshinePassword -Method "POST" -JsonBody ($payload | ConvertTo-Json -Compress)

            if ($postResponse.HttpCode -ge 200 -and $postResponse.HttpCode -lt 300) {
                # Sunshine repond 200 meme quand il REFUSE l'appariement (PIN
                # errone, aucune demande en attente) : c'est le champ "status" qui
                # fait foi, pas le code HTTP. Se fier au seul code annoncait un
                # succes alors que rien n'etait appaire.
                if ($postResponse.Body -match '"status"\s*:\s*"?true"?') {
                    $paired = $true
                } else {
                    $pairError = "Sunshine a refuse l'appariement"
                }
            } else {
                $pairError = "$($postResponse.Error) - $($postResponse.Body)"
            }

            # Moonlight a rendu la main sans que rien n'aboutisse : inutile
            # d'attendre les 60 secondes, sa sortie dit pourquoi.
            if (-not $paired -and $pairProcess.HasExited) {
                $moonlightSays = Get-NovaMoonlightFailureReason -OutFile $pairOutFile -ErrorFile $pairErrFile
                if ($moonlightSays) { $pairError = $moonlightSays }
                break
            }
        }

        # Moonlight est arrete DANS TOUS LES CAS, succes compris.
        #
        # "moonlight pair" ne rend pas la main une fois l'appariement accepte : il
        # reste a surveiller l'hote indefiniment. Or il herite du tube de sortie
        # standard de ce script (CreateProcess transmet les descripteurs
        # heritables), donc tant qu'il vit, SPLYT attend la fin d'une sortie qui
        # ne se fermera jamais : l'action entiere reste bloquee, meme apres un
        # appariement parfaitement reussi. On lui laisse quelques secondes pour
        # finir proprement, puis on l'arrete.
        for ($grace = 0; $grace -lt 5 -and -not $pairProcess.HasExited; $grace++) {
            Start-Sleep -Seconds 1
        }
        if (-not $pairProcess.HasExited) {
            try { $pairProcess.Kill() } catch { }
        }
        Remove-Item -LiteralPath $pairOutFile, $pairErrFile -Force -ErrorAction SilentlyContinue
    }

    $result = [ordered]@{
        vmIp            = $vmIp
        sunshineWebUrl  = $baseUrl
        configPath      = $guestOutcome.configPath
        keysApplied     = $guestOutcome.keysApplied
        paired          = $paired
        pairError       = $pairError
        vddCaptured     = [bool]$guestOutcome.vddDeviceId
        vddDeviceId     = $guestOutcome.vddDeviceId
        vddFriendlyName = $guestOutcome.vddFriendlyName
        vddModes        = $guestOutcome.vddModes
        message         = $(
            $capture = if ($guestOutcome.vddDeviceId) {
                " Le streaming utilisera l'ecran virtuel VDD ($($guestOutcome.vddFriendlyName)), a la resolution et a la frequence choisies au lancement."
            } elseif ($guestOutcome.vddPresent) {
                " L'ecran virtuel VDD n'a pas pu etre identifie : le streaming utilisera l'ecran Hyper-V, limite en frequence."
            } else {
                " Aucun ecran virtuel VDD dans cette VM : le streaming utilisera l'ecran Hyper-V, limite en frequence."
            }

            if ($paired -and $alreadyPaired) {
                "Sunshine configure (codecs HEVC/AV1 autorises). Moonlight etait deja apparie avec cette VM : rien a refaire.$capture"
            } elseif ($paired) {
                "Sunshine configure (codecs HEVC/AV1 autorises) et apparie automatiquement avec Moonlight : plus aucun code PIN a saisir.$capture"
            } else {
                "Sunshine est configure, mais l'appariement automatique n'a pas abouti$(if ($pairError) { " ($pairError)" }). Vous pouvez apparier manuellement depuis $baseUrl (identifiant : $SunshineUser).$capture"
            }
        )
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
