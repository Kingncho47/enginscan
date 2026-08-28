# EnginScan — Diagnostic J1939 pour engins lourds & manutention

Application **Flutter / Android 100 % offline-first** pour le diagnostic
technique des engins de chantier et de manutention (Caterpillar, Komatsu,
Volvo CE, Liebherr, Manitou…), connectée en direct au bus **SAE J1939** via un
boîtier Bluetooth (ELM327 v1.4+/v1.5, OBDLink MX+, STN compatibles) branché sur
la prise Deutsch Y (9 broches) ou un adaptateur OBD2/CAN.

## Fonctionnalités

| Module | Description |
|---|---|
| Diagnostic live | Scan/appairage Bluetooth SPP, init `ATZ/ATE0/ATL0/ATS0/ATH1/ATAT1/ATSP A/ATCAF1/ATCRA`, moniteur `AT MA`, décodage temps réel DM1/DM2 + requête active `18EAFFF9 CAFE00` |
| Live data | Régime (SPN 190), températures (110/175), tension batterie (158), pressions (94/102), niveau carburant (96), vitesse (84), couple (513) — jauges radiales avec seuils vigilance/critique |
| Base DTC offline | Recherche instantanée par code (`110-3`), SPN, marque ou mot-clé ; fiche : description, causes probables, procédure d'intervention étape par étape |
| Checklist pré-shift | Contrôle visuel/fonctionnel avant mise en service, points critiques bloquants, observations par point, historique local |
| Console terrain | Terminal AT/ST libre (`ATRV`, `STI`…) + journal des trames HEX |

## Arborescence

```
lib/
├── main.dart                          # composition : DB + services + providers
└── src/
    ├── app.dart                       # MaterialApp M3 + navigation (IndexedStack)
    ├── core/
    │   ├── constants/fmi_catalog.dart     # libellés FMI 0-31 (J1939-73)
    │   ├── constants/j1939_constants.dart # PGN, adresses sources, lecture LE
    │   └── theme/app_theme.dart           # Material 3 sombre haut contraste
    ├── data/
    │   ├── database/app_database.dart     # sqflite (schéma v1)
    │   └── seed/seed_data.dart            # 16 fiches réelles pré-remplies
    └── features/
        ├── j1939/
        │   ├── domain/models.dart         # DtcModel & LiveSensorModel
        │   ├── domain/j1939_frame.dart    # trame : ID 29 bits → PGN/SA
        │   └── data/
        │       ├── elm327_link.dart       # couche série SPP (lignes + prompt '>')
        │       ├── j1939_bluetooth_service.dart   # orchestrateur (ChangeNotifier)
        │       ├── j1939_frame_parser.dart        # parseur HEX + TP + DM1
        │       └── spn_formulas.dart              # formules de conversion SPN
        ├── diagnostics/presentation/      # LiveDiagnosticScreen + widgets
        ├── knowledge/                     # recherche DTC + dépôt SQL
        └── checklist/                     # pré-shift (modèles, dépôt, écran)
```

## Installation

```bash
cd enginscan
flutter create . --org com.terrain --platforms android   # génère android/
flutter pub get
```

Ajoutez ensuite les permissions Bluetooth dans
`android/app/src/main/AndroidManifest.xml` (dans `<manifest>`, au niveau de
`<uses-feature>`) :

```xml
<uses-feature android:name="android.hardware.bluetooth" android:required="true"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                 xmlns:tools="http://schemas.android.com/tools"
                 tools:targetApi="s"
                 android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
```

Laissez `minSdkVersion` par défaut (≥ 21) — compatible `flutter_bluetooth_serial`.

## Build & signature Android
### Livraisons (téléchargement direct)

| Version | Lien | Taille | SHA-256 |
|---|---|---|---|
| **Release** (production) | https://files.catbox.moe/577q4k.apk | 8,3 Mo | `12345a2bc2b8234994dc32c6ec543bdede42fc3e27a382c5e56232d41aa121cc` |
| Debug (3 ABIs) | https://files.catbox.moe/ticmn2.apk | 70 Mo | `a61e256f28ee3466f9be03c3702ec0ad175c501c97bf46032536e41dcf5b27a2` |

Copies locales : `EnginScan-v1.0-release.apk` et `EnginScan-v1.0-debug.apk`
à la racine du projet. L'APK release est signé avec la clé de production
(certificat `CN=EnginScan Terrain`, SHA-256 `327f7d7c…9612c4` — voir plus bas).

