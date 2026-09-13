<#
.SYNOPSIS
    Processus detache lance par Start-NovaVm.ps1 quand une ISO est montee :
    surveille le heartbeat Hyper-V (actif uniquement une fois Windows demarre
    normalement, donc apres la fin d'une installation) puis remet le disque
    dur en premier peripherique de demarrage, pour eviter que les demarrages
    ulterieurs ne relancent l'installeur depuis l'ISO.

    Quand l'installation est automatique (unattendPending dans les preferences),
    ce script fait en plus deux choses dont la console se chargeait jusqu'ici -
    et qu'il faut bien que quelqu'un fasse, puisque cette fois aucune console
    n'est ouverte :
      - passer l'invite firmware "Press any key to boot from CD or DVD..." via
        le clavier synthetique WMI (Msvm_Keyboard) ;
      - publier un avancement REEL, deduit de ce qui est effectivement ecrit
        dans le disque virtuel, pour la barre de progression de SPLYT.

    Tourne independamment de l'appli GUI (Start-Process -WindowStyle Hidden) :
    une installation Windows peut prendre longtemps, l'appli peut etre fermee
    entre-temps.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "NovaVm.Unattend.psm1") -Force

$unattend = [bool](Get-NovaVmPreferences -Name $Name).unattendPending

# Taille (octets) que le disque virtuel a prise, en net, une fois Windows 11
# installe. Ne sert QU'A convertir une progression d'ecriture en pourcentage :
# la fin reelle de l'installation, c'est le heartbeat, jamais cette valeur.
$installedSizeBytes = 13GB

function Get-NovaVmDiskBytes {
    param([Parameter(Mandatory)][string]$VmName)
    $hd = Get-VMHardDiskDrive -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $hd) { return 0 }
    try { return [int64](Get-VHD -Path $hd.Path -ErrorAction Stop).FileSize } catch { return 0 }
}

function Set-NovaUnattendProgress {
    param([string]$Stage, [int]$Percent)
    if (-not $unattend) { return }
    try { Save-NovaVmPreferences -Name $Name -UnattendStage $Stage -UnattendPercent $Percent } catch { }
}

# Envoie "une touche" a l'invite de demarrage firmware. Le clavier synthetique
# doit etre RELU a chaque envoi : l'objet rendu par GetRelated est un
# instantane, et le reutiliser d'une iteration a l'autre fait echouer TypeKey
# silencieusement (verifie : la premiere tentative passait, jamais les
# suivantes). Ce chemin ne marche que SANS adaptateur GPU-P attache, ce qui est
# toujours le cas pendant une installation - GPU-P n'est configure qu'apres.
function Send-NovaBootKeyBurst {
    param([Parameter(Mandatory)][string]$VmName, [int]$Seconds = 30)
    $filter = "ElementName='" + ($VmName -replace "'", "''") + "'"
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $cs = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem `
                -Filter $filter -ErrorAction Stop
            $kb = $cs | ForEach-Object { $_.GetRelated("Msvm_Keyboard") } | Select-Object -First 1
            if ($kb) { $null = $kb.TypeKey(0x20) }   # VK_SPACE, comme la console
        } catch { }
        Start-Sleep -Milliseconds 250
    }
}

if ($unattend) {
    Set-NovaUnattendProgress -Stage "starting" -Percent 2

    # Ce script est lance AVANT Start-VM (voir Start-NovaVm.ps1) : taper dans une
    # machine encore eteinte ne menerait nulle part.
    $startDeadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $startDeadline) {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
        if (-not $vm) { exit }
        if ($vm.State -eq 'Running') { break }
        Start-Sleep -Milliseconds 500
    }

    Set-NovaUnattendProgress -Stage "boot" -Percent 5
    Send-NovaBootKeyBurst -VmName $Name
    Set-NovaUnattendProgress -Stage "copy" -Percent 8
}

$deadline = (Get-Date).AddHours(3)
$baselineBytes = -1

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15

    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $vm) { exit }                       # VM supprimee entre-temps
    if ($vm.State -ne 'Running') { continue }    # eteinte/en pause : on continue d'attendre

    # Progression reelle : le disque virtuel grossit au fur et a mesure que
    # l'installeur y ecrit. On part de sa taille au premier passage (un VHDX
    # dynamique n'est jamais vide, et un point de controle automatique change
    # encore la donne) pour que 0 % soit bien le debut de la copie et pas
    # l'en-tete du fichier. Plafonne a 95 % : pendant la derniere phase
    # (personnalisation, creation du compte) plus rien ne grossit, seul le
    # heartbeat dira que c'est fini.
    if ($unattend) {
        $bytes = Get-NovaVmDiskBytes -VmName $Name
        if ($baselineBytes -lt 0) { $baselineBytes = $bytes }
        $written = $bytes - $baselineBytes
        if ($written -lt 0) { $written = 0 }
        $percent = 8 + [int](87.0 * $written / $installedSizeBytes)
        if ($percent -gt 95) { $percent = 95 }
        $stage = if ($percent -ge 90) { "configure" } else { "copy" }
        Set-NovaUnattendProgress -Stage $stage -Percent $percent
    }

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

        # L'ISO du fichier de reponses a fait son office : elle porte le mot de
        # passe du compte Windows, sans autre protection qu'un encodage
        # reversible, et n'a plus aucune raison de rester montee ni sur le disque.
        try { Remove-NovaUnattendIso -VmName $Name } catch { }

        # Memorise que Windows est installe : c'est ce qui declenche cote GUI la
        # proposition de configuration en un clic (bouton "SPLYT") et rend ce
        # bouton disponible ensuite dans l'onglet Ressources. Lever
        # unattendPending dans le meme mouvement rend la VM a l'interface : la
        # console redevient ouvrable, les onglets reapparaissent et la barre de
        # progression laisse la place.
        try {
            Save-NovaVmPreferences -Name $Name -OsInstalled "true" `
                -UnattendPending "false" -UnattendStage "done" -UnattendPercent 100
        } catch { }
        exit
    }
}

# Delai depasse sans jamais voir de heartbeat : on rend quand meme la VM a
# l'utilisateur plutot que de la laisser cachee derriere une barre qui
# n'avancera plus. A lui d'aller voir dans la console, redevenue accessible,
# ce qui s'est passe.
if ($unattend) {
    try { Save-NovaVmPreferences -Name $Name -UnattendPending "false" -UnattendStage "timeout" } catch { }
}
