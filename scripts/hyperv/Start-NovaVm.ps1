<#
.SYNOPSIS
    Demarre une VRAIE VM Hyper-V. L'ouverture de la console (vmconnect.exe)
    est faite cote GUI (NovaVmService), pas ici.

    Si une ISO est montee ET encore premier peripherique de demarrage
    (needsBootKeyPress du DTO retourne - voir ConvertTo-NovaVmDto), la GUI
    simule elle-meme un appui clavier DANS LA FENETRE vmconnect une fois
    celle-ci ouverte, pour passer l'invite "Press any key to boot from CD
    or DVD..." sans intervention manuelle.

    Ancienne approche abandonnee : simuler la touche via le clavier
    synthetique WMI (Msvm_Keyboard.TypeKey), independamment de toute fenetre
    vmconnect. Verifie empiriquement (capture d'ecran + logs) : ca fonctionne
    sur une VM sans GPU-P, mais PAS sur une VM avec un adaptateur GPU-P
    attache (Add-VMGpuPartitionAdapter) - les appels WMI reussissent sans
    erreur mais la touche n'atteint jamais reellement l'invite de demarrage.
    Puisque GPU-P est la fonctionnalite phare de SPLYT, c'etait inacceptable.
    A l'inverse, appuyer une touche reellement DANS la fenetre vmconnect
    (confirme par l'utilisateur, manuellement) fonctionne dans tous les cas -
    d'ou le nouveau mecanisme, cote GUI plutot que cote script.
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
        Start-NovaDetachedScript -ScriptName "Watch-NovaVmInstallComplete.ps1" -Name $Name
    }

    Start-VM -Name $Name -ErrorAction Stop

    $vm = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $vm | ConvertTo-Json -Depth 8 -Compress)
}
