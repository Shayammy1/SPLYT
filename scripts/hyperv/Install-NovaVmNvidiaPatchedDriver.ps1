<#
.SYNOPSIS
    BIDOUILLE COMMUNAUTAIRE, NON OFFICIELLE - contrairement a Install-NovaVmGpuDriver.ps1
    (procedure GPU-P officiellement documentee par Microsoft, vendeur-agnostique), les
    GPU NVIDIA GeForce grand public refusent volontairement de fonctionner dans une VM :
    leur pilote noyau (nvlddmkm.sys) detecte l'hyperviseur et desactive l'acceleration.
    NVIDIA ne le permet officiellement que sur ses cartes datacenter avec licence vGPU
    payante.

    Reprend (avec attribution, licence MIT) la technique publiee par Rafael Rivera
    (github.com/riverar/Remove-HypervisorChecks, 2020) : patcher quelques octets precis
    dans nvlddmkm.sys pour neutraliser cette detection, puis reconstruire/re-signer
    (auto-signature, d'ou le Mode test requis) le catalogue du pilote.

    FRAGILITE ASSUMEE : cette technique repose sur un motif d'octets EXACT, verifie
    manuellement par son auteur pour quatre versions precises de pilote NVIDIA (de
    375.63 a 461.40, toutes anterieures a 2021 - le projet est abandonne depuis, aucun
    motif connu pour les pilotes recents). Ce script essaie les quatre motifs connus
    dans l'ordre ; si AUCUN ne correspond EXACTEMENT une fois dans votre pilote (le cas
    le plus probable avec un pilote NVIDIA recent), il s'arrete proprement SANS modifier
    votre fichier - impossible de determiner un nouveau motif automatiquement sans
    retro-ingenierie manuelle (desassemblage) du pilote concerne.

    Etapes :
    1. Verifie/installe 7-Zip (extraction de l'installeur NVIDIA) et les outils du
       Windows Driver Kit - inf2cat.exe, signtool.exe (regeneration/signature du
       catalogue) - via winget si absents (peut telecharger plusieurs centaines de Mo
       la premiere fois seulement).
    2. Extrait l'installeur NVIDIA fourni par l'utilisateur (telecharge manuellement
       depuis nvidia.com - SPLYT ne redistribue aucun fichier NVIDIA).
    3. Cherche puis patche nvlddmkm.sys, regenere son catalogue, le signe avec un
       certificat auto-genere jetable.
    4. Monte hors-ligne le disque de la VM (doit etre eteinte), active le Mode test
       (bcdedit sur le magasin BCD hors-ligne - pas besoin de credentials/PowerShell
       Direct pour cette etape) et enregistre le pilote patche via DISM.

    Prerequis : executer d'abord "Installer le pilote" (Install-NovaVmGpuDriver.ps1,
    methode officielle) au moins une fois sur cette VM - ce script reutilise sa copie
    du magasin de pilotes (HostDriverStore) et se contente de reenregistrer la partie
    pilote noyau avec la version patchee.

    Consequence visible : une fois demarree, la VM affichera le filigrane "Mode test"
    sur le bureau (normal et attendu - Windows le montre toujours quand la verification
    de signature des pilotes est assouplie).
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$DriverInstallerPath
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

# Motifs connus (auteur original : Rafael Rivera, MIT) - "call <fonction de detection
# d'hyperviseur> ; test eax,eax ; jnz". Essayes dans l'ordre ; le tout premier qui
# correspond EXACTEMENT UNE FOIS dans le fichier est utilise. Remplacement (8 octets,
# le 9e octet du motif est laisse tel quel) : xor rax,rax ; jmp $+2 ; test eax,eax ; jmp.
$script:KnownPatterns = @(
    @{ Pattern = 'E8 A4 FD FF FF 85 C0 75 6C'; Note = '~461.40' },
    @{ Pattern = 'E8 9C FD FF FF 85 C0 75 6C'; Note = '~451.67' },
    @{ Pattern = 'E8 A8 FD FF FF 85 C0 75 6C'; Note = '~446.14' },
    @{ Pattern = 'E8 A7 FD FF FF 85 C0 75 43'; Note = '~375.63' }
)
$script:PatchBytes = [byte[]]@(0x48, 0x31, 0xC0, 0xEB, 0x02, 0x85, 0xC0, 0xEB)

function Find-NovaBytePattern {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string]$Pattern)
    $fileStream = New-Object IO.FileStream -ArgumentList @((Resolve-Path $FilePath), "Open", "Read", "None")
    $streamReader = New-Object IO.StreamReader -ArgumentList @($fileStream, [Text.Encoding]::GetEncoding("iso-8859-1"))
    try {
        $bytes = $streamReader.ReadToEnd()
    } finally {
        $streamReader.Close()
        $streamReader.Dispose()
    }
    $regex = [Regex]($Pattern.Insert(0, "\x") -replace ' ', '\x')
    return $regex.Matches($bytes)
}

