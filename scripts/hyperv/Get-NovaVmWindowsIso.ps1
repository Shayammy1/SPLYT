<#
.SYNOPSIS
    Telecharge automatiquement l'image ISO officielle de Windows 11 (edition
    Home/Pro/Edu, x64) depuis les serveurs de Microsoft, et la met en cache
    localement pour que toutes les VMs creees ensuite la reutilisent sans
    nouveau telechargement (voir CreateVmDialogViewModel : la VM preremplit
    automatiquement le champ ISO avec ce fichier des qu'il existe).

    Ne redistribue AUCUN fichier Microsoft avec SPLYT : reproduit uniquement,
    en HTTP, le meme parcours que microsoft.com/software-download/windows11
    effectue normalement dans un navigateur (choix d'edition, verification
    anti-robot du site, recuperation du lien de telechargement officiel). Le
    fichier obtenu provient exclusivement des serveurs de Microsoft.

    Fragilite connue et assumee : ce parcours n'est pas une API publique
    documentee par Microsoft. Le site peut changer sans preavis (nouveaux
    identifiants d'edition a chaque version de Windows 11, nouvelles
    verifications anti-robot) et casser ce script. En cas d'echec, le
    telechargement manuel depuis microsoft.com/fr-fr/software-download/windows11
    reste toujours possible via le bouton "Parcourir" du formulaire de
    creation de VM.

    Idempotent : si un fichier deja telecharge et de taille plausible existe
    a $OutputPath, ne retelecharge rien.
#>
param(
    [string]$OutputPath = "C:\NovaVM\Downloads\Windows11.iso",
    # Nom de langue tel que retourne par l'API Microsoft (ex. "French", "English International").
    [string]$Language = "French"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Invoke-NovaAction {
    if ((Test-Path -LiteralPath $OutputPath) -and (Get-Item -LiteralPath $OutputPath).Length -gt 3GB) {
        $cached = Get-Item -LiteralPath $OutputPath
        $result = [ordered]@{
            isoPath       = $OutputPath
            alreadyCached = $true
            sizeGb        = [math]::Round($cached.Length / 1GB, 2)
            message       = "L'ISO Windows 11 est deja presente localement."
        }
        Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
        return
    }

    # Identifiants fixes du parcours "software-download-connector" de Microsoft pour
    # Windows 11 (edition consommateur Home/Pro/Edu, x64) : le productEditionId change a
    # chaque nouvelle version majeure de Windows 11 publiee sur cette page. S'il devient
    # invalide (l'appel SKU ci-dessous echoue ou renvoie une liste vide), il doit etre mis
    # a jour en consultant a nouveau microsoft.com/software-download/windows11.
    $orgId = "y6jn8c31"
    $profileId = "606624d44113"
    $instanceId = "560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
    $productEditionId = 3321
    $locale = "fr-FR"
    $sessionId = [guid]::NewGuid().ToString()
    $referer = "https://www.microsoft.com/software-download/windows11"

    Write-NovaProgress "Preparation de la session Microsoft"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://vlscppe.microsoft.com/tags?org_id=$orgId&session_id=$sessionId" `
            -MaximumRedirection 0 -ErrorAction Stop | Out-Null
    } catch {
        throw "Impossible d'initialiser la session aupres de Microsoft : $($_.Exception.Message)"
    }

    try {
        $mdtUrl = "https://ov-df.microsoft.com/mdt.js?instanceId=$instanceId&PageId=si&session_id=$sessionId"
        $mdtResponse = Invoke-RestMethod -UseBasicParsing -Uri $mdtUrl -ErrorAction Stop
        $w = [regex]::Match($mdtResponse, '[?&]w=([A-F0-9]+)').Groups[1].Value
        $rticks = [regex]::Match($mdtResponse, 'rticks\=\"\+?(\d+)').Groups[1].Value
        if (-not $w -or -not $rticks) {
            throw "Reponse inattendue du controle anti-robot de Microsoft (le site a probablement change)."
        }
        $epochMs = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        $replyUrl = "https://ov-df.microsoft.com/?session_id=$sessionId&CustomerId=$instanceId&PageId=si&w=$w&mdt=$epochMs&rticks=$rticks"
        Invoke-WebRequest -UseBasicParsing -Uri $replyUrl -MaximumRedirection 0 -ErrorAction Stop | Out-Null
    } catch {
        throw "Echec du controle anti-robot de Microsoft : $($_.Exception.Message)"
    }

    Write-NovaProgress "Recuperation des informations d'edition Windows 11"
    $skuResponse = $null
    $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition" +
        "?profile=$profileId&productEditionId=$productEditionId&SKU=undefined&friendlyFileName=undefined&Locale=$locale&sessionID=$sessionId"
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Seconds 2 }
        try {
            $response = Invoke-RestMethod -UseBasicParsing -Uri $skuUrl -ErrorAction Stop
            if ($response -and -not $response.Errors -and $response.Skus -and $response.Skus.Count -gt 0) {
                $skuResponse = $response
                break
            }
        } catch { }
    }
    if (-not $skuResponse) {
        throw "Microsoft n'a pas renvoye d'edition Windows 11 valide. Cela arrive si le site a change (identifiant d'edition perime) ou si trop de demandes ont ete faites recemment depuis cette adresse IP. Telechargez l'ISO manuellement sur microsoft.com/fr-fr/software-download/windows11."
    }

    $sku = $skuResponse.Skus | Where-Object { $_.Language -eq $Language } | Select-Object -First 1
    if (-not $sku) { $sku = $skuResponse.Skus | Select-Object -First 1 }
    if (-not $sku) {
        throw "Aucune edition Windows 11 disponible pour la langue '$Language'."
    }

    Write-NovaProgress "Recuperation du lien de telechargement officiel"
    $linksUrl = "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku" +
        "?profile=$profileId&productEditionId=undefined&SKU=$($sku.Id)&friendlyFileName=undefined&Locale=$locale&sessionID=$sessionId"
    try {
        $linksResponse = Invoke-RestMethod -UseBasicParsing -Uri $linksUrl -Headers @{ "Referer" = $referer } -ErrorAction Stop
    } catch {
        throw "Echec de la recuperation du lien de telechargement : $($_.Exception.Message)"
    }
    if ($linksResponse.Errors) {
        throw "Microsoft a refuse la demande de telechargement (" + $linksResponse.Errors[0].Value + "). Cela arrive generalement en cas de trop nombreuses demandes recentes depuis cette adresse IP - reessayez plus tard, ou telechargez l'ISO manuellement sur microsoft.com/fr-fr/software-download/windows11."
    }

    # productEditionId 3321 est deja specifique a x64 (l'ARM64 utilise un identifiant
    # different) : l'API ne renvoie donc normalement qu'une seule option ici.
    $downloadOption = $linksResponse.ProductDownloadOptions | Select-Object -First 1
    if (-not $downloadOption -or -not $downloadOption.Uri) {
        throw "Microsoft n'a renvoye aucun lien de telechargement exploitable."
    }
    $downloadUrl = $downloadOption.Uri

    Write-NovaProgress "Telechargement de l'ISO Windows 11 : demarrage"
    $outputDir = Split-Path -Path $OutputPath -Parent
    New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction SilentlyContinue | Out-Null
    $tempPath = "$OutputPath.download"
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }

    try {
        $webRequest = [System.Net.HttpWebRequest]::Create($downloadUrl)
        $webRequest.Method = "GET"
        $webResponse = $webRequest.GetResponse()
        $totalBytes = $webResponse.ContentLength
        $responseStream = $webResponse.GetResponseStream()
        $fileStream = [System.IO.File]::Create($tempPath)
        try {
            $buffer = New-Object byte[] 1MB
            $totalRead = [int64]0
            $lastPercent = -1
            while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead
                if ($totalBytes -gt 0) {
                    $percent = [int](($totalRead * 100) / $totalBytes)
                    if ($percent -ne $lastPercent) {
                        $doneGb = [math]::Round($totalRead / 1GB, 2)
                        $totalGb = [math]::Round($totalBytes / 1GB, 2)
                        Write-NovaProgress "Telechargement de l'ISO Windows 11 : $percent% ($doneGb Go / $totalGb Go)"
                        $lastPercent = $percent
                    }
                }
            }
        } finally {
            $fileStream.Close()
            $responseStream.Close()
            $webResponse.Close()
        }
    } catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        throw "Echec du telechargement de l'ISO : $($_.Exception.Message)"
    }

    $downloadedFile = Get-Item -LiteralPath $tempPath
    if ($downloadedFile.Length -lt 3GB) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw "Le fichier telecharge est anormalement petit ($([math]::Round($downloadedFile.Length / 1MB, 0)) Mo) : telechargement probablement incomplet."
    }

    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force

    $finalFile = Get-Item -LiteralPath $OutputPath
    $result = [ordered]@{
        isoPath       = $OutputPath
        alreadyCached = $false
        sizeGb        = [math]::Round($finalFile.Length / 1GB, 2)
        message       = "ISO Windows 11 telechargee avec succes depuis les serveurs officiels Microsoft."
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
