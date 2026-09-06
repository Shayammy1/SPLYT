# Projet : SPLYT (anciennement NovaVM)

Tu es l’architecte principal de ce projet. Construis progressivement un gestionnaire de machines virtuelles Windows utilisant Windows Hypervisor Platform (WHP).

## Objectif à long terme

Créer un logiciel capable de :

- créer et exécuter des machines virtuelles ;
- utiliser Windows Hypervisor Platform ;
- automatiser la configuration GPU-P ;
- proposer un affichage à faible latence ;
- prendre en charge 60, 70, 100, 120 et 144 Hz ;
- permettre l’utilisation simultanée du GPU par l’hôte et la VM ;
- fournir une interface graphique moderne.

Ne cherche pas à tout implémenter immédiatement.

## Premier objectif

Construis uniquement un prototype fonctionnel qui :

1. vérifie que WHP est disponible ;
2. crée une partition WHP ;
3. configure un processeur virtuel ;
4. alloue et mappe de la mémoire invitée ;
5. exécute quelques instructions x86-64 simples ;
6. affiche clairement les sorties et erreurs ;
7. libère correctement toutes les ressources.

Le programme ne doit pas encore démarrer Windows et ne doit pas encore implémenter GPU-P.

## Technologies

- Windows 11 x64
- C++20
- CMake
- Visual Studio Build Tools 2022
- Windows SDK
- Windows Hypervisor Platform
- Bibliothèque `WinHvPlatform.lib`
- VS Code

## Structure souhaitée

Crée automatiquement tous les dossiers et fichiers nécessaires :

```text
NovaVM/
├── CLAUDE.md
├── CMakeLists.txt
├── README.md
├── .gitignore
├── scripts/
│   ├── configure.ps1
│   ├── build.ps1
│   └── run.ps1
├── include/
│   ├── Hypervisor.hpp
│   ├── VirtualMachine.hpp
│   └── WhpError.hpp
├── src/
│   ├── main.cpp
│   ├── Hypervisor.cpp
│   ├── VirtualMachine.cpp
│   └── WhpError.cpp
└── tests/
    └── basic_tests.cpp