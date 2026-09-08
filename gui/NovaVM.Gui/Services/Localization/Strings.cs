namespace NovaVM.Gui.Services.Localization;

/// <summary>Tables de traduction francais/anglais - voir Loc.cs. Cles groupees par
/// ecran/controle (commentaires) pour rester reperables malgre le volume.</summary>
internal static class Strings
{
    public static readonly Dictionary<string, string> French = new()
    {
        // --- Commun ---
        ["Common_Yes"] = "Oui",
        ["Common_No"] = "Non",

        // --- Coquille principale / navigation ---
        ["App_Subtitle"] = "Gestionnaire de VM GPU-P",
        ["Nav_Dashboard"] = "Accueil",
        ["Nav_VmList"] = "Machines virtuelles",
        ["Nav_Gpu"] = "GPU",
        ["Nav_Storage"] = "Stockage",
        ["Nav_Journal"] = "Journal",
        ["Nav_Settings"] = "Parametres",
        ["Common_Refresh"] = "Actualiser",
        ["Common_GbUnit"] = " Go",

        // --- Accueil ---
        ["Dashboard_Subtitle"] = "Vue d'ensemble de l'hote et des machines virtuelles",
        ["Dashboard_NoVms"] = "Aucune VM pour le moment.",
        ["Dashboard_RecentAlerts"] = "Alertes recentes",
        ["Dashboard_NoAlerts"] = "Aucune alerte. Tout fonctionne normalement.",

        // --- GPU ---
        ["Gpu_Subtitle"] = "GPU physiques de l'hote et partitionnement GPU-P",
        ["Gpu_PartitionSupported"] = "GPU-P pris en charge",
        ["Gpu_PartitionNotSupported"] = "GPU-P non pris en charge",
        ["Gpu_Driver"] = "Pilote : ",
        ["Gpu_VmsUsingThisGpu"] = "VMs utilisant ce GPU : ",
        ["Gpu_NoGpuDetected"] = "Aucun GPU detecte.",

        // --- Stockage ---
        ["Storage_Subtitle"] = "Disques virtuels (VHDX) des machines NovaVM",
        ["Storage_ColumnFile"] = "Fichier",
        ["Storage_ColumnSize"] = "Taille",
        ["Storage_ColumnAttachedVm"] = "VM attachee",
        ["Storage_NoneAttached"] = "Aucune",
        ["Storage_NoDisks"] = "Aucun disque pour le moment.",

        // --- Journal ---
        ["Journal_Subtitle"] = "Historique des operations effectuees sur les VMs (le plus recent en premier)",

        // --- Parametres ---
        ["Settings_Title"] = "Parametres",
        ["Settings_Subtitle"] = "Preferences et diagnostic de l'environnement Hyper-V/GPU-P",
        ["Settings_RefreshDiagnostics"] = "Reactualiser le diagnostic",
        ["Settings_DiagnosticTitle"] = "Diagnostic",
        ["Settings_HyperVModuleInstalled"] = "Module PowerShell Hyper-V installe",
        ["Settings_CanListVms"] = "Acces en lecture aux VMs Hyper-V",
        ["Settings_CanListGpus"] = "Acces aux GPU partitionnables (GPU-P)",
        ["Settings_IsElevated"] = "Session administrateur",
        ["Settings_DiagnosticNote"] = "Sans acces Hyper-V/GPU-P, l'appli continue de fonctionner avec des donnees simulees. Ajouter ce compte au groupe local 'Hyper-V Administrators' (ou executer en administrateur) sera necessaire pour piloter de vraies VMs.",

        ["Settings_ReportTitle"] = "Signaler un probleme",
        ["Settings_ReportDesc"] = "Copie dans le presse-papiers tout ce qui rend un rapport de bug exploitable : modele exact du processeur et de la carte graphique, version du pilote, edition et build de Windows, etat de vos VMs et dernieres erreurs. Deux pannes GPU-P de causes differentes donnent souvent le meme symptome vu de l'exterieur : sans ces details, elles sont impossibles a distinguer. Ne contient aucun mot de passe, et les chemins contenant votre nom d'utilisateur sont masques.",
        ["Settings_CopyReport"] = "Copier le rapport de diagnostic",
        ["Settings_ReportCopied"] = "Rapport copie. Collez-le dans votre rapport de bug (Ctrl+V), avec une capture d'ecran du premier ecran ou le probleme apparait.",
        ["Settings_ReportCopyFailed"] = "Impossible d'acceder au presse-papiers : {0}",
        ["Settings_PreferencesTitle"] = "Preferences",
        ["Settings_DefaultDiskPath"] = "Dossier par defaut des disques virtuels",
        ["Settings_AutoSelectGpu"] = "Selectionner automatiquement le GPU pour GPU-P",
        ["Settings_DarkTheme"] = "Theme sombre",
        ["Settings_PreferencesNote"] = "(Reglages conserves en memoire pour ce prototype ; la persistance sur disque viendra ensuite.)",
        ["Settings_LanguageTitle"] = "Langue",
        ["Settings_LanguageNote"] = "Change la langue de l'interface de SPLYT.",
        ["Settings_LanguageRestartNotice"] = "Redemarrez SPLYT pour appliquer le changement de langue.",
        ["Settings_RestartNow"] = "Redemarrer maintenant",
        ["Settings_AboutTitle"] = "A propos",
        ["Settings_AboutRoadmap"] = "Voir Claude.md a la racine du depot pour la feuille de route complete.",

        // --- Communs additionnels ---
        ["Common_Delete"] = "Supprimer",
        ["Common_Save"] = "Enregistrer",
        ["Common_Diagnose"] = "Diagnostiquer",
        ["Common_Browse"] = "Parcourir...",

        // --- Machines virtuelles (liste + detail) ---
        ["VmList_Subtitle"] = "Creer, configurer et piloter vos VMs",
        ["VmList_CreateVm"] = "+  Creer une VM",
        ["VmList_MachinesHeader"] = "Machines",
        ["VmList_Start"] = "Demarrer",
        ["VmList_Stop"] = "Arreter",
        ["VmList_Stop_Tooltip"] = "Arret normal (equivalent a demarrer l'arret depuis le menu Demarrer de Windows).",
        ["VmList_StopChoice_Title"] = "Arreter la VM",
        ["VmList_StopChoice_Message"] = "Comment voulez-vous arreter '{0}' ?\n\nArret classique : demande a Windows de s'arreter proprement, comme depuis son menu Demarrer (rien n'est perdu).\n\nArret force : coupe l'alimentation immediatement, comme un appui long sur le bouton d'alimentation. A n'utiliser que si l'arret classique ne repond pas - le travail non enregistre dans la VM sera perdu.",
        ["VmList_StopChoice_Normal"] = "Arret classique",
        ["VmList_StopChoice_Forced"] = "Arret force",
        ["VmList_DeleteConfirm_Title"] = "Supprimer la VM",
        ["VmList_DeleteConfirm_Message"] = "Supprimer definitivement la VM '{0}' ?\n\nSa configuration Hyper-V et son disque virtuel seront effaces. Cette action est irreversible.",
        ["VmList_IsoMounted"] = "ISO montee : ",
        ["VmList_NoSelection"] = "Selectionnez une VM ou creez-en une nouvelle.",

        ["VmList_Tab_Resources"] = "Ressources",
        ["VmList_Tab_Display"] = "Affichage",

        ["VmList_Res_Vcpu"] = "Processeurs virtuels (vCPU)",
        ["VmList_Res_Ram"] = "Memoire vive (Go)",
        ["VmList_Res_PhysicalRamDetected"] = "RAM physique detectee : ",
        ["VmList_Res_MaxForVm"] = " Go - maximum pour une VM : ",
        ["VmList_Res_RamWarning"] = "Attention : vous attribuez une grande partie de la RAM de cet ordinateur a la VM.",
        ["VmList_Res_CpuDetected"] = "Processeur detecte : ",
        ["VmList_Res_CpuCores"] = " coeurs physiques (",
        ["VmList_Res_CpuThreads"] = " threads) - le maximum pour une VM est limite aux coeurs physiques.",

        ["VmList_Credentials_UsernameLabel"] = "Nom d'utilisateur : compte local Windows OU compte Microsoft",
        ["VmList_Credentials_PasswordLabel"] = "Mot de passe",
        ["VmList_Credentials_Remember"] = "Se souvenir de mes identifiants",
        ["VmList_Credentials_MicrosoftHint_Part1"] = "Compte Microsoft : indiquez juste votre e-mail, ex. ",
        ["VmList_Credentials_MicrosoftHint_Part2"] = " (le prefixe technique est ajoute automatiquement). Compte local : indiquez le nom affiche sur l'ecran de connexion de la VM.",
        ["VmList_Credentials_StorageNote"] = "Ces identifiants sont ceux que vous avez definis en installant Windows dans cette VM. Ils ne sont ni stockes, ni journalises, sauf si vous cochez la case ci-dessus (Gestionnaire d'identifiants Windows, chiffre - supprimable a tout moment dans le Panneau de configuration).",

        ["VmList_Gaming_Header"] = "Optimisations gaming",
        ["VmList_Gaming_Intro"] = "Applique des reglages Windows courants pour le jeu (equivalents a des outils comme WinToys), directement dans la VM.",
        ["VmList_Gaming_PerformanceTitle"] = "Performances",
        ["VmList_Gaming_PerformanceDesc"] = "Profil d'alimentation Ultimate Performance, Hardware-accelerated GPU scheduling (si disponible), securite basee sur la virtualisation (VBS) desactivee, demarrage rapide desactive. Redemarrage de la VM conseille apres application.",
        ["VmList_Gaming_OptimizePerformance"] = "Optimiser les performances",
        ["VmList_Gaming_PrivacyTitle"] = "Vie privee",
        ["VmList_Gaming_PrivacyDesc"] = "Reduit la telemetrie Windows au minimum, desactive l'identifiant publicitaire et la localisation de facon permanente.",
        ["VmList_Gaming_ReduceTracking"] = "Reduire le tracking Microsoft",

        ["VmList_Gpu_Partitioned"] = "GPU partitionne",
        ["VmList_Gpu_VramAllocated"] = "VRAM allouee (Mo)",
        ["VmList_Gpu_NoDedicatedVram"] = "Ce GPU n'a pas de VRAM dediee (processeur graphique integre : il puise dans la RAM systeme). Il n'y a donc rien a doser ici - Hyper-V repartit automatiquement la memoire graphique entre l'hote et la VM.",
        ["VmList_Gpu_InstallDriverInProgress"] = "Preparation du pilote GPU-P en cours - la copie du magasin de pilotes represente plusieurs Go, comptez quelques minutes. Ne fermez pas SPLYT.",
        ["VmList_Gpu_InstallDriver"] = "Installer le pilote",
        ["VmList_Gpu_InstallDriver_Tooltip"] = "Copie hors-ligne le pilote du GPU hote dans le disque de la VM (DISM). Necessite une elevation (invite administrateur) et que la VM soit eteinte.",

        ["VmList_Nvidia_Header"] = "Bidouille NVIDIA (non officielle)",
        ["VmList_Nvidia_Warning"] = "NVIDIA bloque volontairement ses GPU GeForce dans les VM. Ceci patche votre pilote pour contourner ce blocage - technique communautaire non officielle, abandonnee depuis 2021 : de bonnes chances d'echouer proprement (message clair) si votre pilote est trop recent. Ne modifie rien si aucun motif ne correspond. Necessite d'avoir deja fait 'Installer le pilote' ci-dessus au moins une fois, et que la VM soit eteinte.",
        ["VmList_Nvidia_InstallerLabel"] = "Installeur du pilote NVIDIA (telecharge depuis nvidia.com - meme version que celle installee sur cet hote)",
        ["VmList_Nvidia_PatchButton"] = "Patcher et installer (bidouille)",
        ["VmList_Nvidia_PatchButton_Tooltip"] = "Peut telecharger plusieurs centaines de Mo (7-Zip, Windows Driver Kit) la premiere fois, et prendre plusieurs minutes. Le disque de la VM sera monte hors-ligne : ne fermez pas SPLYT pendant l'operation.",

        ["VmList_Display_HzWarning_Part1"] = "Important : vmconnect (session Basique ou Amelioree) est plafonne a ",
        ["VmList_Display_HzWarning_Part2"] = ", meme avec GPU-P actif - il n'existe pas de reglage pour depasser cette limite via vmconnect. Pour 100+ Hz, utilisez le streaming Sunshine/Moonlight ci-dessous. Cliquez sur Diagnostiquer pour verifier l'etat reel sur cette VM.",
        ["VmList_Display_InstallSunshine"] = "Installer Sunshine automatiquement",
        ["VmList_Display_InstallSunshine_Tooltip"] = "Installe Moonlight sur l'hote, prepare puis installe Sunshine dans la VM (demande le mot de passe Windows de la VM, jamais stocke, sauf si vous cochez 'Se souvenir'). L'appariement avec Moonlight (code PIN) reste manuel.",
        ["VmList_Display_FixEnhancedSession"] = "Corriger la Session Amelioree",
        ["VmList_Display_FixEnhancedSession_Tooltip"] = "Si la Session Amelioree reste bloquee sur un ecran de verrouillage flou : desactive la connexion Windows Hello obligatoire (RDP ne sait pas la gerer).",

        ["VmList_Vdd_Intro"] = "Installez et pilotez le pilote d'ecran virtuel tiers (VDD) pour le streaming 100+ Hz. VDD coupe vmconnect (Basique ET Amelioree) tant qu'il est actif : utilisez Sunshine/Moonlight pour voir/controler la VM pendant ce temps.",
        ["VmList_Vdd_InstallAuto"] = "Installer VDD automatiquement",
        ["VmList_Vdd_InstallAuto_Tooltip"] = "Telecharge et installe silencieusement le pilote VDD dans la VM (methode officielle du projet, certificat de confiance importe automatiquement - pas besoin du Mode test). Sans effet si deja installe.",
        ["VmList_Vdd_Enable"] = "Activer VDD",
        ["VmList_Vdd_Disable"] = "Desactiver VDD",

        // --- Communs (dialogues) ---
        ["Common_Cancel"] = "Annuler",
        ["Common_Create"] = "Creer",
        ["Common_Install"] = "Installer",
        ["Common_VmLabel"] = "VM : ",
        ["Common_PasswordRequired"] = "Le mot de passe est obligatoire.",

        // --- Creer une VM ---
        ["CreateVm_Title"] = "Creer une VM",
        ["CreateVm_Name"] = "Nom de la VM",
        ["CreateVm_Disk"] = "Disque (Go)",
        ["CreateVm_IsoLabel"] = "Image ISO de demarrage (optionnel)",
        ["CreateVm_DownloadIso"] = "Telecharger l'ISO Windows 11 (officiel Microsoft)",
        ["CreateVm_DownloadIso_Tooltip"] = "Telecharge automatiquement l'image officielle depuis les serveurs Microsoft (environ 8 Go, une seule fois) - reutilisee ensuite pour toutes les prochaines VMs sans nouveau telechargement.",
        ["CreateVm_NoIsoNote"] = "Sans ISO, la VM demarrera sans systeme d'exploitation (BIOS/UEFI visible, aucun peripherique amorcable).",

        // --- Dialogue Sunshine ---
        ["Sunshine_DialogSubtitle"] = "Identifiants Windows de la VM",
        ["Sunshine_Preparing"] = "Preparation (Moonlight sur l'hote, depot de l'installeur Sunshine)...",
        ["Sunshine_PrepFailed"] = "La preparation du streaming a echoue.",
        ["Sunshine_Installing"] = "Installation de Sunshine dans la VM...",
        ["Sunshine_InstallFailed"] = "L'installation automatique de Sunshine a echoue.",

        // --- Dialogue correction Session Amelioree ---
        ["EnhancedSession_Description"] = "Desactive la connexion Windows Hello obligatoire (RDP, utilise par la Session Amelioree, ne sait pas la gerer et reste bloque sur l'ecran de verrouillage flou).",
        ["EnhancedSession_InProgress"] = "Connexion et correction en cours (PowerShell Direct)...",
        ["EnhancedSession_FixButton"] = "Corriger",
        ["EnhancedSession_FixFailed"] = "La correction a echoue.",

        // --- Dialogue activation Hyper-V ---
        ["HyperV_Title"] = "Installer Hyper-V",
        ["HyperV_Prompt"] = "SPLYT a besoin de Hyper-V pour creer et piloter des machines virtuelles, et ce n'est pas encore installe/active sur ce PC. L'installer maintenant ? Cela necessite les droits administrateur (invite Windows) et, si c'est la premiere fois, un redemarrage complet du PC.",
        ["HyperV_EditionNote"] = "Officiellement disponible sur Windows 11 Pro, Entreprise et Education. Sur Windows Home, SPLYT tentera une methode non-officielle (non garantie, non prise en charge par Microsoft) : elle fonctionne sur la plupart des PC mais peut echouer selon votre version de Windows.",
        ["HyperV_InProgress"] = "Installation de Hyper-V en cours (peut prendre plusieurs minutes) - ne fermez pas SPLYT...",
        ["HyperV_EnableNow"] = "Installer Hyper-V",
        ["HyperV_RebootStillPending"] = "Hyper-V a deja ete installe sur ce PC, mais un redemarrage complet est encore necessaire pour finaliser l'installation. Redemarrer maintenant ?",
        ["Common_Later"] = "Plus tard",
        ["Common_Close"] = "Fermer",
        ["Common_DontShowAgain"] = "Ne plus afficher a l'avenir",

        // --- Configuration en un clic ("bouton SPLYT") ---
        ["Splyt_Title"] = "Windows est installe : tout configurer en un clic",
        ["Splyt_Intro"] = "Le bouton SPLYT enchaine automatiquement toute la configuration de cette VM : partage du GPU (GPU-P), copie du pilote graphique dans la VM, ecran virtuel VDD pour le 100+ Hz, et installation de Sunshine pour l'affichage sur le second ecran. La VM sera arretee puis redemarree toute seule quand c'est necessaire. Comptez plusieurs minutes, principalement pour la copie du pilote.\n\nVos identifiants Windows de la VM sont necessaires : installer un logiciel dans un Windows demande de s'y authentifier, c'est une exigence de Windows et non de SPLYT.",
        ["Splyt_CardTitle"] = "Tout configurer en un clic",
        ["Splyt_CardDesc"] = "GPU-P, pilote graphique, ecran virtuel VDD et Sunshine, enchaines automatiquement. Relance la configuration complete si besoin.",
        ["Splyt_Step_Stopping"] = "Arret de la VM (necessaire pour configurer le GPU)...",
        ["Splyt_Step_Gpu"] = "Configuration du partage du GPU (GPU-P)...",
        ["Splyt_Step_Driver"] = "Copie du pilote graphique dans la VM (plusieurs Go, quelques minutes)...",
        ["Splyt_Step_Starting"] = "Redemarrage de la VM...",
        ["Splyt_Step_Vdd"] = "Installation de l'ecran virtuel VDD...",
        ["Splyt_Step_Sunshine"] = "Installation de Sunshine...",
        ["Splyt_Step_Streaming"] = "Reglages de qualite et appariement automatique de Moonlight...",
        ["Splyt_Report_StreamingOk"] = "Streaming : configure et apparie.",
        ["Splyt_Report_StreamingFailed"] = "Reglages de streaming : echec - {0}",

        ["VmList_LaunchMoonlight"] = "Lancer avec Moonlight",
        ["VmList_LaunchMoonlight_Tooltip"] = "Demarre la VM si necessaire, attend qu'elle soit prete, puis ouvre Moonlight deja connecte en 100 Hz avec un debit adapte a un lien local. Le deuxieme joueur n'a rien a regler.",
        ["VmList_Moonlight_Starting"] = "Preparation du lancement...",
        ["VmList_Moonlight_Failed"] = "Le lancement avec Moonlight a echoue : {0}",
        ["Splyt_Report_NoGpu"] = "GPU-P : ignore, aucun GPU partitionnable detecte sur cet ordinateur.",
        ["Splyt_Report_GpuOk"] = "GPU-P : configure sur {0}.",
        ["Splyt_Report_GpuFailed"] = "GPU-P : echec - {0}",
        ["Splyt_Report_DriverOk"] = "Pilote graphique : copie dans la VM.",
        ["Splyt_Report_DriverFailed"] = "Pilote graphique : echec - {0}",
        ["Splyt_Report_GuestNotReady"] = "Windows n'a pas fini de demarrer dans la VM a temps : VDD et Sunshine n'ont pas ete installes. Relancez le bouton SPLYT une fois la VM demarree.",
        ["Splyt_Report_VddOk"] = "Ecran virtuel VDD : installe.",
        ["Splyt_Report_VddFailed"] = "Ecran virtuel VDD : echec - {0}",
        ["Splyt_Report_SunshineOk"] = "Sunshine : installe. Interface web : {0}",
        ["Splyt_Report_SunshineFailed"] = "Sunshine : echec - {0}",
        ["Splyt_Report_PairingReminder"] = "Derniere etape, manuelle : ouvrez Moonlight et appariez-le a Sunshine avec le code PIN. Cet appariement est la protection de Sunshine contre le streaming non consenti - SPLYT ne le contourne volontairement pas.",

        ["VmList_Gpu_InfoTitle"] = "Le GPU-P, c'est quoi ?",
        ["VmList_Gpu_InfoMessage"] = "Le GPU-P (partitionnement de GPU) permet de partager votre carte graphique entre votre PC et la machine virtuelle EN MEME TEMPS. Contrairement au passthrough classique, vous ne perdez pas l'usage de votre GPU sur l'ordinateur principal : les deux sessions l'utilisent en parallele.\n\nC'est ce qui permet a deux personnes de jouer simultanement sur un seul PC : vous sur votre ecran habituel, la deuxieme personne dans la VM, avec une vraie acceleration graphique des deux cotes.\n\nDans cet onglet :\n\n- GPU partitionne : choisissez la carte graphique a partager avec cette VM. La VM doit etre eteinte pour changer ce reglage.\n\n- VRAM allouee : la part de memoire graphique reservee a la VM. Sur un processeur graphique integre (sans VRAM dediee), ce reglage est desactive car la memoire est geree automatiquement.\n\n- Installer le pilote : etape indispensable apres avoir choisi un GPU. Elle copie le pilote graphique de votre PC dans le disque de la VM (plusieurs Go, comptez quelques minutes). Sans elle, le GPU n'apparaitra pas dans la VM.\n\nOrdre a suivre : choisir le GPU, Enregistrer, puis Installer le pilote, et enfin demarrer la VM.",

        // --- Messages VmListViewModel ---
        ["Vm_NoGpuOption"] = "Aucun (pas de GPU-P)",
        ["Vm_SunshineInstalledSummary"] = "{0}\n\nInterface Sunshine : {1}",
        ["Vm_DeleteFailed"] = "La suppression de '{0}' a echoue.",
        ["Vm_RamLimitExceeded"] = "La RAM demandee ({0} Go) depasse la limite raisonnable pour cet ordinateur ({1} Go).",
        ["Vm_GpuConfigFailed"] = "La configuration du GPU-P a echoue (voir le Journal pour le detail).",
        ["Vm_DiagnosticFailed"] = "Le diagnostic a echoue (voir le Journal pour le detail).",
        ["Vm_DriverInstallFailed"] = "Installation du pilote : ECHEC - {0}",
        ["Vm_DriverInstallSummary"] = "{0}\nHostDriverStore : {1}",
        ["Vm_NvidiaPatchInProgress"] = "Patch en cours (peut prendre plusieurs minutes, et telecharger des outils la premiere fois)...",
        ["Vm_NvidiaPatchFailed"] = "Le patch du pilote NVIDIA a echoue.",
        ["Vm_VddDiagnosticFailed"] = "Le diagnostic VDD a echoue.",
        ["Vm_VddInstallInProgress"] = "Installation de VDD en cours (telechargement + installation du pilote)... cela peut prendre une minute.",
        ["Vm_VddInstallFailed"] = "L'installation automatique de VDD a echoue.",
        ["Vm_GamingOptimizeInProgress"] = "Application des optimisations en cours...",
        ["Vm_GamingOptimizeFailed"] = "L'application des optimisations a echoue.",

        // --- Messages CreateVmDialogViewModel ---
        ["CreateVm_AutoGpu"] = "Auto (recommande)",
        ["CreateVm_IsoNotFound"] = "Le fichier ISO est introuvable : {0}",
        ["CreateVm_CreationFailed"] = "La creation de la VM a echoue (voir le Journal pour le detail).",
        ["CreateVm_DownloadPreparing"] = "Preparation du telechargement...",
        ["CreateVm_IsoDownloadFailed"] = "Le telechargement de l'ISO Windows 11 a echoue.",

        // --- Messages HyperVSetupDialogViewModel ---
        ["HyperV_EnableFailed"] = "L'activation de Hyper-V a echoue.",
        ["HyperV_RestartMessage"] = "SPLYT redemarre ce PC pour activer Hyper-V.",
        ["HyperV_RestartFailed"] = "Impossible de lancer le redemarrage automatiquement : {0}. Redemarrez manuellement.",

        // --- Selecteurs de fichiers (OpenFileDialog) ---
        ["VmList_Nvidia_FilePickerTitle"] = "Selectionner l'installeur du pilote NVIDIA",
        ["VmList_Nvidia_FilePickerFilter"] = "Installeur NVIDIA (*.exe)|*.exe|Tous les fichiers (*.*)|*.*",
        ["CreateVm_FilePickerTitle"] = "Selectionner une image ISO",
        ["CreateVm_FilePickerFilter"] = "Images ISO (*.iso)|*.iso|Tous les fichiers (*.*)|*.*",

        // --- Memoire dynamique ---
        ["Vm_DynamicMemory"] = "Memoire dynamique",
        ["Vm_DynamicMemory_Tooltip"] = "Decochee (par defaut) : la RAM configuree ci-dessus est toujours entierement assignee a la VM. Cochee : Hyper-V n'assigne que la RAM reellement utilisee (jusqu'a ce montant), et la reprend quand la VM est peu chargee.",

        // --- Modeles (VirtualMachine, VmState) ---
        ["Vm_DisplaySummary"] = "{0} vCPU - {1} Go - {2}@{3}Hz",
        ["Vm_Unnamed"] = "(sans nom)",
        ["VmState_Off"] = "Arretee",
        ["VmState_Running"] = "En cours",
        ["VmState_Starting"] = "Demarrage...",
        ["VmState_Stopping"] = "Arret en cours...",
        ["VmState_Saved"] = "En pause",
        ["VmState_Error"] = "Erreur",
        ["VmState_Unknown"] = "Inconnu",
    };

