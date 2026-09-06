<#
.SYNOPSIS
    Supprime une VRAIE VM Hyper-V : la VM elle-meme, son disque VHDX, et ses
    preferences locales (GPU-P/affichage).
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop

    $diskPaths = Get-VMHardDiskDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path

    if ($vm.State -ne 'Off') {
        Stop-VM -Name $Name -TurnOff -Force -ErrorAction Stop
    }
    Remove-VM -Name $Name -Force -ErrorAction Stop

    # Hyper-V effectue une fusion/liberation de disque en arriere-plan juste
    # apres Remove-VM : le VHDX peut rester verrouille une poignee de secondes.
    # On reessaie plutot que d'abandonner au premier echec (silencieux sinon).
    foreach ($path in $diskPaths) {
        if (-not $path) { continue }
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            if (-not (Test-Path -LiteralPath $path)) { break }
            try {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                break
            } catch {
                Start-Sleep -Seconds 2
            }
        }
    }

    Remove-NovaVmPreferences -Name $Name

    Write-NovaResult -Success $true -DataJson ('{"name":' + ($Name | ConvertTo-Json -Compress) + '}')
}
