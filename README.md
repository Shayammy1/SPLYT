# SPLYT

Gestionnaire de machines virtuelles Windows GPU-P, avec une interface graphique
moderne. Deux composants, volontairement séparés :

- un **noyau bas niveau en C++** construit sur la **Windows Hypervisor
  Platform (WHP)** — le tout premier prototype d'hyperviseur du projet ;
- une **application graphique WPF** qui pilote de vraies VMs **Hyper-V**
  (création, ressources, GPU-P, affichage) via des scripts PowerShell dédiés.

> Voir [Claude.md](Claude.md) pour la feuille de route complète du projet.

## Application graphique (gui/NovaVM.Gui)

Interface graphique moderne (WPF + WPF-UI, thème sombre façon tableau de
bord) pour créer, configurer et piloter des VMs avec partitionnement GPU-P.

**Statut actuel : maquette fonctionnelle.** La navigation, les 6 écrans, la
création/démarrage/arrêt/suppression de VM et le journal fonctionnent
réellement de bout en bout, mais le backend Hyper-V (`scripts/hyperv/`) est
pour l'instant **simulé** (données stockées dans un fichier JSON local) :
GPU/CPU/RAM/stockage hôte affichés sont en revanche de vraies données lues sur
la machine. Les scripts sont conçus pour être remplacés progressivement par
de vrais appels aux cmdlets Hyper-V (`New-VM`, `Add-VMGpuPartitionAdapter`,
etc.) sans changer la GUI.

### Écrans

- **Accueil** — utilisation CPU/RAM/stockage de l'hôte, liste des VMs, alertes récentes.
- **Machines virtuelles** — création (assistant), liste + détail à onglets
  (Ressources, GPU-P, Affichage), démarrer/arrêter/supprimer.
- **GPU** — GPU physiques détectés, compatibilité GPU-P, VMs qui les utilisent.
- **Stockage** — disques virtuels (VHDX) et leur VM associée.
- **Journal** — historique horodaté de toutes les opérations (succès/erreurs).
- **Paramètres** — préférences et diagnostic (accès Hyper-V/GPU-P, élévation).

### Architecture (3 couches)

```text
gui/NovaVM.Gui/          # Interface graphique (WPF, MVVM)
├── Views/               # XAML des 6 écrans + composants
├── ViewModels/          # Etat de chaque écran + logique de présentation
├── Services/            # NovaVmService (metier) + PowerShellRunner (interop)
├── Models/               # Types observables (VirtualMachine, HostGpu, ...)
scripts/hyperv/           # "Backend" : scripts PowerShell autonomes
├── NovaVm.Common.psm1    # Contrat JSON partagé, aide, verrouillage
├── Get-/New-/Start-/...  # Un script par opération (liste, creation, GPU-P, ...)
```

Chaque script PowerShell reçoit des paramètres et renvoie une ligne JSON
`{ "success": ..., "data": ..., "error": ... }` sur stdout ; `NovaVmService`
est la seule classe C# qui sait que le backend est du PowerShell.

### Prérequis

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- Pour piloter de *vraies* VMs Hyper-V plus tard : le module PowerShell
  Hyper-V installé, et ce compte utilisateur dans le groupe local
  **Hyper-V Administrators** (ou une exécution en administrateur). La page
  Paramètres de l'appli affiche un diagnostic de ces prérequis.

### Compilation et exécution

```powershell
cd gui/NovaVM.Gui
dotnet build
dotnet run
```

## Noyau bas niveau (WHP) — prototype initial

Prototype minimal qui vérifie WHP, crée une partition, un vCPU, alloue de la
mémoire invité, exécute un petit programme x86 et libère proprement toutes
les ressources. Ne démarre pas encore Windows en tant qu'invité et
n'implémente pas GPU-P — c'est la fondation bas niveau de la feuille de
route, indépendante de l'application graphique ci-dessus.

### Ce que fait ce prototype

1. Vérifie que Windows Hypervisor Platform est disponible sur la machine.
2. Crée une partition WHP.
3. Configure un processeur virtuel (vCPU).
4. Alloue et mappe une page de mémoire invité.
5. Charge et exécute un petit programme x86 (`mov ax,0x1234 ; add ax,1 ; hlt`).
6. Affiche clairement les registres et le résultat de l'exécution (ou toute erreur).
7. Libère proprement toutes les ressources (vCPU, mémoire, partition), y compris en cas d'erreur (RAII).

### Prérequis

- Windows 11 x64, avec la virtualisation matérielle (Intel VT-x / AMD-V)
  activée dans le BIOS/UEFI.
- La fonctionnalité Windows **« Plateforme Hyperviseur Windows »**
  (*Windows Hypervisor Platform*) activée :

  ```powershell
  Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
  ```

  (nécessite une exécution en administrateur et généralement un redémarrage)

- [CMake](https://cmake.org/download/) ≥ 3.20
- Visual Studio Build Tools 2022 (charge de travail *Desktop development
  with C++*, qui inclut le compilateur MSVC et le Windows SDK)

### Compilation

```powershell
./scripts/configure.ps1
./scripts/build.ps1
```

### Exécution

```powershell
./scripts/run.ps1
```

## Structure du projet

```text
NovaVM/
├── CMakeLists.txt
├── include/, src/, tests/   # Noyau WHP (C++)
├── scripts/
│   ├── configure.ps1, build.ps1, run.ps1   # Build du noyau C++
│   └── hyperv/                              # "Backend" PowerShell de la GUI
└── gui/NovaVM.Gui/                          # Application graphique (WPF)
```

## Feuille de route

Voir [Claude.md](Claude.md) pour l'objectif à long terme (GPU-P réel, affichage
basse latence, 60-144 Hz, usage simultané hôte/VM du GPU, etc.).
