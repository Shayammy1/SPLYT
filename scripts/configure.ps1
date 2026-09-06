<#
.SYNOPSIS
    Configure le projet NovaVM avec CMake (generateur Visual Studio 17 2022, x64).
#>

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error "cmake est introuvable dans le PATH. Installez CMake (https://cmake.org/download/) et reessayez."
    exit 1
}

if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

cmake -S $RepoRoot -B $BuildDir -G "Visual Studio 17 2022" -A x64

if ($LASTEXITCODE -ne 0) {
    Write-Error "La configuration CMake a echoue (code $LASTEXITCODE)."
    exit $LASTEXITCODE
}

Write-Host "Configuration terminee. Utilisez scripts/build.ps1 pour compiler." -ForegroundColor Green
