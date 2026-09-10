<#
.SYNOPSIS
    Arrete une VRAIE VM Hyper-V.

    -Force "false" (par defaut) : arret normal, via le service d'integration
    Arret (Shutdown), equivalent a demander a Windows de s'eteindre proprement
    depuis le menu Demarrer. Necessite ce service d'integration actif dans la
    VM - si absent/non reactif, cette commande echoue clairement plutot que
    de silencieusement forcer l'arret.

    -Force "true" : coupure franche (Stop-VM -TurnOff), equivalent a rester
    appuye sur le bouton d'alimentation. A utiliser si l'arret normal ne
    repond pas.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Force = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# PowerShell ne convertit pas la chaine "true"/"false" recue en ligne de commande
# (via -File) vers [bool] automatiquement - d'ou un [string] ici, converti a la main.
$forceBool = $Force -eq "true"

# Termine proprement la session de streaming avant d'eteindre la VM.
#
# Couper la VM sous une session Moonlight active laisse deux restes : cote invite,
# Sunshine n'a jamais recu de fin de session ; cote hote, la fenetre Moonlight
# survit a l'arret et continue de croire qu'une session est en cours. C'est ce
# reste-la qu'on retrouve au rebranchement suivant, sous la forme d'une session
# deja ouverte.
#
# On demande donc d'abord a Moonlight de rendre l'application ("quit"), ce qui
# fait proprement retomber la session cote Sunshine - y compris le retour a
# l'ecran d'affichage d'origine - PUIS on ferme ce qui resterait ouvert.
function Stop-NovaMoonlightSession {
    param([Parameter(Mandatory)][string]$Name)

    $moonlightPath = Get-NovaMoonlightPath
    if (-not $moonlightPath) { return }
    if (-not (Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue)) { return }

    $vmIp = Get-NovaVmIpAddress -Name $Name
    if ($vmIp) {
        try {
            $outFile = Join-Path $env:TEMP "splyt-moonlight-quit.out"
            $errFile = Join-Path $env:TEMP "splyt-moonlight-quit.err"
            $quit = Start-Process -FilePath $moonlightPath -ArgumentList "quit", $vmIp `
                -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile
            if (-not $quit.WaitForExit(20000)) { try { $quit.Kill() } catch { } }
            Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
        } catch {
            # Best-effort : l'arret de la VM ne doit jamais echouer a cause de ca.
        }
    }

    # "quit" rend la main des que Sunshine a repris l'application, mais la fenetre
    # de streaming, elle, ne se ferme pas toujours d'elle-meme - et apres une
    # coupure elle reste carrement affichee sur une erreur. On la ferme.
    for ($wait = 0; $wait -lt 5; $wait++) {
        if (-not (Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Seconds 1
    }
    Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.CloseMainWindow() | Out-Null } catch { }
    }
    Start-Sleep -Seconds 2
    Get-Process -Name "Moonlight" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch { }
    }
}

Invoke-NovaAction {
    Write-NovaProgress "Fermeture de la session de streaming"
    Stop-NovaMoonlightSession -Name $Name

    if ($forceBool) {
        Stop-VM -Name $Name -TurnOff -Force -ErrorAction Stop
    } else {
        try {
            Stop-VM -Name $Name -Force -ErrorAction Stop
        } catch {
            throw "Echec de l'arret normal (le service d'integration Arret n'est peut-etre pas actif dans la VM) : $($_.Exception.Message). Utilisez l'arret force a la place."
        }
    }

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
