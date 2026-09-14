<#
    NovaVm.Unattend.psm1

    Fabrique le "fichier de reponses" (autounattend.xml) qui installe Windows 11
    sans aucune intervention, et l'emballe dans une petite image ISO que la VM lit
    au demarrage.

    POURQUOI UNE ISO A PART, et pas une modification de l'ISO de Windows :
    reconstruire l'image officielle demanderait de l'extraire, d'y injecter le
    fichier et de la regraver - plusieurs Go copies, et une image qui n'est plus
    celle signee par Microsoft. Le programme d'installation cherche de lui-meme
    "autounattend.xml" a la racine de TOUS les lecteurs amovibles : un second
    lecteur DVD de quelques dizaines de kilo-octets suffit donc, et l'ISO de
    Windows reste intacte.

    L'image est fabriquee avec IMAPI2, le composant de gravure livre avec Windows :
    aucun outil tiers a installer, contrairement a oscdimg qui demande le kit
    ADK complet.

    MOT DE PASSE : Windows n'offre pas de vraie protection dans un fichier de
    reponses. Le format "PlainText=false" n'est qu'un encodage base64, trivialement
    reversible - le documenter honnetement vaut mieux que de laisser croire a un
    chiffrement. On l'utilise quand meme, pour qu'un mot de passe ne s'affiche pas
    en clair a l'ecran pendant l'installation, et l'ISO de reponses est supprimee
    des que Windows est installe (voir Remove-NovaUnattendIso).
#>

$ErrorActionPreference = "Stop"

# Chemin ou sont gardees les ISO de reponses, le temps de l'installation.
$script:UnattendDir = "C:\NovaVM\Unattend"

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public class NovaIsoWriter {
    /// <summary>Ecrit sur disque le flux produit par IMAPI2. L'objet rendu par
    /// CreateResultImage expose un IStream COM, que .NET ne sait pas copier
    /// directement dans un fichier : on le lit par blocs.</summary>
    public static void Save(object comStream, string path) {
        IStream stream = (IStream)comStream;
        using (FileStream file = File.Create(path)) {
            byte[] buffer = new byte[64 * 1024];
            IntPtr read = Marshal.AllocHGlobal(sizeof(int));
            try {
                while (true) {
                    stream.Read(buffer, buffer.Length, read);
                    int n = Marshal.ReadInt32(read);
                    if (n <= 0) break;
                    file.Write(buffer, 0, n);
                }
            } finally {
                Marshal.FreeHGlobal(read);
            }
        }
    }
}
"@

# Encodage attendu par Windows pour un mot de passe "non affiche" : base64 de la
# chaine UTF-16LE formee du mot de passe suivi du nom de l'element qui le porte.
# Ce n'est PAS du chiffrement.
function ConvertTo-NovaUnattendPassword {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Password,
        [Parameter(Mandatory)][string]$ElementName
    )
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Password + $ElementName)
    return [Convert]::ToBase64String($bytes)
}

