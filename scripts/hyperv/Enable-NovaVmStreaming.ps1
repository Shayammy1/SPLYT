<#
.SYNOPSIS
    Vraie solution pour depasser 60 Hz avec GPU-P : vmconnect (Basique ou
    Amelioree) ne transmettant aucun signal a frequence variable (voir
    Get-NovaVmDisplayDiagnostics.ps1), la seule maniere reelle d'obtenir une
    frequence elevee est de faire sortir l'image de la VM par un logiciel de
    streaming DEDIE au lieu de vmconnect. Sunshine (cote VM, capture l'ecran
    accelere par GPU-P et l'encode) + Moonlight (cote client, decode et
    affiche a la vraie frequence configuree) est la solution standard,
    largement utilisee pour exactement ce scenario (VM GPU-P + haut taux de
    rafraichissement).

    Ce script prepare tout ce qui est automatisable SANS identifiants de
    session dans l'invite (login/mot de passe de la VM inconnus de NovaVM) :
    - installe Moonlight (client) sur l'HOTE, silencieusement, via winget ;
    - active l'integration Hyper-V necessaire (Interface de services invite)
      pour pouvoir deposer un fichier dans la VM sans reseau ;
    - telecharge l'installeur Sunshine (via winget download, paquet
      officiel verifie) et le depose sur le Bureau public de la VM
      (Copy-VMFile, necessite la VM demarree).

    Etapes manuelles restantes, obligatoires et non contournables (elles ne
    peuvent pas etre automatisees sans connaitre les identifiants de session
    de la VM, et l'appariement Sunshine/Moonlight est volontairement protege
    par un code a usage unique) :
    1. Dans la VM, double-cliquer sur "Installer-Sunshine.msi" sur le Bureau.
    2. Suivre l'assistant Sunshine (cree un compte pour son interface web).
    3. Sur l'hote, ouvrir Moonlight, ajouter l'ordinateur (adresse de la VM),
       entrer le code PIN affiche par Sunshine pour terminer l'appariement.
    4. Dans Sunshine, regler la resolution/frequence souhaitee (60/70/100/120/144 Hz) :
       c'est LA ou la frequence reelle se configure desormais, plus dans NovaVM.
#>
param(
    [Parameter(Mandatory)][string]$Name
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour recevoir l'installeur Sunshine (Copy-VMFile necessite une VM active)."
    }

    Write-NovaProgress "Installation de Moonlight (client) sur cet ordinateur"
    $wingetArgs = @("install", "--id", "MoonlightGameStreamingProject.Moonlight", "-e",
        "--accept-package-agreements", "--accept-source-agreements", "--silent")
    & winget.exe @wingetArgs | Out-Null
    # Ne pas se fier au seul code de sortie winget : il est non-zero si le
    # paquet est deja installe (pas un echec reel). On verifie l'etat final.
    $moonlightListOutput = & winget.exe list --id "MoonlightGameStreamingProject.Moonlight" -e --accept-source-agreements 2>&1
    $moonlightInstalled = ($LASTEXITCODE -eq 0) -and ($moonlightListOutput -join "`n") -match "MoonlightGameStreamingProject\.Moonlight"

    Write-NovaProgress "Activation de l'interface de services invite (necessaire pour deposer un fichier)"
    # Le nom de ce composant est localise ("Interface de services d'invite" en
    # francais) : on le trouve via son GUID stable/independant de la langue
    # (6C09BB55-D683-4DA0-8931-C9BF705F6480), pas par -Name (piege verifie
    # empiriquement, meme cause que pour le groupe "Hyper-V Administrators").
    $guestServiceInterface = Get-VMIntegrationService -VMName $Name -ErrorAction Stop |
        Where-Object { $_.Id -like "*6C09BB55-D683-4DA0-8931-C9BF705F6480*" } | Select-Object -First 1
    if (-not $guestServiceInterface) {
        throw "Le composant d'integration 'Interface de services invite' est introuvable sur cette VM."
    }
    if (-not $guestServiceInterface.Enabled) {
        # Passer l'objet (pas -Name, localise) : Enable-VMIntegrationService
        # accepte -VMIntegrationService <VMIntegrationComponent[]> directement.
        Enable-VMIntegrationService -VMIntegrationService $guestServiceInterface -ErrorAction Stop

        # Verifie empiriquement : la premiere activation de ce composant ne
        # devient utilisable par Copy-VMFile qu'APRES un redemarrage complet de
        # la VM (le service correspondant cote invite doit demarrer a l'amorcage).
        # Continuer immediatement echoue systematiquement (0x800710DF, "peripherique
        # pas pret") : mieux vaut le dire clairement que de laisser echouer Copy-VMFile
        # avec un message HRESULT peu comprehensible.
        throw "L'interface de services invite vient d'etre activee pour la premiere fois sur cette VM. Redemarrez la VM (Arreter puis Demarrer) puis relancez cette action : elle ne sera utilisable par Copy-VMFile qu'apres un redemarrage complet."
    }

    Write-NovaProgress "Telechargement de Sunshine (paquet officiel, via winget)"
    $downloadDir = "C:\NovaVM\Downloads\Sunshine"
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    Get-ChildItem $downloadDir -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $downloadArgs = @("download", "--id", "LizardByte.Sunshine", "-d", $downloadDir,
        "--accept-package-agreements", "--accept-source-agreements")
    & winget.exe @downloadArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Le telechargement de Sunshine via winget a echoue (code $LASTEXITCODE)."
    }
    $installer = Get-ChildItem $downloadDir -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installer) {
        throw "Le paquet Sunshine telecharge ne contient pas de fichier .msi dans $downloadDir."
    }

    Write-NovaProgress "Depot de l'installeur sur le Bureau de la VM"
    try {
        Copy-VMFile -VMName $Name -SourcePath $installer.FullName `
            -DestinationPath "C:\Users\Public\Desktop\Installer-Sunshine.msi" `
            -CreateFullPath -FileSource Host -Force -ErrorAction Stop
    } catch {
        throw "Copy-VMFile a echoue : $($_.Exception.Message). Verifiez que l'invite a bien demarre completement (pas seulement l'ecran de demarrage) et reessayez."
    }

    $result = [ordered]@{
        vmName              = $Name
        moonlightInstalledOnHost = $moonlightInstalled
        sunshineInstallerPath    = "C:\Users\Public\Desktop\Installer-Sunshine.msi (dans la VM)"
        nextSteps = @(
            "1. Dans la VM : double-cliquer sur 'Installer-Sunshine.msi' sur le Bureau et terminer l'installation.",
            "2. Suivre l'assistant Sunshine (creation d'un compte pour son interface web).",
            "3. Sur cet ordinateur : ouvrir Moonlight, ajouter la VM, entrer le code PIN affiche par Sunshine.",
            "4. Dans Sunshine : regler la resolution et la frequence reellement voulues (60 a 144 Hz) - c'est la que ca se configure desormais, pas dans NovaVM."
        ) -join "`n"
        message = "Preparation terminee. Etapes manuelles restantes (non automatisables : identifiants de session et appariement securise) listees ci-dessus."
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
