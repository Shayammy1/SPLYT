<#
.SYNOPSIS
    Outil de diagnostic/reparation MANUEL (a executer directement par vous-meme
    dans PowerShell, pas via l'interface NovaVM) pour une VM qui s'eteint toute
    seule ou reste en ecran noir apres l'installation d'un pilote d'ecran tiers.

    Vos identifiants sont demandes ICI, localement, via Read-Host -AsSecureString :
    ils ne transitent jamais par la conversation avec Claude, ne sont ni stockes,
    ni journalises. Seul le resultat du diagnostic (textes d'evenements Windows,
    noms de peripheriques) est ecrit dans un fichier JSON pour etre relu.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Repair-NovaVmDisplay.ps1 -Name "TEST"
#>
param(
    [string]$Name = "TEST",
    [string]$OutFile = "$env:TEMP\novavm-display-diag.json",
    [switch]$DisableVirtualDisplayDriver
)

Import-Module Hyper-V -ErrorAction Stop

$rawUsername = Read-Host "Nom d'utilisateur Windows de la VM (email si compte Microsoft)"
$username = $rawUsername.Trim()
if ($username.Contains('@') -and -not $username.Contains('\')) {
    $username = "MicrosoftAccount\$username"
}
$securePassword = Read-Host "Mot de passe" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

$vm = Get-VM -Name $Name -ErrorAction Stop
if ($vm.State -ne 'Running') {
    Write-Host "Demarrage de '$Name'..."
    Start-VM -Name $Name -ErrorAction Stop
}

Write-Host "Attente de la disponibilite de PowerShell Direct (jusqu'a 2 minutes)..."
$connected = $false
$lastError = $null
for ($attempt = 0; $attempt -lt 24 -and -not $connected; $attempt++) {
    Start-Sleep -Seconds 5
    try {
        Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ScriptBlock { $null } | Out-Null
        $connected = $true
    } catch {
        $lastError = $_.Exception.Message
    }
}

if (-not $connected) {
    Write-Host "Impossible de se connecter via PowerShell Direct : $lastError"
    Write-Host "La VM s'est peut-etre re-eteinte avant qu'on puisse s'y connecter. Relancez ce script."
    exit 1
}

Write-Host "Connecte. Collecte du diagnostic..."
$diag = Invoke-Command -VMName $Name -Credential $credential -ArgumentList $DisableVirtualDisplayDriver.IsPresent -ScriptBlock {
    param($doDisable)

    $shutdownEvents = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074, 6006, 6008, 41, 1076 } -MaxEvents 15 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, ProviderName, Message

    $displayDevices = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
        Select-Object FriendlyName, InstanceId, Status, Problem

    $pendingShutdown = $null
    try {
        $abortOutput = & shutdown.exe /a 2>&1
        $pendingShutdown = "shutdown /a : $abortOutput"
    } catch {
        $pendingShutdown = "shutdown /a : $($_.Exception.Message)"
    }

    $disableResult = $null
    if ($doDisable) {
        $vdd = $displayDevices | Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' }
        if ($vdd) {
            try {
                Disable-PnpDevice -InstanceId $vdd.InstanceId -Confirm:$false -ErrorAction Stop
                $disableResult = "Virtual Display Driver ($($vdd.InstanceId)) desactive avec succes."
            } catch {
                $disableResult = "Echec de la desactivation : $($_.Exception.Message)"
            }
        } else {
            $disableResult = "Aucun peripherique 'Virtual Display Driver' trouve (deja retire ?)."
        }
    }

    # Diagnostic specifique a la Session Amelioree (RDP interne via VMBus, distinct du VDD).
    $rdpServices = Get-Service -Name TermService, UmRdpService, SessionEnv -ErrorAction SilentlyContinue |
        Select-Object Name, Status, StartType

    $rdpCoreEvents = Get-WinEvent -LogName 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational' -MaxEvents 15 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message

    $lsmEvents = Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -MaxEvents 15 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message

    $sessions = & qwinsta.exe 2>&1

    [pscustomobject]@{
        CollectedAtUtc   = (Get-Date).ToUniversalTime().ToString("o")
        ShutdownEvents   = $shutdownEvents
        DisplayDevices   = $displayDevices
        PendingShutdown  = $pendingShutdown
        DisableResult    = $disableResult
        RdpServices      = $rdpServices
        RdpCoreEvents    = $rdpCoreEvents
        LsmEvents        = $lsmEvents
        Sessions         = ($sessions -join "`n")
    }
}

$diag | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Host "Diagnostic ecrit dans : $OutFile"
Write-Host "Vous pouvez maintenant demander a Claude de le lire et de l'analyser."
