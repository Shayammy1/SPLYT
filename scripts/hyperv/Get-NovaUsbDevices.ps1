<#
.SYNOPSIS
    Liste les peripheriques USB de l'hote, tels que le serveur USB/IP les voit,
    pour que l'utilisateur puisse en choisir un a confier a une VM.

    Ne demande aucune elevation : lister est une lecture. Seuls le partage et le
    rattachement en exigent une.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $usbipd = Get-NovaUsbipdPath
    if (-not $usbipd) {
        Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
            serverInstalled = $false
            devices         = @()
        } | ConvertTo-Json -Compress -Depth 4)
        return
    }

    # "usbipd state" rend du JSON, contrairement a "usbipd list" dont la sortie
    # est un tableau de texte aligne, cale sur la langue de l'utilisateur.
    $raw = & $usbipd state 2>&1 | Out-String
    $state = $null
    try { $state = $raw | ConvertFrom-Json } catch {
        throw "Reponse illisible du serveur USB/IP : $($raw.Trim())"
    }

    $devices = @()
    foreach ($d in $state.Devices) {
        # Un peripherique debranche reste liste s'il a ete partage un jour : sans
        # BusId il n'est branche nulle part, donc rien a en faire ici.
        if (-not $d.BusId) { continue }

        # Distinguer ce qui est plausible comme souris/clavier aide a choisir : la
        # liste brute melange webcams, cles USB et cartes son.
        $description = "$($d.Description)"
        $isInput = $description -match 'entr|input|HID|souris|mouse|clavier|keyboard'

        # Les champs absents reviennent en chaine VIDE et non en $null : tester la
        # nullite marquerait tous les peripheriques comme partages et rattaches.
        $clientIp = "$($d.ClientIPAddress)"
        $persisted = "$($d.PersistedGuid)"

        $devices += [pscustomobject]@{
            busId       = "$($d.BusId)"
            instanceId  = "$($d.InstanceId)"
            description = $description
            shared      = (-not [string]::IsNullOrWhiteSpace($persisted))
            attached    = (-not [string]::IsNullOrWhiteSpace($clientIp))
            clientIp    = $clientIp
            likelyInput = [bool]$isInput
        }
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        serverInstalled = $true
        devices         = @($devices)
    } | ConvertTo-Json -Compress -Depth 4)
}
