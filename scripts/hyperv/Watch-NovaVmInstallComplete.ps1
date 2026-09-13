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

# Vrai quand l'invite a publie le drapeau pose par la derniere commande de
# premiere ouverture de session du fichier de reponses (voir
# Get-NovaUnattendPrivacyCommands). Contrairement au heartbeat, qui repond des la
# passe specialize - donc pendant l'ecran "Installation xx %" qui suit le premier
# redemarrage -, ce drapeau ne peut apparaitre qu'une fois la session ouverte,
# c'est-a-dire au bureau.
function Test-NovaGuestReportsInstalled {
    param([Parameter(Mandatory)][string]$VmName)
    try {
        $cs = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem `
            -Filter ("ElementName='" + ($VmName -replace "'", "''") + "'") -ErrorAction Stop
        $kvp = $cs | ForEach-Object { $_.GetRelated("Msvm_KvpExchangeComponent") } | Select-Object -First 1
        if (-not $kvp -or -not $kvp.GuestExchangeItems) { return $false }
        foreach ($item in $kvp.GuestExchangeItems) {
            if ($item -match 'SplytInstallComplete') { return $true }
        }
        return $false
    } catch {
        return $false
    }
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
    param([Parameter(Mandatory)][string]$VmName, [int]$MaxSeconds = 150)
    $filter = "ElementName='" + ($VmName -replace "'", "''") + "'"
    $deadline = (Get-Date).AddSeconds($MaxSeconds)

    # Duree genereuse ET sortie anticipee, parce qu'on ne sait pas quand l'invite
    # va paraitre : mesure sur cette machine, une VM deja demarree une fois y
    # arrive en moins de douze secondes, mais le TOUT PREMIER demarrage est bien
    # plus lent (TPM virtuel et protecteur de cle a initialiser). Une rafale de
    # trente secondes la manquait donc systematiquement sur une VM neuve - c'est
    # a dire dans le seul cas qui compte - et le firmware repliait sur le reseau.
    #
    # On s'arrete des que le disque virtuel se met a grossir : l'installeur ecrit,
    # donc l'invite est passee depuis longtemps et il n'y a plus aucune raison de
    # continuer a taper dedans.
    $baseOctets = Get-NovaVmDiskBytes -VmName $VmName
    $tour = 0
    while ((Get-Date) -lt $deadline) {
        if ($tour % 20 -eq 0 -and (Get-NovaVmDiskBytes -VmName $VmName) - $baseOctets -gt 64MB) { return }
        $tour++
        try {
            $cs = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem `
                -Filter $filter -ErrorAction Stop
            $kb = $cs | ForEach-Object { $_.GetRelated("Msvm_Keyboard") } | Select-Object -First 1
            if ($kb) { $null = $kb.TypeKey(0x20) }   # VK_SPACE, comme la console
        } catch { }
        Start-Sleep -Milliseconds 250
    }
}

# Taille du disque avant que l'installeur n'y touche : c'est le zero de la
# progression. Relevee avant la rafale et pas dans la boucle principale, sinon
# les premiers mega-octets ecrits pendant la rafale seraient comptes comme
# "deja la" et la barre partirait en retard.
$baselineBytes = -1

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
    $baselineBytes = Get-NovaVmDiskBytes -VmName $Name
    Send-NovaBootKeyBurst -VmName $Name
    Set-NovaUnattendProgress -Stage "copy" -Percent 8
}

$deadline = (Get-Date).AddHours(3)

# Filet de securite pour une installation automatique dont le fichier de reponses
# n'aurait pas pu poser son drapeau : pose la premiere fois que le heartbeat
# repond, et arme un repli douze minutes plus tard. Compte a partir du heartbeat
# et pas du debut, pour ne pas dependre de la duree - tres variable - de la copie
# des fichiers : ce qu'on veut couvrir, c'est la phase d'apres.
$graceDeadline = $null

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
    $heartbeat = Test-NovaVmHeartbeatOk -Name $Name
    if ($heartbeat -and -not $graceDeadline) { $graceDeadline = (Get-Date).AddMinutes(12) }

    # Fin de l'installation. Deux definitions, selon le signal disponible :
    #
    #  - installation automatique : l'invite le dit lui-meme, en publiant son
    #    drapeau une fois la session ouverte. Le heartbeat ne suffit pas, il
    #    repond des la passe specialize - donc pendant l'ecran "Installation
    #    xx %" qui suit le premier redemarrage, alors que Windows en a encore
    #    pour de longues minutes. Il ne sert ici que de filet, une fois le delai
    #    de grace ecoule ;
    #  - installation manuelle : rien ne pose de drapeau, le heartbeat reste le
    #    seul signal disponible, comme avant.
    $termine = if ($unattend) {
        (Test-NovaGuestReportsInstalled -VmName $Name) -or
        ($graceDeadline -and (Get-Date) -gt $graceDeadline -and $heartbeat)
    } else {
        $heartbeat
    }

    if ($termine) {
        # On remet le disque dur en premier peripherique de demarrage, pour que
        # les demarrages suivants ne relancent pas l'installeur depuis l'ISO.
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