function Get-NovaUnattendXml {
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Password,
        [Parameter(Mandatory)][string]$ComputerName,
        # Nom exact de l'edition dans l'image ("Windows 11 Pro"). Doit correspondre
        # a une edition presente dans l'ISO, sinon l'installation s'arrete en
        # demandant laquelle installer - ce qui ruinerait l'automatisation.
        [string]$Edition = "Windows 11 Pro",
        [string]$Locale = "fr-FR"
    )

    $passwordAccount = ConvertTo-NovaUnattendPassword -Password $Password -ElementName "Password"

    # Cle generique publique de Windows 11 Pro. Elle n'active rien : elle sert
    # uniquement a dire au programme d'installation QUELLE edition installer, pour
    # qu'il ne pose pas la question. L'activation reste a faire ensuite, comme
    # avec une installation manuelle.
    $genericKey = "VK7JG-NPHTM-C97JM-9MPGT-3V66T"

    @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <SetupUILanguage>
        <UILanguage>$Locale</UILanguage>
      </SetupUILanguage>
      <InputLocale>$Locale</InputLocale>
      <SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage>
      <UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <DiskConfiguration>
        <!-- Le disque de la VM est neuf : on le partitionne en GPT comme le ferait
             l'installateur, sans rien demander. WillWipeDisk efface un disque
             deja utilise, ce qui rend l'installation reproductible. -->
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order><Type>EFI</Type><Size>300</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order><Type>MSR</Type><Size>16</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order><Type>Primary</Type><Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order><PartitionID>1</PartitionID><Label>Systeme</Label><Format>FAT32</Format>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order><PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order><PartitionID>3</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
          <!-- L'edition n'est PAS nommee ici. La cle generique ci-dessous suffit a
               la designer, et elle a l'avantage de fonctionner quelle que soit la
               facon dont l'image nomme ses editions : exiger "Windows 11 Pro" au
               mot pres ferait echouer l'installation sur une ISO dont le
               catalogue differe, et l'utilisateur se retrouverait devant le choix
               manuel que l'on cherche justement a eviter. -->
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey><Key>$genericKey</Key></ProductKey>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$ComputerName</ComputerName>
    </component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <!-- Les choix de personnalisation sont poses ICI, pendant l'installation,
           et non a la premiere ouverture de session : personne ne s'etant encore
           connecte, des commandes de premiere session ne se seraient executees
           qu'au moment ou l'utilisateur ouvre enfin la sienne - c'est-a-dire trop
           tard, et seulement s'il le fait. Constate en essai reel : machine
           installee, mais tous les reglages absents. -->
      <!-- L'enveloppe <RunSynchronous> n'est pas decorative : sans elle, Windows
           considere chaque <RunSynchronousCommand> comme un reglage repete dans
           la meme section, declare TOUT le fichier de reponses invalide, et
           l'installation s'arrete sur "L'installation de Windows ne peut pas
           continuer". Diagnostique dans Panther\setuperr.log : "Les parametres
           n'appartenant pas a une liste ne doivent pas etre specifies deux fois
           dans une meme section de parametres". -->
      <RunSynchronous>
$(Get-NovaUnattendSpecializeCommands)
      </RunSynchronous>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>$Locale</InputLocale>
      <SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage>
      <UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <!-- Chaque page que Windows poserait a l'utilisateur est repondue ici.
             ProtectYourPC = 3 refuse les "parametres express" en bloc : c'est le
             reglage qui met a NON la publicite ciblee, les experiences
             personnalisees, la localisation et l'envoi de donnees facultatives. -->
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
        <NetworkLocation>Home</NetworkLocation>
        <!-- Volontairement PAS de SkipMachineOOBE/SkipUserOOBE : Microsoft les
             documente comme depreciees, et elles laissent parfois un profil
             utilisateur a moitie configure. Les pages sont deja toutes
             repondues par ce qui precede et par le compte local ci-dessous. -->
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$Username</Name>
            <DisplayName>$Username</DisplayName>
            <Group>Administrators</Group>
            <Password>
              <Value>$passwordAccount</Value>
              <PlainText>false</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <!-- Pas de <AutoLogon> ici : SPLYT pose l'ouverture de session automatique
           lui-meme, avec le mot de passe range dans le secret LSA plutot qu'en
           clair dans le registre (voir Set-NovaVmAutoLogon.ps1). -->
      <FirstLogonCommands>
$(Get-NovaUnattendPrivacyCommands)
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

