<#
.SYNOPSIS
    Demarre une VRAIE VM Hyper-V. L'ouverture de la console (vmconnect.exe)
    est faite cote GUI (NovaVmService), pas ici.

    Si une ISO est montee :
    - verifie qu'elle existe toujours avant de demarrer (message clair sinon) ;
    - lance D'ABORD (avant Start-VM) un processus detache (Send-NovaVmBootKey.ps1)
      qui envoie Entree en rafale pour passer l'invite "Press any key to boot
      from CD or DVD..." (fenetre tres courte, une seconde ou deux, qui peut
      apparaitre moins de 2 secondes apres le demarrage) sans intervention
      manuelle. L'ordre compte : demarrer ce processus APRES Start-VM (comme
      avant) ajoute le cout de demarrage d'un nouveau powershell.exe (chargement
      des assemblies CIM comprises) avant le premier envoi de touche, ce qui
      peut a lui seul depasser la fenetre. En le lancant avant, ce cout est
      absorbe pendant que Start-VM tourne encore, et la boucle d'envoi est deja
      chaude au moment ou l'invite apparait reellement ;
    - lance un second processus detache (Watch-NovaVmInstallComplete.ps1) qui
      remettra le disque dur en premier peripherique de demarrage une fois
      l'installation terminee, pour eviter de relancer l'installeur au prochain
      demarrage.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

function Start-NovaDetachedScript {
    param([Parameter(Mandatory)][string]$ScriptName, [Parameter(Mandatory)][string]$Name)
    Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        (Join-Path $PSScriptRoot $ScriptName),
        "-Name", $Name
    )
}

Invoke-NovaAction {
    $dvd = Get-VMDvdDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dvd -and $dvd.Path -and -not (Test-Path -LiteralPath $dvd.Path)) {
        throw "L'image ISO configuree pour cette VM est introuvable : $($dvd.Path)"
    }

    if ($dvd -and $dvd.Path) {
        # Lance en premier, AVANT Start-VM : voir le commentaire d'en-tete - le
        # temps de demarrage de ce processus (powershell.exe + assemblies CIM)
        # doit se chevaucher avec Start-VM, pas s'additionner apres, sans quoi
        # l'invite "Press any key" (a peine 1-2 secondes, parfois vue en moins
        # de 2 secondes apres le clic "Demarrer") peut deja etre passee avant
        # le tout premier envoi de touche.
        Start-NovaDetachedScript -ScriptName "Send-NovaVmBootKey.ps1" -Name $Name
        Start-NovaDetachedScript -ScriptName "Watch-NovaVmInstallComplete.ps1" -Name $Name
    }

    Start-VM -Name $Name -ErrorAction Stop

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
