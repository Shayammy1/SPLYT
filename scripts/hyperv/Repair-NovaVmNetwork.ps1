<#
.SYNOPSIS
    Repare l'acces internet des VMs quand le commutateur "Default Switch" de Hyper-V
    a cesse de router - panne connue et recurrente : il continue a distribuer des
    adresses par DHCP, la VM obtient donc une adresse tout a fait normale, mais plus
    rien ne sort. Vu de la VM, tout ressemble a une machine correctement connectee
    qui n'a simplement plus de DNS.

    Constate en conditions reelles : c'est ce qui faisait echouer l'installation
    automatique de VDD, qui telecharge son pilote depuis GitHub.

    Le script MESURE avant et apres au lieu d'agir en aveugle : sans ca, impossible
    de savoir si la reparation a servi a quelque chose ou si la panne etait
    ailleurs. Le test est une resolution DNS adressee a la passerelle que les VMs
    utilisent elles-memes.

    Deux remedes appliques dans l'ordre, du moins au plus perturbateur :
      1. redemarrage du service de partage de connexion (ICS), qui fournit le NAT ;
      2. desactivation/reactivation de la carte du commutateur.

    Necessite une elevation (les deux operations l'exigent) - voir
    PowerShellRunner.RunElevatedAsync cote C#.

    Effet de bord assume : les VMs en cours d'execution perdent le reseau quelques
    secondes, et le sous-reseau distribue par le commutateur peut changer (l'adresse
    des VMs change alors au prochain bail DHCP).
#>
param(
    [string]$SwitchAdapterAlias = "vEthernet (Default Switch)"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Adresse de la passerelle du commutateur : c'est elle que les VMs interrogent, donc
# c'est elle qu'il faut tester - pas la connexion internet de l'hote, qui peut tres
# bien fonctionner pendant que le commutateur, lui, ne route plus.
function Get-NovaSwitchGateway {
    param([Parameter(Mandatory)][string]$Alias)
    return (Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1).IPAddress
}

function Test-NovaSwitchDns {
    param([string]$Gateway)
    if (-not $Gateway) { return $false }
    try {
        $resolved = Resolve-DnsName -Name "github.com" -Server $Gateway -Type A -QuickTimeout -ErrorAction Stop
        return [bool]($resolved | Where-Object { $_.IPAddress })
    } catch {
        return $false
    }
}

Invoke-NovaAction {
    $adapter = Get-NetAdapter -Name $SwitchAdapterAlias -ErrorAction SilentlyContinue
    if (-not $adapter) {
        throw "La carte '$SwitchAdapterAlias' est introuvable sur cet ordinateur. Le commutateur Hyper-V correspondant n'existe peut-etre pas (ou porte un autre nom)."
    }

    Write-NovaProgress "Test de l'acces reseau avant reparation"
    $gatewayBefore = Get-NovaSwitchGateway -Alias $SwitchAdapterAlias
    $workedBefore = Test-NovaSwitchDns -Gateway $gatewayBefore

    Write-NovaProgress "Redemarrage du service de partage de connexion (ICS)"
    $icsRestarted = $false
    try {
        Restart-Service -Name "SharedAccess" -Force -ErrorAction Stop
        $icsRestarted = $true
        Start-Sleep -Seconds 5
    } catch {
        # Non bloquant : la reactivation de la carte ci-dessous suffit souvent seule.
    }

    Write-NovaProgress "Reactivation de la carte du commutateur"
    Disable-NetAdapter -Name $SwitchAdapterAlias -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 3
    Enable-NetAdapter -Name $SwitchAdapterAlias -Confirm:$false -ErrorAction Stop

    # La carte remonte progressivement : inutile de tester une adresse qui n'existe
    # pas encore, on attend qu'elle reapparaisse avant de conclure.
    Write-NovaProgress "Attente du retour de la carte"
    $gatewayAfter = $null
    for ($attempt = 0; $attempt -lt 20 -and -not $gatewayAfter; $attempt++) {
        Start-Sleep -Seconds 2
        $gatewayAfter = Get-NovaSwitchGateway -Alias $SwitchAdapterAlias
    }

    Write-NovaProgress "Test de l'acces reseau apres reparation"
    $workedAfter = $false
    for ($attempt = 0; $attempt -lt 10 -and -not $workedAfter; $attempt++) {
        $workedAfter = Test-NovaSwitchDns -Gateway $gatewayAfter
        if (-not $workedAfter) { Start-Sleep -Seconds 3 }
    }

    $message = if ($workedAfter -and -not $workedBefore) {
        "Reseau repare : la passerelle $gatewayAfter resout de nouveau les noms. Les VMs demarrees doivent renouveler leur adresse - redemarrez-les si elles n'ont toujours pas internet."
    } elseif ($workedAfter -and $workedBefore) {
        "Le reseau fonctionnait deja avant l'operation, et fonctionne toujours (passerelle $gatewayAfter). Si une VM n'a pas internet, le probleme est a l'interieur de celle-ci, pas sur le commutateur."
    } else {
        "La reparation n'a pas suffi : la passerelle $gatewayAfter ne resout toujours pas les noms. A tenter ensuite : redemarrer l'ordinateur, ou supprimer le commutateur 'Default Switch' pour que Windows le recree."
    }

    $result = [ordered]@{
        gatewayBefore = $gatewayBefore
        gatewayAfter  = $gatewayAfter
        workedBefore  = $workedBefore
        workedAfter   = $workedAfter
        icsRestarted  = $icsRestarted
        message       = $message
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
