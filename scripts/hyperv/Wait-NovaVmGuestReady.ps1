<#
.SYNOPSIS
    Attend que le Windows invite d'une VM soit reellement pret a recevoir des
    commandes (PowerShell Direct), en surveillant le heartbeat Hyper-V.

    Utilise par l'enchainement "SPLYT" en un clic : apres avoir redemarre la VM
    pour appliquer le GPU-P, les etapes suivantes (VDD, Sunshine) passent par
    PowerShell Direct et echouent si elles partent trop tot. "La VM est
    demarree" (Start-VM a rendu la main) ne veut pas dire "Windows a fini de
    demarrer" : il s'ecoule facilement une minute entre les deux.

    Le heartbeat ne repond que lorsqu'un systeme a demarre normalement, avec ses
    services d'integration actifs - c'est exactement le signal recherche.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [int]$TimeoutSeconds = 300
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = $null

    while ((Get-Date) -lt $deadline) {
        $vm = Get-VM -Name $Name -ErrorAction Stop
        if ($vm.State -ne 'Running') {
            throw "La VM '$Name' n'est pas en cours d'execution (etat : $($vm.State))."
        }

        $heartbeat = Get-VMIntegrationService -VMName $Name -Name "Heartbeat" -ErrorAction SilentlyContinue
        $state = if ($heartbeat) { $heartbeat.PrimaryStatusDescription } else { $null }
        if ($state -ne $lastState) {
            Write-NovaProgress "Demarrage de Windows dans la VM ($(if ($state) { $state } else { 'en attente' }))"
            $lastState = $state
        }

        if ($state -eq 'OK') {
            # Windows repond : on memorise que cette VM a bien un systeme installe
            # (voir ConvertTo-NovaVmDto) et on laisse quelques secondes aux services
            # de la session de finir de se lancer avant d'y installer quoi que ce soit.
            Save-NovaVmPreferences -Name $Name -OsInstalled "true"
            Start-Sleep -Seconds 10

            $result = [ordered]@{ ready = $true; waitedSeconds = [int]($TimeoutSeconds - ($deadline - (Get-Date)).TotalSeconds) }
            Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
            return
        }

        Start-Sleep -Seconds 3
    }

    throw "Windows n'a pas fini de demarrer dans la VM '$Name' apres $TimeoutSeconds secondes."
}
