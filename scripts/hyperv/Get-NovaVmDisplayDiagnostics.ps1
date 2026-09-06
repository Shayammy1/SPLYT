<#
.SYNOPSIS
    Diagnostic honnete de la limitation de frequence d'affichage. vmconnect
    (session Basique OU Amelioree) est un protocole d'images distantes, pas un
    vrai signal video a frequence variable : la frequence "reellement
    appliquee" ne peut pas depasser ce que ce protocole transmet, meme avec
    GPU-P configure (GPU-P accelere le RENDU dans la VM, pas le CHEMIN
    d'affichage vmconnect qui vous le montre). N'affirme jamais qu'une
    frequence demandee (ex. 100 Hz) est reellement appliquee sans verification.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop
    $prefs = Get-NovaVmPreferences -Name $Name

    $hostEnhancedSessionAllowed = $false
    try {
        $hostEnhancedSessionAllowed = [bool](Get-VMHost -ErrorAction Stop).EnableEnhancedSessionMode
    } catch { }

    $adapter = $null
    try {
        $adapter = Get-VMGpuPartitionAdapter -VMName $Name -ErrorAction Stop | Select-Object -First 1
    } catch { }
    $gpuPartitionActive = [bool]$adapter

    $limitation = if ($gpuPartitionActive) {
        "Le GPU-P est configure et accelere le rendu A L'INTERIEUR de la VM, mais l'affichage continue de passer par vmconnect (session Basique ou Amelioree/RDP) pour vous le montrer : ce protocole d'images distantes ne transmet pas de veritable signal a frequence variable, quelle que soit la puissance du rendu en amont."
    } else {
        "Aucun GPU-P n'est configure pour cette VM : l'affichage utilise l'adaptateur video synthetique Hyper-V (emule), qui n'a de toute facon aucune notion de frequence reelle."
    }

    $result = [ordered]@{
        vmName                     = $Name
        requestedResolution        = $prefs.resolution
        requestedHz                = $prefs.hz
        actualHz                   = 60
        actualHzIsReallyEnforced   = $false
        hostEnhancedSessionAllowed = $hostEnhancedSessionAllowed
        gpuPartitionActive         = $gpuPartitionActive
        displayPathLimitation      = $limitation
        recommendation             = "Pour une frequence reellement superieure a 60 Hz avec un rendu accelere par GPU-P, utilisez l'action 'Preparer le streaming 100+ Hz' : elle installe Moonlight sur cet ordinateur et depose l'installeur Sunshine sur le Bureau de la VM. Sunshine (dans la VM) capture l'image accelere par GPU-P et l'envoie a la vraie frequence choisie a Moonlight (ici) : vmconnect seul (Basique ou Amelioree) ne le permet pas."
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Depth 4 -Compress)
}