# Une seule commande, executee pendant l'installation, qui pose tous les choix de
# personnalisation.
#
# Deux endroits a servir, et c'est ce qui rend la chose moins triviale qu'il n'y
# parait :
#   - la machine (HKLM), pour les strategies qui valent pour tout le monde ;
#   - le PROFIL PAR DEFAUT, dont herite chaque compte cree ensuite. On charge
#     donc C:\Users\Default\NTUSER.DAT le temps d'y ecrire. Sans cette partie, les
#     reglages "par utilisateur" n'existeraient pour personne, puisque le compte
#     n'est meme pas encore cree a ce stade.
function Get-NovaUnattendSpecializeCommands {
    $lignes = @()

    foreach ($c in (Get-NovaUnattendMachineCommands)) { $lignes += $c }

    # Le profil par defaut : monte, ecrit, demonte. Le demontage doit suivre quoi
    # qu'il arrive - une ruche laissee chargee empeche la creation des profils.
    $lignes += 'reg load "HKU\SplytDefaut" "C:\Users\Default\NTUSER.DAT"'
    foreach ($c in (Get-NovaUnattendUserCommands -Root 'HKU\SplytDefaut')) { $lignes += $c }
    $lignes += 'reg unload "HKU\SplytDefaut"'

    # Signal de fin d'installation, a destination de l'hote.
    #
    # SetupComplete.cmd est le crochet que Windows execute tout a la fin de
    # l'installation, une fois l'OOBE terminee et AVANT l'ecran de connexion,
    # sous le compte systeme. C'est le seul endroit qui corresponde vraiment a
    # "Windows est installe" : les FirstLogonCommands, elles, attendent une
    # ouverture de session qui n'arrive jamais toute seule ici, puisque SPLYT ne
    # pose l'ouverture automatique qu'ensuite, a la configuration en un clic.
    #
    # Ce qu'il ecrit ressort cote hote dans
    # Msvm_KvpExchangeComponent.GuestExchangeItems (voir
    # Watch-NovaVmInstallComplete.ps1), sans identifiants ni reseau.
    #
    # En DEUX commandes courtes, et pas une seule lisible : le champ Path d'un
    # RunSynchronousCommand est plafonne a 259 caracteres. Une version en une
    # ligne (PowerShell + Set-Content) en faisait 356 : tronquee, elle perdait
    # son "exit /b 0" final, et une commande de cette phase qui rend une erreur
    # INTERROMPT TOUTE L'INSTALLATION. Constate en essai reel - l'installeur
    # s'arretait sur "L'ordinateur a redemarre de maniere inattendue".
    #
    # Le "& rem" final est la pour la redirection : chaque ligne de cette phase
    # se voit ajouter " >nul 2>&1", qui capterait le ">" de l'echo et laisserait
    # le fichier vide. En fermant la commande par "& rem", la redirection ajoutee
    # s'applique a un commentaire, et l'echo garde la sienne.
    $lignes += 'md C:\Windows\Setup\Scripts'
    $lignes += 'echo reg add "HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest" /v SplytInstallComplete /t REG_SZ /d 1 /f>C:\Windows\Setup\Scripts\SetupComplete.cmd & rem'

    # Une entree par commande, plutot qu'une seule ligne geante : le champ Path a
    # une longueur bornee, et une commande unique de deux mille caracteres serait
    # tronquee sans rien dire. Les entrees s'executent dans l'ordre, ce qui est
    # exactement ce qu'il faut pour encadrer les ecritures par le chargement et le
    # dechargement de la ruche.
    $ordre = 1
    $blocs = foreach ($ligne in $lignes) {
        # "exit /b 0" n'est pas une precaution de style : Windows Setup
        # INTERROMPT TOUTE L'INSTALLATION si une commande de cette phase rend un
        # code d'erreur, avec le laconique "L'installation de Windows ne peut pas
        # continuer". Constate en essai reel, provoque par un "reg unload" qui
        # echoue quand la ruche est encore referencee. Un reglage de confort ne
        # doit jamais pouvoir couter l'installation entiere.
        $echappee = [System.Security.SecurityElement]::Escape("$ligne >nul 2>&1 & exit /b 0")
        @"
      <RunSynchronousCommand wcm:action="add">
        <Order>$ordre</Order>
        <Path>cmd /c $echappee</Path>
        <Description>Personnalisation</Description>
      </RunSynchronousCommand>
"@
        $ordre++
    }
    return ($blocs -join "`n")
}

# Strategies valables pour toute la machine.
function Get-NovaUnattendMachineCommands {
    return @(
        # Publicite ciblee : verrouillee par strategie, pour qu'elle ne puisse pas
        # etre reactivee silencieusement.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f',
        # Donnees de diagnostic reduites au strict necessaire.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f',
        # Localisation.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v DisableLocation /t REG_DWORD /d 1 /f',
        # Localiser mon appareil.
        'reg add "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v LocationSyncEnabled /t REG_DWORD /d 0 /f',
        # Contenu suggere et installation automatique d'applications : c'est ce qui
        # fait apparaitre des jeux et des raccourcis promotionnels dans le menu
        # Demarrer d'un Windows fraichement installe.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f'
    )
}