    public static readonly Dictionary<string, string> English = new()
    {
        // --- Common ---
        ["Common_Yes"] = "Yes",
        ["Common_No"] = "No",

        // --- Main shell / navigation ---
        ["App_Subtitle"] = "GPU-P VM Manager",
        ["Nav_Dashboard"] = "Home",
        ["Nav_VmList"] = "Virtual Machines",
        ["Nav_Gpu"] = "GPU",
        ["Nav_Storage"] = "Storage",
        ["Nav_Journal"] = "Log",
        ["Nav_Settings"] = "Settings",
        ["Common_Refresh"] = "Refresh",
        ["Common_GbUnit"] = " GB",

        // --- Home ---
        ["Dashboard_Subtitle"] = "Overview of the host and virtual machines",
        ["Dashboard_NoVms"] = "No VMs yet.",
        ["Dashboard_RecentAlerts"] = "Recent alerts",
        ["Dashboard_NoAlerts"] = "No alerts. Everything is running normally.",

        // --- GPU ---
        ["Gpu_Subtitle"] = "Physical host GPUs and GPU-P partitioning",
        ["Gpu_PartitionSupported"] = "GPU-P supported",
        ["Gpu_PartitionNotSupported"] = "GPU-P not supported",
        ["Gpu_Driver"] = "Driver: ",
        ["Gpu_VmsUsingThisGpu"] = "VMs using this GPU: ",
        ["Gpu_NoGpuDetected"] = "No GPU detected.",

        // --- Storage ---
        ["Storage_Subtitle"] = "Virtual disks (VHDX) of NovaVM machines",
        ["Storage_ColumnFile"] = "File",
        ["Storage_ColumnSize"] = "Size",
        ["Storage_ColumnAttachedVm"] = "Attached VM",
        ["Storage_NoneAttached"] = "None",
        ["Storage_NoDisks"] = "No disks yet.",

        // --- Log ---
        ["Journal_Subtitle"] = "History of operations performed on VMs (most recent first)",

        // --- Settings ---
        ["Settings_Title"] = "Settings",
        ["Settings_Subtitle"] = "Preferences and Hyper-V/GPU-P environment diagnostics",
        ["Settings_RefreshDiagnostics"] = "Refresh diagnostics",
        ["Settings_DiagnosticTitle"] = "Diagnostics",
        ["Settings_HyperVModuleInstalled"] = "Hyper-V PowerShell module installed",
        ["Settings_CanListVms"] = "Read access to Hyper-V VMs",
        ["Settings_CanListGpus"] = "Access to partitionable GPUs (GPU-P)",
        ["Settings_IsElevated"] = "Administrator session",
        ["Settings_DiagnosticNote"] = "Without Hyper-V/GPU-P access, the app keeps running with simulated data. Adding this account to the local 'Hyper-V Administrators' group (or running as administrator) will be needed to control real VMs.",

        ["Settings_ReportTitle"] = "Report a problem",
        ["Settings_ReportDesc"] = "Copies to the clipboard everything that makes a bug report actionable: exact CPU and GPU model, driver version, Windows edition and build, the state of your VMs and the latest errors. Two GPU-P failures with different causes often look identical from the outside: without these details they cannot be told apart. Contains no passwords, and paths containing your username are redacted.",
        ["Settings_CopyReport"] = "Copy diagnostic report",
        ["Settings_ReportCopied"] = "Report copied. Paste it into your bug report (Ctrl+V), along with a screenshot of the first screen where the problem shows.",
        ["Settings_ReportCopyFailed"] = "Could not access the clipboard: {0}",
        ["Settings_PreferencesTitle"] = "Preferences",
        ["Settings_DefaultDiskPath"] = "Default folder for virtual disks",
        ["Settings_AutoSelectGpu"] = "Automatically select the GPU for GPU-P",
        ["Settings_DarkTheme"] = "Dark theme",
        ["Settings_PreferencesNote"] = "(Settings kept in memory for this prototype; on-disk persistence will follow.)",
        ["Settings_LanguageTitle"] = "Language",
        ["Settings_LanguageNote"] = "Changes SPLYT's interface language.",
        ["Settings_LanguageRestartNotice"] = "Restart SPLYT to apply the language change.",
        ["Settings_RestartNow"] = "Restart now",
        ["Settings_AboutTitle"] = "About",
        ["Settings_AboutRoadmap"] = "See Claude.md at the repository root for the full roadmap.",

        // --- Additional common ---
        ["Common_Delete"] = "Delete",
        ["Common_Save"] = "Save",
        ["Common_Diagnose"] = "Diagnose",
        ["Common_Browse"] = "Browse...",

        // --- Virtual machines (list + detail) ---
        ["VmList_Subtitle"] = "Create, configure and control your VMs",
        ["VmList_CreateVm"] = "+  Create a VM",
        ["VmList_MachinesHeader"] = "Machines",
        ["VmList_Start"] = "Start",
        ["VmList_Stop"] = "Stop",
        ["VmList_Stop_Tooltip"] = "Normal shutdown (equivalent to starting a shutdown from Windows' Start menu).",
        ["VmList_StopChoice_Title"] = "Stop the VM",
        ["VmList_StopChoice_Message"] = "How do you want to stop '{0}'?\n\nNormal shutdown: asks Windows to shut down cleanly, like from its Start menu (nothing is lost).\n\nForce stop: cuts power immediately, like holding down the power button. Only use this if the normal shutdown doesn't respond - unsaved work inside the VM will be lost.",
        ["VmList_StopChoice_Normal"] = "Normal shutdown",
        ["VmList_StopChoice_Forced"] = "Force stop",
        ["VmList_DeleteConfirm_Title"] = "Delete the VM",
        ["VmList_DeleteConfirm_Message"] = "Permanently delete the VM '{0}'?\n\nIts Hyper-V configuration and its virtual disk will be erased. This cannot be undone.",
        ["VmList_IsoMounted"] = "Mounted ISO: ",
        ["VmList_NoSelection"] = "Select a VM or create a new one.",

        ["VmList_Tab_Resources"] = "Resources",
        ["VmList_Tab_Display"] = "Display",

        ["VmList_Res_Vcpu"] = "Virtual processors (vCPU)",
        ["VmList_Res_Ram"] = "Memory (GB)",
        ["VmList_Res_PhysicalRamDetected"] = "Detected physical RAM: ",
        ["VmList_Res_MaxForVm"] = " GB - maximum for a VM: ",
        ["VmList_Res_RamWarning"] = "Warning: you're assigning a large share of this computer's RAM to the VM.",
        ["VmList_Res_CpuDetected"] = "Detected processor: ",
        ["VmList_Res_CpuCores"] = " physical cores (",
        ["VmList_Res_CpuThreads"] = " threads) - the maximum for a VM is capped at the physical cores.",

        ["VmList_Credentials_UsernameLabel"] = "Username: local Windows account OR Microsoft account",
        ["VmList_Credentials_PasswordLabel"] = "Password",
        ["VmList_Credentials_Remember"] = "Remember my credentials",
        ["VmList_Credentials_MicrosoftHint_Part1"] = "Microsoft account: just enter your email, e.g. ",
        ["VmList_Credentials_MicrosoftHint_Part2"] = " (the technical prefix is added automatically). Local account: enter the name shown on the VM's sign-in screen.",
        ["VmList_Credentials_StorageNote"] = "These are the credentials you set when installing Windows in this VM. They are neither stored nor logged, unless you check the box above (Windows Credential Manager, encrypted - removable at any time from Control Panel).",

        ["VmList_Gaming_Header"] = "Gaming optimizations",
        ["VmList_Gaming_Intro"] = "Applies common Windows gaming tweaks (similar to tools like WinToys), directly inside the VM.",
        ["VmList_Gaming_PerformanceTitle"] = "Performance",
        ["VmList_Gaming_PerformanceDesc"] = "Ultimate Performance power plan, Hardware-accelerated GPU scheduling (if available), virtualization-based security (VBS) disabled, fast startup disabled. A VM restart is recommended after applying.",
        ["VmList_Gaming_OptimizePerformance"] = "Optimize performance",
        ["VmList_Gaming_PrivacyTitle"] = "Privacy",
        ["VmList_Gaming_PrivacyDesc"] = "Reduces Windows telemetry to the minimum, disables the advertising ID and location permanently.",
        ["VmList_Gaming_ReduceTracking"] = "Reduce Microsoft tracking",

        ["VmList_Gpu_Partitioned"] = "Partitioned GPU",
        ["VmList_Gpu_VramAllocated"] = "Allocated VRAM (MB)",
        ["VmList_Gpu_NoDedicatedVram"] = "This GPU has no dedicated VRAM (integrated graphics: it draws from system RAM). There is nothing to size here - Hyper-V shares graphics memory between the host and the VM automatically.",
        ["VmList_Gpu_InstallDriverInProgress"] = "Preparing the GPU-P driver - copying the driver store means several GB, expect a few minutes. Don't close SPLYT.",
        ["VmList_Gpu_InstallDriver"] = "Install driver",
        ["VmList_Gpu_InstallDriver_Tooltip"] = "Copies the host GPU driver into the VM's disk offline (DISM). Requires elevation (administrator prompt) and the VM to be off.",

        ["VmList_Nvidia_Header"] = "NVIDIA hack (unofficial)",
        ["VmList_Nvidia_Warning"] = "NVIDIA deliberately blocks its GeForce GPUs inside VMs. This patches your driver to bypass that block - an unofficial community technique, abandoned since 2021: a good chance of failing cleanly (clear message) if your driver is too recent. Changes nothing if no pattern matches. Requires having already run 'Install driver' above at least once, and the VM to be off.",
        ["VmList_Nvidia_InstallerLabel"] = "NVIDIA driver installer (downloaded from nvidia.com - same version as the one installed on this host)",
        ["VmList_Nvidia_PatchButton"] = "Patch and install (hack)",
        ["VmList_Nvidia_PatchButton_Tooltip"] = "May download several hundred MB (7-Zip, Windows Driver Kit) the first time, and take several minutes. The VM's disk will be mounted offline: don't close SPLYT during the operation.",

        ["VmList_Display_HzWarning_Part1"] = "Important: vmconnect (Basic or Enhanced session) is capped at ",
        ["VmList_Display_HzWarning_Part2"] = ", even with GPU-P active - there is no setting to exceed this limit via vmconnect. For 100+ Hz, use Sunshine/Moonlight streaming below. Click Diagnose to check the real state on this VM.",
        ["VmList_Display_InstallSunshine"] = "Install Sunshine automatically",
        ["VmList_Display_InstallSunshine_Tooltip"] = "Installs Moonlight on the host, prepares then installs Sunshine in the VM (asks for the VM's Windows password, never stored unless you check 'Remember'). Pairing with Moonlight (PIN code) stays manual.",
        ["VmList_Display_FixEnhancedSession"] = "Fix Enhanced Session",
        ["VmList_Display_FixEnhancedSession_Tooltip"] = "If Enhanced Session stays stuck on a blurry lock screen: disables the mandatory Windows Hello sign-in (RDP can't handle it).",

        ["VmList_Vdd_Intro"] = "Install and control the third-party virtual display driver (VDD) for 100+ Hz streaming. VDD cuts off vmconnect (both Basic AND Enhanced) while active: use Sunshine/Moonlight to see/control the VM meanwhile.",
        ["VmList_Vdd_InstallAuto"] = "Install VDD automatically",
        ["VmList_Vdd_InstallAuto_Tooltip"] = "Silently downloads and installs the VDD driver in the VM (the project's official method, trusted certificate imported automatically - no Test Mode needed). No effect if already installed.",
        ["VmList_Vdd_Enable"] = "Enable VDD",
        ["VmList_Vdd_Disable"] = "Disable VDD",

        // --- Common (dialogs) ---
        ["Common_Cancel"] = "Cancel",
        ["Common_Create"] = "Create",
        ["Common_Install"] = "Install",
        ["Common_VmLabel"] = "VM: ",
        ["Common_PasswordRequired"] = "Password is required.",

        // --- Create a VM ---
        ["CreateVm_Title"] = "Create a VM",
        ["CreateVm_Name"] = "VM name",
        ["CreateVm_Disk"] = "Disk (GB)",
        ["CreateVm_IsoLabel"] = "Boot ISO image (optional)",
        ["CreateVm_DownloadIso"] = "Download the Windows 11 ISO (official Microsoft)",
        ["CreateVm_DownloadIso_Tooltip"] = "Automatically downloads the official image from Microsoft's servers (about 8 GB, once only) - reused for every future VM with no new download.",
        ["CreateVm_NoIsoNote"] = "Without an ISO, the VM will boot with no operating system (BIOS/UEFI visible, no bootable device).",

        // --- Sunshine dialog ---
        ["Sunshine_DialogSubtitle"] = "VM's Windows credentials",
        ["Sunshine_Preparing"] = "Preparing (Moonlight on the host, dropping the Sunshine installer)...",
        ["Sunshine_PrepFailed"] = "Streaming preparation failed.",
        ["Sunshine_Installing"] = "Installing Sunshine in the VM...",
        ["Sunshine_InstallFailed"] = "Automatic Sunshine installation failed.",

        // --- Enhanced Session fix dialog ---
        ["EnhancedSession_Description"] = "Disables the mandatory Windows Hello sign-in (RDP, used by Enhanced Session, can't handle it and stays stuck on the blurry lock screen).",
        ["EnhancedSession_InProgress"] = "Connecting and fixing (PowerShell Direct)...",
        ["EnhancedSession_FixButton"] = "Fix",
        ["EnhancedSession_FixFailed"] = "The fix failed.",

        // --- Hyper-V setup dialog ---
        ["HyperV_Title"] = "Install Hyper-V",
        ["HyperV_Prompt"] = "SPLYT needs Hyper-V to create and control virtual machines, and it isn't installed/enabled on this PC yet. Install it now? This requires administrator rights (Windows prompt) and, if this is the first time, a full PC restart.",
        ["HyperV_EditionNote"] = "Officially available on Windows 11 Pro, Enterprise and Education. On Windows Home, SPLYT will attempt an unofficial method (not guaranteed, not supported by Microsoft): it works on most PCs but may fail depending on your Windows version.",
        ["HyperV_InProgress"] = "Installing Hyper-V (can take several minutes) - don't close SPLYT...",
        ["HyperV_EnableNow"] = "Install Hyper-V",
        ["HyperV_RebootStillPending"] = "Hyper-V has already been installed on this PC, but a full restart is still needed to finish the installation. Restart now?",
        ["Common_Later"] = "Later",
        ["Common_Close"] = "Close",
        ["Common_DontShowAgain"] = "Don't show this again",

        // --- One-click setup ("SPLYT button") ---
        ["Splyt_Title"] = "Windows is installed: set everything up in one click",
        ["Splyt_Intro"] = "The SPLYT button chains the whole setup of this VM automatically: GPU sharing (GPU-P), copying the graphics driver into the VM, the VDD virtual display for 100+ Hz, and installing Sunshine for output on the second screen. The VM is stopped and restarted on its own when needed. Expect several minutes, mostly for the driver copy.\n\nYour Windows credentials for the VM are required: installing software inside a Windows guest means authenticating to it - that's a Windows requirement, not a SPLYT one.",
        ["Splyt_CardTitle"] = "Set everything up in one click",
        ["Splyt_CardDesc"] = "GPU-P, graphics driver, VDD virtual display and Sunshine, chained automatically. Re-run the full setup whenever needed.",
        ["Splyt_Step_Stopping"] = "Stopping the VM (required to configure the GPU)...",
        ["Splyt_Step_Gpu"] = "Configuring GPU sharing (GPU-P)...",
        ["Splyt_Step_Driver"] = "Copying the graphics driver into the VM (several GB, a few minutes)...",
        ["Splyt_Step_Starting"] = "Restarting the VM...",
        ["Splyt_Step_Vdd"] = "Installing the VDD virtual display...",
        ["Splyt_Step_Sunshine"] = "Installing Sunshine...",
        ["Splyt_Step_Streaming"] = "Quality settings and automatic Moonlight pairing...",
        ["Splyt_Report_StreamingOk"] = "Streaming: configured and paired.",
        ["Splyt_Report_StreamingFailed"] = "Streaming settings: failed - {0}",

        ["VmList_LaunchMoonlight"] = "Launch with Moonlight",
        ["VmList_LaunchMoonlight_Tooltip"] = "Starts the VM if needed, waits until it's ready, then opens Moonlight already connected at 100 Hz with a bitrate suited to a local link. The second player has nothing to configure.",
        ["VmList_Moonlight_Starting"] = "Preparing launch...",
        ["VmList_Moonlight_Failed"] = "Launching with Moonlight failed: {0}",
        ["Splyt_Report_NoGpu"] = "GPU-P: skipped, no partitionable GPU detected on this computer.",
        ["Splyt_Report_GpuOk"] = "GPU-P: configured on {0}.",
        ["Splyt_Report_GpuFailed"] = "GPU-P: failed - {0}",
        ["Splyt_Report_DriverOk"] = "Graphics driver: copied into the VM.",
        ["Splyt_Report_DriverFailed"] = "Graphics driver: failed - {0}",
        ["Splyt_Report_GuestNotReady"] = "Windows didn't finish booting in the VM in time: VDD and Sunshine were not installed. Run the SPLYT button again once the VM is up.",
        ["Splyt_Report_VddOk"] = "VDD virtual display: installed.",
        ["Splyt_Report_VddFailed"] = "VDD virtual display: failed - {0}",
        ["Splyt_Report_SunshineOk"] = "Sunshine: installed. Web UI: {0}",
        ["Splyt_Report_SunshineFailed"] = "Sunshine: failed - {0}",
        ["Splyt_Report_PairingReminder"] = "One manual step left: open Moonlight and pair it with Sunshine using the PIN code. That pairing is Sunshine's protection against non-consented streaming - SPLYT deliberately does not bypass it.",

        ["VmList_Gpu_InfoTitle"] = "What is GPU-P?",
        ["VmList_Gpu_InfoMessage"] = "GPU-P (GPU partitioning) shares your graphics card between your PC and the virtual machine AT THE SAME TIME. Unlike traditional passthrough, you don't lose the use of your GPU on the main computer: both sessions use it in parallel.\n\nThat's what makes it possible for two people to game simultaneously on a single PC: you on your usual screen, the second person inside the VM, with real graphics acceleration on both sides.\n\nIn this tab:\n\n- Partitioned GPU: pick the graphics card to share with this VM. The VM must be shut down to change this setting.\n\n- Allocated VRAM: the share of graphics memory reserved for the VM. On integrated graphics (no dedicated VRAM), this setting is disabled because memory is managed automatically.\n\n- Install driver: a required step after picking a GPU. It copies your PC's graphics driver into the VM's disk (several GB, expect a few minutes). Without it, the GPU will not appear inside the VM.\n\nOrder to follow: pick the GPU, Save, then Install driver, and finally start the VM.",

        // --- VmListViewModel messages ---
        ["Vm_NoGpuOption"] = "None (no GPU-P)",
        ["Vm_SunshineInstalledSummary"] = "{0}\n\nSunshine interface: {1}",
        ["Vm_DeleteFailed"] = "Deleting '{0}' failed.",
        ["Vm_RamLimitExceeded"] = "The requested RAM ({0} GB) exceeds the reasonable limit for this computer ({1} GB).",
        ["Vm_GpuConfigFailed"] = "GPU-P configuration failed (see the Log for details).",
        ["Vm_DiagnosticFailed"] = "Diagnostics failed (see the Log for details).",
        ["Vm_DriverInstallFailed"] = "Driver installation: FAILED - {0}",
        ["Vm_DriverInstallSummary"] = "{0}\nHostDriverStore: {1}",
        ["Vm_NvidiaPatchInProgress"] = "Patching in progress (can take several minutes, and download tools the first time)...",
        ["Vm_NvidiaPatchFailed"] = "The NVIDIA driver patch failed.",
        ["Vm_VddDiagnosticFailed"] = "VDD diagnostics failed.",
        ["Vm_VddInstallInProgress"] = "Installing VDD (downloading + installing the driver)... this can take a minute.",
        ["Vm_VddInstallFailed"] = "Automatic VDD installation failed.",
        ["Vm_GamingOptimizeInProgress"] = "Applying optimizations...",
        ["Vm_GamingOptimizeFailed"] = "Applying optimizations failed.",

        // --- CreateVmDialogViewModel messages ---
        ["CreateVm_AutoGpu"] = "Auto (recommended)",
        ["CreateVm_IsoNotFound"] = "ISO file not found: {0}",
        ["CreateVm_CreationFailed"] = "VM creation failed (see the Log for details).",
        ["CreateVm_DownloadPreparing"] = "Preparing download...",
        ["CreateVm_IsoDownloadFailed"] = "Windows 11 ISO download failed.",

        // --- HyperVSetupDialogViewModel messages ---
        ["HyperV_EnableFailed"] = "Enabling Hyper-V failed.",
        ["HyperV_RestartMessage"] = "SPLYT is restarting this PC to enable Hyper-V.",
        ["HyperV_RestartFailed"] = "Could not start the automatic restart: {0}. Please restart manually.",

        // --- File pickers (OpenFileDialog) ---
        ["VmList_Nvidia_FilePickerTitle"] = "Select the NVIDIA driver installer",
        ["VmList_Nvidia_FilePickerFilter"] = "NVIDIA installer (*.exe)|*.exe|All files (*.*)|*.*",
        ["CreateVm_FilePickerTitle"] = "Select an ISO image",
        ["CreateVm_FilePickerFilter"] = "ISO images (*.iso)|*.iso|All files (*.*)|*.*",

        // --- Dynamic memory ---
        ["Vm_DynamicMemory"] = "Dynamic memory",
        ["Vm_DynamicMemory_Tooltip"] = "Unchecked (default): the RAM configured above is always fully assigned to the VM. Checked: Hyper-V only assigns the RAM actually in use (up to this amount), and reclaims it when the VM is lightly loaded.",

        // --- Models (VirtualMachine, VmState) ---
        ["Vm_DisplaySummary"] = "{0} vCPU - {1} GB - {2}@{3}Hz",
        ["Vm_Unnamed"] = "(unnamed)",
        ["VmState_Off"] = "Off",
        ["VmState_Running"] = "Running",
        ["VmState_Starting"] = "Starting...",
        ["VmState_Stopping"] = "Stopping...",
        ["VmState_Saved"] = "Paused",
        ["VmState_Error"] = "Error",
        ["VmState_Unknown"] = "Unknown",
    };
}