### APK debug (référence terrain)

### APK debug (référence terrain)

Un APK installable de test est livré :

```text
build/app/outputs/flutter-apk/app-debug.apk   (~70 Mo, 3 ABIs, signé clé debug)
```

```bash
flutter build apk --debug     # regenere l'APK (aucun reseau requis)
```

Note machine : hôte **ARM64**. Le cache Flutter 3.24.5 ne contient que des
`gen_snapshot` x86_64 (pas de zip `linux-arm64` pour ce moteur — 404 sur le
serveur d'artefacts). Le compilateur AOT tourne donc sous **Box64**
(traducteur x86_64→ARM64, `apt install box64`) via un shim :

```text
/opt/flutter/bin/cache/artifacts/engine/android-*-release/linux-arm64/gen_snapshot
  → #!/bin/sh
    exec /usr/bin/box64 "<...>/linux-x64/gen_snapshot" "$@"
```

```bash
flutter build apk --release --target-platform android-arm64   # mono-ABI, suffit pour un appareil physique
```

> Si le cache est régénéré (`flutter precache --android`), recréer les shims
> pour les 3 ABI (android-arm64-release, android-arm-release,
> android-x64-release) après le téléchargement.

### Signature release

Clé de production générée localement, **ne quitte jamais la machine** :

| Fichier | Rôle |
|---|---|
| `android/app/enginscan-release.jks` | keystore PKCS12, RSA 2048, validité 30 ans |
| `android/key.properties` | `storeFile`, `storePassword`, `keyAlias`, `keyPassword` |

Les deux sont exclus du VCS (`.gitignore`). `android/app/build.gradle` signe
en release avec cette clé dès que `key.properties` existe, sinon retombe sur
la clé debug — les builds locaux ne cassent jamais.

Rotation : conserver une **copie chiffrée** du `.jks` et du mot de passe.
Sans eux, plus aucune mise à jour ne pourra être installée par-dessus
l'application (Android exige une signature identique).

## Logique de parsing CAN/J1939 (résumé)

1. **Identifiant 29 bits** : `[28:26]` priorité, `[25:24]` DP, `[23:16]` PF,
   `[15:8]` PS (= destination si PF < 240 → PDU1, sinon partie du PGN), `[7:0]`
   adresse source. PGN = `(ID >> 8) & 0x3FFFF` avec PS masqué pour le PDU1.
2. **Endianness** : J1939 transmet l'octet de **poids faible en premier**.
   Ex. régime moteur SPN 190 (octets 4-5 de l'EEC1) :
   `rpm = (data[4] | data[5] << 8) × 0,125`.
3. **DM1 (PGN 65226)** : octet 0 = voyants (MIL/STOP/ambre/protection, 2 bits
   chacun), puis blocs de 4 octets par défaut :
   `SPN = b0 | b1<<8 | (b2&0x07)<<16`, `FMI = (b2>>3)&0x1F`,
   occurrences = `b3&0x7F`. Slots vides remplis de `FF` (ou `00`).
4. **Transport Protocol** (> 8 octets) : contrôle `0xEC00` (taille + PGN
   transporté) puis données `0xEB00` (octet 0 = séquence). Réassemblage par
   source, puis reconstruction de l'ID final.
5. **Donnée invalide** : tous les bits à 1 (`FF…`) = « non disponible » → la
   valeur n'est pas affichée.

## Limites connues (honnêteté d'ingénieur)

- La **pression hydraulique** n'a pas de SPN standard J1939 : chaque
  constructeur utilise un PGN propriétaire (gabarit `oemSpecific` fourni dans
  `spn_formulas.dart`, à calibrer selon la machine).
- Certains boîtiers clones gèrent mal `AT MA` ou `ATH1` : préférez ELM327
  v1.4+/v1.5 ou OBDLink MX+ ; le sélecteur de protocole permet de basculer
  vers CAN 500 kbps (`7`) sur machines récentes.
- Les fiches fournies sont des bases de dépannage terrain : la documentation
  constructeur reste la référence contractuelle.

## Sécurité

Ne manipulez jamais l'application en conduisant. Lecture bus conseillée
contact mis / moteur arrêté pour le scan DTC ; live data moteur tournant =
opérateur présent aux commandes.
