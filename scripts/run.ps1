<#
.SYNOPSIS
    Compile (si necessaire) puis execute le prototype NovaVM.
#>
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build"
$ExePath = Join-Path $BuildDir "$Configuration\NovaVM.exe"

& (Join-Path $PSScriptRoot "build.ps1") -Configuration $Configuration

if (-not (Test-Path $ExePath)) {
    Write-Error "Executable introuvable : $ExePath"
    exit 1
}

Write-Host "Execution de NovaVM.exe..." -ForegroundColor Cyan
& $ExePath
exit $LASTEXITCODE
