<#
.SYNOPSIS
    Modifie le CPU/RAM d'une VRAIE VM Hyper-V. La VM doit etre eteinte
    (changer la RAM/le CPU a chaud n'est pas prevu ici).
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$Cpu,
    [Parameter(Mandatory)][long]$MemoryMb,
    # "true"/"false" (voir NovaVm.Common.psm1 - PowerShell ne convertit pas une
    # chaine recue en ligne de commande vers [bool] automatiquement).
    [string]$DynamicMemoryEnabled = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

$dynamicMemoryBool = $DynamicMemoryEnabled -eq "true"

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop

    $hostMemory = Get-NovaHostMemoryInfo
    if ($MemoryMb -gt $hostMemory.maxVmMemoryMb) {
        throw "La RAM demandee ($MemoryMb Mo) depasse la limite raisonnable pour cet ordinateur ($($hostMemory.maxVmMemoryMb) Mo, sur $($hostMemory.totalPhysicalMb) Mo physiques)."
    }
    if ($vm.State -ne 'Off') {
        throw "La VM doit etre arretee pour changer son CPU/sa RAM."
    }

    Set-VMProcessor -VMName $Name -Count $Cpu -ErrorAction Stop

    # Toujours repasser explicitement DynamicMemoryEnabled (pas seulement
    # StartupBytes) : sinon, desactiver la case a cocher dans SPLYT ne desactivait
    # jamais reellement la memoire dynamique cote Hyper-V si elle avait ete activee
    # manuellement auparavant (Set-VMMemory ne touche que les parametres fournis).
    if ($dynamicMemoryBool) {
        $minimumBytes = [Math]::Min(512MB, $MemoryMb * 1MB)
        Set-VMMemory -VMName $Name -DynamicMemoryEnabled $true `
            -MinimumBytes $minimumBytes -StartupBytes ($MemoryMb * 1MB) -MaximumBytes ($MemoryMb * 1MB) `
            -ErrorAction Stop
    } else {
        Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false -StartupBytes ($MemoryMb * 1MB) -ErrorAction Stop
    }

    $updated = Get-VM -Name $Name
    Write-NovaResult -Success $true -DataJson (ConvertTo-NovaVmDto -Vm $updated | ConvertTo-Json -Depth 8 -Compress)
}
