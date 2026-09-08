<#
.SYNOPSIS
    Processus detache lance par Start-NovaVm.ps1 quand une ISO est montee :
    surveille le heartbeat Hyper-V (actif uniquement une fois Windows demarre
    normalement, donc apres la fin d'une installation) puis remet le disque
    dur en premier peripherique de demarrage, pour eviter que les demarrages
    ulterieurs ne relancent l'installeur depuis l'ISO.

    Tourne independamment de l'appli GUI (Start-Process -WindowStyle Hidden) :
    une installation Windows peut prendre longtemps, l'appli peut etre fermee
    entre-temps.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

$deadline = (Get-Date).AddHours(3)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15

    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $vm) { exit }                      # VM supprimee entre-temps
    if ($vm.State -ne 'Running') { continue }    # eteinte/en pause : on continue d'attendre

    # Test-NovaVmHeartbeatOk et pas "-Name Heartbeat" : ce nom est traduit par
    # Windows ("Pulsation" en francais), donc le filtre par nom ne trouvait jamais
    # rien sur un Windows non anglais - et ce script ne remettait donc jamais le
    # disque dur en premier peripherique de demarrage.
    if (Test-NovaVmHeartbeatOk -Name $Name) {
        # Heartbeat actif = Windows a demarre normalement (donc l'installation
        # est terminee) : on remet le disque dur en premier au boot.
        $hardDrive = Get-VMHardDiskDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hardDrive) {
            try { Set-VMFirmware -VMName $Name -FirstBootDevice $hardDrive -ErrorAction Stop } catch { }
        }

        # Memorise que Windows est installe : c'est ce qui declenche cote GUI la
        # proposition de configuration en un clic (bouton "SPLYT") et rend ce
        # bouton disponible ensuite dans l'onglet Ressources.
        try { Save-NovaVmPreferences -Name $Name -OsInstalled "true" } catch { }
        exit
    }
}
