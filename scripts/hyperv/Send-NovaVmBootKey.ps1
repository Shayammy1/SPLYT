<#
.SYNOPSIS
    Appuie sur une touche a l'invite de demarrage "Press any key to boot from
    CD or DVD...", pour une VM dont personne ne regarde la console.

    Volontairement minuscule et lance AVANT Start-VM par Start-NovaVm.ps1 : la
    fenetre pour repondre a cette invite est tres courte (mesure sur cette
    machine : elle expirait deja douze secondes apres la mise sous tension) et
    la manquer envoie le firmware sur le reseau, puis sur la page "The boot
    loader failed" - avec, cote SPLYT, une VM cachee derriere une barre qui
    n'avance plus.

    D'ou les regles de ce script :
      - aucun Import-Module, aucune lecture ni ecriture de preferences (leur
        mutex global est dispute par la GUI toutes les cinq secondes) ;
      - le chemin du disque est RECU en parametre plutot que demande a
        Get-VMHardDiskDrive, pour n'avoir besoin que de WMI ;
      - on tape tout de suite, sans attendre que la VM soit "Running" :
        TypeKey sur une machine encore eteinte echoue sans consequence.

    Ne fonctionne que sans adaptateur GPU-P attache, ce qui est toujours le cas
    a l'installation : GPU-P n'est configure qu'ensuite.
#>
param(
    [Parameter(Mandatory)][string]$VmName,
    # Disque virtuel de la VM. Des qu'il grossit, l'installeur ecrit : l'invite
    # est donc passee depuis longtemps et il n'y a plus rien a taper.
    [string]$DiskPath = "",
    [int]$MaxSeconds = 180,
    # Fichier cree des que ce script a reellement commence a taper. Start-NovaVm.ps1
    # l'attend avant d'allumer la VM : mesure sur cette machine, l'invite parait
    # entre une demi-seconde et deux secondes apres la mise sous tension, alors que
    # demarrer un powershell.exe en coute presque autant. Sans cette poignee de
    # main, la rafale arrivait apres la bataille une fois sur deux.
    [string]$ReadyFile = ""
)

$filter = "ElementName='" + ($VmName -replace "'", "''") + "'"
$deadline = (Get-Date).AddSeconds($MaxSeconds)

function Get-NovaDiskLength {
    if (-not $DiskPath) { return 0 }
    try { return [int64](New-Object System.IO.FileInfo $DiskPath).Length } catch { return 0 }
}

$base = Get-NovaDiskLength
$tour = 0

while ((Get-Date) -lt $deadline) {
    # Toutes les cinq secondes environ, et jamais au premier tour.
    if ($tour -gt 0 -and $tour % 20 -eq 0) {
        if ((Get-NovaDiskLength) - $base -gt 64MB) { break }
    }
    $tour++

    try {
        $cs = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem `
            -Filter $filter -ErrorAction Stop
        $kb = $cs | ForEach-Object { $_.GetRelated("Msvm_Keyboard") } | Select-Object -First 1
        if ($kb) { $null = $kb.TypeKey(0x20) }   # VK_SPACE, comme la console
    } catch {
        # VM pas encore allumee, ou WMI momentanement indisponible : on reessaie.
    }

    # Signale apres le premier tour, et pas avant : ce qui compte pour l'appelant
    # n'est pas que le processus existe, mais qu'il ait deja traverse WMI une fois -
    # c'est ce premier passage qui est lent.
    if ($ReadyFile -and $tour -eq 1) {
        try { New-Item -ItemType File -Path $ReadyFile -Force | Out-Null } catch { }
    }

    Start-Sleep -Milliseconds 200
}
