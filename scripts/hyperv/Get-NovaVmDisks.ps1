<#
.SYNOPSIS
    Liste les disques virtuels (VHDX) des VRAIES VMs Hyper-V, avec la taille
    reellement occupee sur le disque (Get-VHD), pas une estimation.
#>
param()

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vms = Get-VM -ErrorAction Stop
    $disks = foreach ($vm in $vms) {
        $hardDrive = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $hardDrive) { continue }

        $sizeGb = 0
        $usedGb = 0
        try {
            $vhd = Get-VHD -Path $hardDrive.Path -ErrorAction Stop
            $sizeGb = [math]::Round([double]$vhd.Size / 1GB, 1)
            $usedGb = [math]::Round([double]$vhd.FileSize / 1GB, 1)
        } catch {
            # VHD introuvable/inaccessible : on affiche quand meme la ligne, tailles a 0.
        }

        [ordered]@{
            path       = $hardDrive.Path
            sizeGb     = $sizeGb
            usedGb     = $usedGb
            attachedVm = $vm.Name
        }
    }

    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaJsonArray -InputObject $disks)
}