function Get-NovaToolPath {
    param([Parameter(Mandatory)][string]$FileName, [Parameter(Mandatory)][string]$SearchRoot)
    Get-ChildItem -Path $SearchRoot -Filter $FileName -Recurse -ErrorAction SilentlyContinue -Depth 4 |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}

Invoke-NovaAction {
    if (-not (Test-Path -LiteralPath $DriverInstallerPath -PathType Leaf)) {
        throw "Installeur NVIDIA introuvable : $DriverInstallerPath"
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Off') {
        throw "La VM doit etre eteinte pour cette operation (montage hors-ligne de son disque)."
    }

    $prefs = Get-NovaVmPreferences -Name $Name
    $gpuName = $prefs.gpuName
    if ([string]::IsNullOrWhiteSpace($gpuName)) {
        throw "Aucun GPU-P n'est configure pour cette VM."
    }
    if ($gpuName -notmatch '(?i)nvidia|geforce|rtx|gtx|quadro') {
        throw "Le GPU configure ('$gpuName') ne semble pas etre un GPU NVIDIA - cette procedure ne s'applique qu'aux GPU NVIDIA."
    }

    Write-NovaProgress "Recherche/installation de 7-Zip"
    $sevenZipPath = "$env:ProgramFiles\7-Zip\7z.exe"
    if (-not (Test-Path -LiteralPath $sevenZipPath)) {
        & winget.exe install --id "7zip.7zip" -e --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
    }
    if (-not (Test-Path -LiteralPath $sevenZipPath)) {
        throw "7-Zip est introuvable meme apres tentative d'installation via winget (7z.exe attendu dans $sevenZipPath)."
    }

    Write-NovaProgress "Recherche/installation des outils du Windows Driver Kit (peut telecharger plusieurs centaines de Mo la premiere fois)"
    $wdkSearchRoots = @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "$env:ProgramFiles\Windows Kits\10\bin")
    $inf2catPath = $null
    $signtoolPath = $null
    foreach ($root in $wdkSearchRoots) {
        if (-not $inf2catPath -and (Test-Path -LiteralPath $root)) { $inf2catPath = Get-NovaToolPath -FileName "inf2cat.exe" -SearchRoot $root }
        if (-not $signtoolPath -and (Test-Path -LiteralPath $root)) { $signtoolPath = Get-NovaToolPath -FileName "signtool.exe" -SearchRoot $root }
    }
    if (-not $inf2catPath -or -not $signtoolPath) {
        & winget.exe install --id "Microsoft.WindowsWDK" -e --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        foreach ($root in $wdkSearchRoots) {
            if (-not $inf2catPath -and (Test-Path -LiteralPath $root)) { $inf2catPath = Get-NovaToolPath -FileName "inf2cat.exe" -SearchRoot $root }
            if (-not $signtoolPath -and (Test-Path -LiteralPath $root)) { $signtoolPath = Get-NovaToolPath -FileName "signtool.exe" -SearchRoot $root }
        }
    }
    if (-not $inf2catPath -or -not $signtoolPath) {
        throw "inf2cat.exe et/ou signtool.exe introuvables meme apres tentative d'installation du Windows Driver Kit via winget. Installez manuellement le 'Windows Driver Kit' puis reessayez."
    }

    Write-NovaProgress "Extraction de l'installeur NVIDIA (peut prendre plusieurs minutes)"
    $workDir = Join-Path $env:TEMP "NovaVM-NvidiaPatch-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    $extractedPath = Join-Path $workDir "Extracted"
    try {
        & $sevenZipPath x "-i!*" "$DriverInstallerPath" "-o$extractedPath" | Out-Null

        $driverFolder = Join-Path $extractedPath "Display.Driver"
        $catPath = Join-Path $driverFolder "nv_disp.cat"
        $compressedKernelPath = Join-Path $driverFolder "nvlddmkm.sy_"
        $kernelPath = Join-Path $driverFolder "nvlddmkm.sys"
        if (-not (Test-Path -LiteralPath $catPath) -or -not (Test-Path -LiteralPath $compressedKernelPath)) {
            throw "Structure de pilote NVIDIA inattendue (Display.Driver\nv_disp.cat / nvlddmkm.sy_ introuvables) - l'installeur fourni n'est peut-etre pas un pilote NVIDIA standard."
        }

        Write-NovaProgress "Recherche du motif connu dans nvlddmkm.sys"
        & expand.exe "$compressedKernelPath" "$kernelPath" | Out-Null

        $matchedPattern = $null
        foreach ($candidate in $script:KnownPatterns) {
            $matches = Find-NovaBytePattern -FilePath $kernelPath -Pattern $candidate.Pattern
            if ($matches.Count -eq 1) {
                $matchedPattern = $candidate
                $matchIndex = $matches[0].Index
                break
            }
        }
        if (-not $matchedPattern) {
            throw "Aucun des motifs connus (versions ~375.63 a ~461.40) ne correspond exactement une fois dans ce nvlddmkm.sys : votre pilote NVIDIA est trop recent pour cette technique (abandonnee depuis 2021, aucun motif publie pour les pilotes actuels). Aucune modification n'a ete faite. Il n'existe pas de moyen automatise et sur de deriver un nouveau motif sans retro-ingenierie manuelle du pilote."
        }

        Write-NovaProgress "Patch de nvlddmkm.sys (motif $($matchedPattern.Note))"
        $writer = New-Object IO.BinaryWriter -ArgumentList @(New-Object IO.FileStream -ArgumentList @($kernelPath, "Open", "Write", "None"))
        try {
            $writer.Seek($matchIndex, 'Begin') | Out-Null
            $writer.Write($script:PatchBytes)
        } finally {
            $writer.Close()
            $writer.Dispose()
        }

        Write-NovaProgress "Recompression et reconstruction du catalogue du pilote (peut prendre plusieurs minutes)"
        & makecab.exe "$kernelPath" "$compressedKernelPath" | Out-Null
        Remove-Item -LiteralPath $kernelPath -Force

        & $inf2catPath "/os:10_X64" "/v" "/driver:$driverFolder" | Out-Null

        $signingCert = New-SelfSignedCertificate -Type CodeSigningCert `
            -Subject "CN=SPLYT NVIDIA GPU-P (auto-genere, jetable)" -CertStoreLocation "Cert:\CurrentUser\My"
        try {
            & $signtoolPath sign "/sha1" $signingCert.Thumbprint "$catPath" | Out-Null
        } finally {
            Remove-Item -LiteralPath $signingCert.PSPath -Force -ErrorAction SilentlyContinue
        }

        Write-NovaProgress "Recherche du fichier .inf correspondant a votre pilote NVIDIA installe sur cet hote"
        $hostDriverInfo = Find-NovaHostGpuDriverPackage -GpuName $gpuName
        $infLeafName = Split-Path -Leaf $hostDriverInfo.infFile
        $patchedInfPath = Join-Path $driverFolder $infLeafName
        if (-not (Test-Path -LiteralPath $patchedInfPath)) {
            throw "Le fichier '$infLeafName' (correspondant au pilote actuellement installe sur cet hote) est introuvable dans le pilote NVIDIA fourni. Assurez-vous d'avoir telecharge exactement la MEME version de pilote que celle installee sur cet ordinateur."
        }

        $hardDrive = Get-VMHardDiskDrive -VMName $Name -ErrorAction Stop | Select-Object -First 1
        if (-not $hardDrive) { throw "Aucun disque dur trouve pour cette VM." }

        Write-NovaProgress "Montage du disque de la VM"
        Mount-VHD -Path $hardDrive.Path -ErrorAction Stop | Out-Null
        try {
            $partition = Get-VHD -Path $hardDrive.Path -ErrorAction Stop |
                Get-Disk | Get-Partition | Where-Object { $_.DriveLetter } | Select-Object -First 1
            if (-not $partition) { throw "Aucune partition Windows (avec lettre de lecteur) trouvee sur le disque de la VM une fois monte." }
            $volumeRoot = "$($partition.DriveLetter):\"

            Write-NovaProgress "Activation du Mode test (magasin BCD hors-ligne de la VM)"
            $bcdStorePath = Join-Path $volumeRoot "Boot\BCD"
            if (Test-Path -LiteralPath $bcdStorePath) {
                & bcdedit.exe /store $bcdStorePath /set '{default}' testsigning on | Out-Null
            } else {
                throw "Magasin BCD introuvable sur le disque de la VM ($bcdStorePath) - Mode test non active."
            }

            Write-NovaProgress "Enregistrement du pilote patche (DISM)"
            $addResult = Add-WindowsDriver -Path $volumeRoot -Driver $patchedInfPath -ForceUnsigned -ErrorAction Stop

            $result = [ordered]@{
                gpuName          = $gpuName
                patternUsed      = $matchedPattern.Note
                infFile          = $patchedInfPath
                pnpInstalledDriver = $addResult.Driver
                message          = "Pilote NVIDIA patche (motif version $($matchedPattern.Note)) et enregistre. Mode test active sur cette VM (le filigrane 'Mode test' apparaitra sur le bureau - c'est normal). Demarrez la VM pour verifier dans le Gestionnaire de peripheriques. Si le GPU affiche toujours une erreur, ce pilote precis n'est probablement pas compatible avec cette technique."
            }
            Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
        } finally {
            Dismount-VHD -Path $hardDrive.Path -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
