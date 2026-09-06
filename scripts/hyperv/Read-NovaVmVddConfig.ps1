<#
.SYNOPSIS
    Outil de diagnostic MANUEL (a executer directement par vous-meme dans
    PowerShell, pas via l'interface NovaVM) : lit le vrai contenu du fichier
    de configuration du pilote VDD (C:\VirtualDisplayDriver\vdd_settings.xml)
    dans la VM, pour comprendre son format reel au lieu de deviner depuis la
    documentation en ligne.

    Vos identifiants sont demandes ICI, localement, via Read-Host -AsSecureString :
    ils ne transitent jamais par la conversation avec Claude, ne sont ni
    stockes, ni journalises.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Read-NovaVmVddConfig.ps1 -Name "TEST"
#>
param(
    [string]$Name = "TEST",
    [string]$OutFile = "$env:TEMP\novavm-vdd-settings.xml"
)

$rawUsername = Read-Host "Nom d'utilisateur Windows de la VM (email si compte Microsoft)"
$username = $rawUsername.Trim()
if ($username.Contains('@') -and -not $username.Contains('\')) {
    $username = "MicrosoftAccount\$username"
}
$securePassword = Read-Host "Mot de passe" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

$vm = Get-VM -Name $Name -ErrorAction Stop
if ($vm.State -ne 'Running') {
    Write-Host "La VM doit etre demarree."
    exit 1
}

Write-Host "Connexion (PowerShell Direct)..."
$content = Invoke-Command -VMName $Name -Credential $credential -ScriptBlock {
    $candidatePaths = @(
        "C:\VirtualDisplayDriver\vdd_settings.xml",
        "$env:ProgramData\VirtualDisplayDriver\vdd_settings.xml",
        "$env:LOCALAPPDATA\VirtualDisplayDriver\vdd_settings.xml"
    )
    $found = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $found) {
        # Recherche large si aucun des chemins standards ne correspond.
        $found = Get-ChildItem -Path C:\ -Filter "vdd_settings.xml" -Recurse -ErrorAction SilentlyContinue -Depth 4 |
            Select-Object -First 1 -ExpandProperty FullName
    } else {
        $found = $found | Select-Object -First 1
    }

    if (-not $found) {
        return "INTROUVABLE : aucun vdd_settings.xml trouve dans les emplacements standards ni via recherche."
    }

    "=== $found ===`n" + (Get-Content -LiteralPath $found -Raw)
}

Set-Content -LiteralPath $OutFile -Value $content -Encoding UTF8
Write-Host "Ecrit dans : $OutFile"
