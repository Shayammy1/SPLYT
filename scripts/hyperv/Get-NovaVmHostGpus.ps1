<#
.SYNOPSIS
    Liste les GPU physiques de l'hote (donnees REELLES via WMI), avec un
    partitionSupported determine par une vraie verification croisee avec
    Get-VMHostPartitionableGpu (pas suppose vrai par defaut). La VRAM vient du
    registre (Get-NovaRealGpuVramBytes) : Win32_VideoController.AdapterRAM est
    un DWORD 32 bits qui plafonne/deborde pour tout GPU au-dela de ~4 Go
    (verifie : rapporte 4 Go pour un GPU qui en a reellement 24).
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $partitionableGpus = $null
    $partitionCheckError = $null
    try {
        $partitionableGpus = Get-VMHostPartitionableGpu -ErrorAction Stop
    } catch {
        $partitionCheckError = $_.Exception.Message
    }

    # Seuls les GPU reellement branches sur le bus PCI sont retenus.
    #
    # Le filtre par NOM ne suffisait pas : un ecran virtuel installe sur l'hote
    # (Virtual Display Driver, Parsec, DisplayLink, casque de realite virtuelle,
    # session a distance...) apparait dans Win32_VideoController comme n'importe
    # quel adaptateur, et se retrouvait propose dans la liste des GPU de SPLYT.
    # Remonte par un utilisateur : "le GPU-P a tendance a choper les drivers
    # virtuels deja existants de mon PC". Une liste de noms a exclure aurait
    # toujours un train de retard sur le prochain pilote virtuel a la mode.
    #
    # Le bus, lui, ne ment pas : un peripherique d'affichage virtuel est enumere
    # sous ROOT\, SWD\, UMB\ ou USB\, jamais sous PCI\ - et GPU-P exige un vrai
    # GPU PCI. Le critere est donc structurel plutot que nominatif.
    $adapters = Get-CimInstance Win32_VideoController |
        Where-Object { $_.Name -and $_.PNPDeviceID -like 'PCI\*' -and $_.Name -notmatch "Basic Render|Remote Desktop" } |
        ForEach-Object {
            $realVram = Get-NovaRealGpuVramBytes -PnpDeviceId $_.PNPDeviceID

            # Integre ou dedie ? Un GPU integre au processeur est branche sur le bus
            # PCI 0, a la racine ; une carte dediee vit derriere un pont PCIe, donc
            # sur un bus superieur (verifie : bus 3 pour une RX 7900 XTX). Critere
            # structurel, contrairement au nom - "AMD Radeon(TM) Graphics" ne dit
            # pas s'il s'agit d'un iGPU de processeur ou d'une carte.
            #
            # Pourquoi ca compte : sur une machine qui a les deux, partitionner
            # l'iGPU au lieu de la carte donne une VM sans puissance graphique.
            # Remonte par un utilisateur avec un 9900X3D et une RTX 5080, ou le
            # choix automatique tombait sur l'iGPU du processeur.
            #
            # Non lisible = considere comme dedie : mieux vaut ne pas retrograder
            # une vraie carte a cause d'une propriete absente.
            $integrated = $false
            try {
                $bus = (Get-PnpDeviceProperty -InstanceId $_.PNPDeviceID -KeyName 'DEVPKEY_Device_BusNumber' -ErrorAction Stop).Data
                if ($null -ne $bus) { $integrated = ([int]$bus -eq 0) }
            } catch { }

            [ordered]@{
                name               = $_.Name
                vramBytes          = if ($realVram) { $realVram } elseif ($_.AdapterRAM) { [int64]$_.AdapterRAM } else { 0 }
                driverVersion      = $_.DriverVersion
                integrated         = $integrated
                partitionSupported = Test-NovaGpuPartitionable -PnpDeviceId $_.PNPDeviceID -PartitionableGpus $partitionableGpus
                partitionCheckError = $partitionCheckError
            }
        }

    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaJsonArray -InputObject $adapters)
}