# Reglages par utilisateur, ecrits sous la racine donnee : la ruche du profil par
# defaut pendant l'installation, HKCU a la premiere ouverture de session.
function Get-NovaUnattendUserCommands {
    param([Parameter(Mandatory)][string]$Root)

    return @(
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo`" /v Enabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy`" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy`" /v HasAccepted /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Input\TIPC`" /v Enabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\InputPersonalization`" /v RestrictImplicitTextCollection /t REG_DWORD /d 1 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\InputPersonalization`" /v RestrictImplicitInkCollection /t REG_DWORD /d 1 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore`" /v HarvestContacts /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f",
        "reg add `"$Root\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f"
    )
}

# Filet de securite a la premiere ouverture de session : le profil par defaut
# couvre les comptes crees APRES l'ecriture, mais le compte de l'installation est
# cree dans la foulee et Windows peut avoir deja fige certaines valeurs.
function Get-NovaUnattendPrivacyCommands {
    $commandes = @(
        # Publicite ciblee : identifiant publicitaire par utilisateur, et la
        # strategie machine qui empeche de le reactiver.
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f',
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f',
        # Experiences personnalisees a partir des donnees de diagnostic.
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f',
        # Donnees de diagnostic reduites au strict necessaire.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f',
        # Localisation.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v DisableLocation /t REG_DWORD /d 1 /f',
        # Localiser mon appareil.
        'reg add "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v LocationSyncEnabled /t REG_DWORD /d 0 /f',
        # Reconnaissance vocale en ligne.
        'reg add "HKCU\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" /v HasAccepted /t REG_DWORD /d 0 /f',
        # Amelioration de l'ecriture manuscrite et de la saisie : envoi des mots
        # frappes a Microsoft.
        'reg add "HKCU\SOFTWARE\Microsoft\Input\TIPC" /v Enabled /t REG_DWORD /d 0 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitTextCollection /t REG_DWORD /d 1 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitInkCollection /t REG_DWORD /d 1 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" /v HarvestContacts /t REG_DWORD /d 0 /f',
        # Contenu suggere et installation automatique d'applications : c'est ce
        # qui fait apparaitre des jeux et des raccourcis promotionnels dans le
        # menu Demarrer d'un Windows fraichement installe.
        'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f',
        'reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f',
        # Doublon volontaire du signal de fin pose par SetupComplete.cmd (voir
        # Get-NovaUnattendSpecializeCommands) : si ce crochet n'a pas pu s'ecrire,
        # une ouverture de session finit quand meme par le poser. Ne remplace pas
        # SetupComplete.cmd, qui lui n'attend aucune session.
        'reg add "HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest" /v SplytInstallComplete /t REG_SZ /d 1 /f'
    )

    $ordre = 1
    $blocs = foreach ($commande in $commandes) {
        $echappee = [System.Security.SecurityElement]::Escape($commande)
        @"
        <SynchronousCommand wcm:action="add">
          <Order>$ordre</Order>
          <CommandLine>cmd /c $echappee</CommandLine>
          <Description>Personnalisation : desactivation</Description>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
"@
        $ordre++
    }
    return ($blocs -join "`n")
}

