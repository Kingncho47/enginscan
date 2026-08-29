# Build APK - EnginScan v1.1.0

## Prérequis

- **Flutter SDK** 3.4.0 ou supérieur
- **Android SDK** API 21 ou supérieur  
- **Java JDK** 11 ou supérieur
- **Gradle** (inclus avec Flutter)

## Installation rapide (Linux/macOS/WSL)

### 1. Installer Flutter
```bash
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:$(pwd)/flutter/bin"
flutter doctor
```

### 2. Configurer Android SDK
```bash
# Télécharger et installer Android Command-line Tools
# Puis accepter les licences
flutter config --android-sdk /path/to/android-sdk
```

## Build APK

### Debug APK (développement, ~70 Mo)
```bash
cd enginscan
flutter clean
flutter pub get
flutter build apk --debug
```

Sortie: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK (production, ~8 Mo)
```bash
flutter build apk --release
```

Sortie: `build/app/outputs/flutter-apk/app-release.apk`

### AAB Bundle (Google Play)
```bash
flutter build appbundle --release
```

Sortie: `build/app/outputs/bundle/release/app-release.aab`

## Signature de clé (Release)

Pour les builds release, une clé de signature est requise :

```bash
# Générer une clé (une seule fois)
keytool -genkey -v -keystore ~/enginscan.jks -keyalg RSA -keysize 2048 -validity 10000 -alias enginscan

# Créer android/key.properties
cat > android/key.properties <<EOF
storePassword=<votre_password>
keyPassword=<votre_key_password>
keyAlias=enginscan
storeFile=~/.keystore/enginscan.jks
EOF

# Builder l'APK signé
flutter build apk --release
```

## Installation sur appareil

```bash
# APK debug
adb install build/app/outputs/flutter-apk/app-debug.apk

# APK release
adb install build/app/outputs/flutter-apk/app-release.apk
```

## Dépannage

| Erreur | Solution |
|--------|----------|
| `Android SDK not found` | Définir `ANDROID_HOME` ou utiliser `flutter config --android-sdk` |
| `Gradle build failed` | Exécuter `flutter clean` puis `flutter pub get` |
| `Bluetooth permissions` | Vérifier `android/app/src/main/AndroidManifest.xml` |

## Ressources

- [Flutter Build APK](https://docs.flutter.dev/deployment/android)
- [Android Keystore](https://developer.android.com/studio/publish/app-signing)
- [SAE J1939 Spec](https://www.sae.org/standards/content/j1939/)
