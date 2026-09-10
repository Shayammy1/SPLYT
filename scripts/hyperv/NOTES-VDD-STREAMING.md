# Streaming sur l'ecran virtuel VDD - etat verifie

Mesures faites le 2026-09-10 sur la VM `test2` (Sunshine 2026.516.143833,
Virtual Display Driver 25.7.23, GPU-P AMD RX 7900 XTX).

## Ce qui fonctionne, verifie de bout en bout

- La fenetre de choix transmet bien la resolution et la frequence a Moonlight,
  qui les reclame a Sunshine.
- `output_name` pointe sur l'ecran VDD, identifie par son `device_id` stable.
  Cet identifiant est lu dans le JOURNAL de Sunshine et non par `dxgi-info.exe` :
  depuis PowerShell Direct (session 0) l'outil renvoie une liste d'ecrans vide,
  alors que Sunshine, qui tourne dans la session interactive, enumere les ecrans
  a chaque demarrage et ecrit le resultat dans son journal.
- `dd_configuration_option = ensure_only_display` deplace reellement le bureau
  de l'invite sur le VDD pendant la session : le journal passe de
  `Virtual Desktop 4480x1440` (deux ecrans) a `2560x1440` (le VDD seul).
- La RESOLUTION demandee est appliquee : demande 2560x1440, obtenu
  `Capture size 2560x1440`.
- Le retour a l'ecran Hyper-V a la deconnexion fonctionne.

## Prerequis absolu : une session Windows OUVERTE dans la VM

Sur l'ecran de connexion, `SetDisplayConfig` renvoie ERROR_ACCESS_DENIED et
Sunshine journalise en boucle, toutes les 5 secondes :

    WinDisplayDevice::isApiAccessAvailable result: [code: ERROR_ACCESS_DENIED]
    Trying to apply display device settings. API is available: false

Aucun reglage d'affichage n'est alors applique - ni resolution, ni frequence, ni
bascule sur le VDD. Des qu'une session est ouverte (explorer.exe present,
LogonUI absent), la meme operation passe a `API is available: true`.

C'est une regle de Windows, pas un defaut de Sunshine : la configuration
d'affichage ne peut etre modifiee que depuis la session interactive deverrouillee.
Cela rejoint, par un autre chemin, le constat deja documente sur l'impossibilite
de piloter l'affichage de l'invite depuis l'hote.

## Limite connue : la frequence retombe a 100 Hz

Demande 2560x1440 a 120 Hz, Sunshine reclame bien 120 :

    "refresh_rate": { "denominator": 1, "numerator": 120 }
    Changing display modes to: ... 120 ...

mais la capture s'etablit a `Display refresh rate [100Hz]`. La resolution, elle,
est correcte.

Pistes ecartees par l'experience :
- Ce n'est PAS la liste de modes du VDD. Un `vdd_settings.xml` ne contenant que
  60 et 120 (aucun 100) donne toujours 100 Hz en session. Le fichier est pourtant
  bien lu : reduit au seul 120, le VDD demarre en 2560x1440 a 120 Hz.
- Ce n'est pas la version de Sunshine : les options `dd_*` sont presentes et
  actives des 2026.516.

Piste non encore verifiee : la base de configuration d'affichage de Windows
(`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration`), qui
memorise le dernier mode utilise pour une combinaison d'ecrans donnee et le
restaure lors du changement de topologie.

## A ne pas retenter

Enumerer les modes d'affichage de l'invite par une tache planifiee en session
interactive : essaye, aucune sortie produite - meme impasse que celle deja
documentee pour le changement de mode.