# Fabrique l'ISO qui porte le fichier de reponses, et rend son chemin.
# Vrai si l'image d'installation porte DEJA son propre autounattend.xml a sa
# racine. Windows Setup cherche un fichier de reponses sur tous les medias
# amovibles et retient le PREMIER trouve : celui du media de demarrage passe
# donc avant le notre, monte sur un second lecteur. Le cas est frequent avec
# les images remaniees (tiny11 et compagnie), et il est silencieux : leur
# fichier ne repond souvent qu'a une poignee de questions, l'installation
# s'arrete alors sur le premier ecran venu sans dire pourquoi - avec, cote
# SPLYT, une VM cachee derriere une barre qui n'avance plus.
#
# Monte l'image en lecture seule le temps du test. Best-effort : si le montage
# echoue (image deja montee ailleurs, fichier verrouille), on repond "non" et
# l'installation suit son cours normal - mieux vaut rater un avertissement que
# refuser une image parfaitement valable.
function Test-NovaIsoHasOwnAnswerFile {
    param([Parameter(Mandatory)][string]$IsoPath)

    # Si l'image est deja montee (l'utilisateur l'explore dans son explorateur,
    # par exemple), on se contente de la lire : la demonter derriere lui ferait
    # disparaitre son lecteur sous ses yeux.
    $dejaMontee = $false
    try { $dejaMontee = [bool](Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop).Attached } catch { }

    $mounted = $null
    try {
        $mounted = if ($dejaMontee) {
            Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop
        } else {
            Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -PassThru -ErrorAction Stop
        }
        $letter = ($mounted | Get-Volume -ErrorAction Stop).DriveLetter
        if (-not $letter) { return $false }
        foreach ($nom in @("autounattend.xml", "unattend.xml")) {
            if (Test-Path -LiteralPath "${letter}:\$nom") { return $true }
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($mounted -and -not $dejaMontee) {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function New-NovaUnattendIso {
    param(
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Password,
        [string]$Edition = "Windows 11 Pro",
        [string]$Locale = "fr-FR"
    )

    # Le nom d'ordinateur ne peut pas depasser 15 caracteres ni contenir
    # n'importe quoi : on derive un nom valide du nom de la VM plutot que de
    # laisser l'installation echouer sur un nom refuse.
    $computerName = ($VmName -replace '[^A-Za-z0-9\-]', '-')
    if ($computerName.Length -gt 15) { $computerName = $computerName.Substring(0, 15) }
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = "SPLYT-VM" }

    $xml = Get-NovaUnattendXml -Username $Username -Password $Password `
        -ComputerName $computerName -Edition $Edition -Locale $Locale

    # Controle de forme avant de graver : une ISO qui porte un XML invalide
    # provoque une installation qui repart en mode manuel sans rien expliquer.
    try {
        [void][xml]$xml
    } catch {
        throw "Le fichier de reponses genere est invalide : $($_.Exception.Message)"
    }

    $staging = Join-Path $env:TEMP ("splyt-unattend-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        # Sans BOM : le programme d'installation lit mal un XML qui en porte un.
        [System.IO.File]::WriteAllText(
            (Join-Path $staging "autounattend.xml"), $xml, (New-Object System.Text.UTF8Encoding($false)))

        New-Item -ItemType Directory -Path $script:UnattendDir -Force | Out-Null
        $isoPath = Join-Path $script:UnattendDir ("$VmName-reponses.iso")
        if (Test-Path -LiteralPath $isoPath) { Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue }

        $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fsi.FileSystemsToCreate = 3   # ISO9660 + Joliet
        $fsi.VolumeName = "SPLYT_AUTO"
        $fsi.Root.AddTree($staging, $false)
        $image = $fsi.CreateResultImage()
        [NovaIsoWriter]::Save($image.ImageStream, $isoPath)

        if (-not (Test-Path -LiteralPath $isoPath)) {
            throw "L'image du fichier de reponses n'a pas ete creee."
        }
        return $isoPath
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Retire l'ISO de reponses de la VM et l'efface : elle porte le mot de passe, et
# n'a plus aucune raison d'exister une fois Windows installe.
function Remove-NovaUnattendIso {
    param([Parameter(Mandatory)][string]$VmName)

    $isoPath = Join-Path $script:UnattendDir ("$VmName-reponses.iso")

    foreach ($drive in @(Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue)) {
        if ($drive.Path -and $drive.Path -eq $isoPath) {
            Remove-VMDvdDrive -VMDvdDrive $drive -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $isoPath) {
        Remove-Item -LiteralPath $isoPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function New-NovaUnattendIso, Remove-NovaUnattendIso, Get-NovaUnattendXml, Test-NovaIsoHasOwnAnswerFile
