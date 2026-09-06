<#
.SYNOPSIS
    Demarre une VRAIE VM Hyper-V. L'ouverture de la console (vmconnect.exe)
    est faite cote GUI (NovaVmService), pas ici.

    Si une ISO est montee :
    - verifie qu'elle existe toujours avant de demarrer (message clair sinon) ;
    - lance un processus detache (Send-NovaVmBootKey.ps1) qui envoie Entree en
      rafale des l'instant du demarrage, pour passer l'invite "Press any key to
      boot from CD or DVD..." (fenetre tres courte, une seconde ou deux) sans
      intervention manuelle ;
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

    Start-VM -Name $Name -ErrorAction Stop

    if ($dvd -and $dvd.Path) {
        Start-NovaDetachedScript -ScriptName "Send-NovaVmBootKey.ps1" -Name $Name
        Start-NovaDetachedScript -ScriptName "Watch-NovaVmInstallComplete.ps1" -Name $Name
    }

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
