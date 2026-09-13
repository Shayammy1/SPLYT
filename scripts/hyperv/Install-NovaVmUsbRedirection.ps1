<#
.SYNOPSIS
    Installe sur l'HOTE le serveur USB/IP (usbipd-win), qui permet de confier un
    peripherique USB a une VM.

    A quoi ca sert : Windows fond toutes les souris en un seul curseur et tous
    les claviers en une seule frappe. Tant qu'un peripherique est vu par l'hote,
    il pilote l'hote - aucun reglage de Moonlight, de Sunshine ou de SPLYT n'y
    change rien, parce que le tri ne se fait pas a ce niveau. La seule facon
    d'avoir une souris pour l'hote et une autre pour la VM est de RETIRER la
    seconde de l'hote et de la donner a l'invite, ce que fait USB/IP.

    Ce script ne s'occupe que de la moitie "hote". Le client s'installe dans la
    VM (voir Install-NovaVmUsbGuest.ps1), et le choix du peripherique vient
    ensuite (Set-NovaUsbShare.ps1 + Set-NovaVmUsbAttach.ps1).

    Demande l'elevation : installer un service et son pilote de filtre USB
    l'exige. Aucun peripherique n'a besoin d'etre branche a ce stade.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $usbipd = Get-NovaUsbipdPath
    if ($usbipd) {
        $version = (& $usbipd --version 2>&1 | Select-Object -First 1)
        Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
            installed = $true
            path      = $usbipd
            version   = "$version"
            message   = "Le serveur USB/IP est deja installe sur cet ordinateur."
        } | ConvertTo-Json -Compress)
        return
    }

    Write-NovaProgress "Installation du serveur USB/IP sur l'hote"

    # winget plutot qu'un telechargement direct : c'est la source officielle du
    # projet (dorssel/usbipd-win), la signature est verifiee par winget, et les
    # mises a jour suivront le meme canal.
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget est introuvable sur cet ordinateur. Installez 'App Installer' depuis le Microsoft Store, puis relancez."
    }

    $output = & winget install --id dorssel.usbipd-win --exact --silent `
        --accept-source-agreements --accept-package-agreements 2>&1 | Out-String

    $usbipd = Get-NovaUsbipdPath
    if (-not $usbipd) {
        throw "L'installation du serveur USB/IP a echoue. Detail winget : $($output.Trim())"
    }

    $version = (& $usbipd --version 2>&1 | Select-Object -First 1)
    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        installed = $true
        path      = $usbipd
        version   = "$version"
        message   = "Serveur USB/IP installe sur l'hote."
    } | ConvertTo-Json -Compress)
}
