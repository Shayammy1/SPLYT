<#
.SYNOPSIS
    Compile le projet NovaVM (execute configure.ps1 si necessaire).
#>
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build"

if (-not (Test-Path (Join-Path $BuildDir "CMakeCache.txt"))) {
    & (Join-Path $PSScriptRoot "configure.ps1")
}

cmake --build $BuildDir --config $Configuration

if ($LASTEXITCODE -ne 0) {
    Write-Error "La compilation a echoue (code $LASTEXITCODE)."
    exit $LASTEXITCODE
}

Write-Host "Compilation reussie ($Configuration)." -ForegroundColor Green
