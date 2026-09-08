; Script Inno Setup pour SPLYT - genere l'installateur autonome (.exe) a partir
; de la publication self-contained (voir README de ce dossier pour la commande
; de publication a relancer avant de recompiler cet installateur).
;
; AppId fixe (genere une seule fois) : NE JAMAIS changer entre les versions,
; sinon Windows considere chaque nouvelle build comme une appli differente au
; lieu d'une mise a jour (deux entrees dans "Applications installees", pas de
; desinstallation automatique de l'ancienne version).
#define MyAppId "{{63D8885A-B8AF-4801-B413-86134D4B8290}"
#define MyAppName "SPLYT"
#define MyAppVersion "0.5.5"
#define MyAppPublisher "SPLYT"
#define MyAppExeName "NovaVM.Gui.exe"
#define MyPublishDir "..\gui\NovaVM.Gui\bin\Release\publish-win-x64"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=SPLYT-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\gui\NovaVM.Gui\Assets\AppIcon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
MinVersion=10.0.19041
; Pas de code non signe execute par l'installateur lui-meme (juste une copie de
; fichiers) : SmartScreen peut quand meme avertir au premier lancement tant que
; l'exe n'est pas signe par un certificat reconnu - normal pour une premiere
; version distribuee hors store, pas un signe de probleme reel.

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Creer une icone sur le Bureau"; GroupDescription: "Icones supplementaires :"

[Files]
Source: "{#MyPublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstaller {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent
