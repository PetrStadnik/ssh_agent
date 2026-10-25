# Android a iOS

Aplikace je napsaná ve **Flutteru** a celé jádro (SSH, nástroje, agent, klienti modelů)
je **čistý Dart** bez nativních závislostí. Projekt `app/` už obsahuje platformní složky
`android/` a `ios/` (i `macos/`, `linux/`), takže mobilní verze vznikne bez úprav kódu –
stačí ji sestavit.

## Co je na mobilu jinak

| Oblast | Řešení |
|---|---|
| **Model** | Telefon dobrý agentní model neutáhne. Aplikace se připojí k Ollamě/LM Studiu na vašem PC v síti (`http://<IP-PC>:11434`) nebo přes VPN (WireGuard, Tailscale). Návod: [LOKALNI_MODEL.md, kap. 6](LOKALNI_MODEL.md#6-model-pro-telefon-androidios). |
| **Rozložení** | Pod 900 px šířky se postranní panel mění na vysouvací menu (☰), nastavení se otevírá na celou obrazovku. Ověřeno widget testem (`app/test/app_test.dart`). |
| **Privátní klíče** | Tlačítko *Vybrat…* použije systémový výběr souboru a obsah klíče uloží do Keystore/Keychain (na mobilu nejsou stabilní cesty k souborům). Klíč lze i vložit jako text. |
| **Hesla** | Android Keystore / iOS Keychain (`flutter_secure_storage`). |
| **Síť** | Android: oprávnění `INTERNET` a `usesCleartextTraffic` (HTTP k Ollamě v LAN) jsou nastavené v `AndroidManifest.xml`. iOS: `NSLocalNetworkUsageDescription` v `Info.plist` (dotaz na přístup k místní síti). |
| **Na pozadí** | Mobilní OS může aplikaci na pozadí uspat – dlouhé dotazy nechte doběhnout s aplikací v popředí. Rozpracovanou odpověď lze vždy poslat znovu. |

## Sestavení pro Android

Požadavky: Flutter SDK, Android Studio (Android SDK, JDK 17).

```bash
cd app
flutter doctor            # zkontroluje Android toolchain
flutter run -d <zařízení> # ladění na připojeném telefonu / emulátoru
flutter build apk --release
# výsledek: app/build/app/outputs/flutter-apk/app-release.apk
```

Pro Google Play použijte `flutter build appbundle` a vlastní podpisový klíč
(<https://docs.flutter.dev/deployment/android>). Šablona projektu podepisuje release
build ladicím klíčem – pro vlastní použití (sideload) to stačí.

Hotové APK sestavuje i GitHub Actions (artefakt `ssh-agent-android-apk`).

## Sestavení pro iOS

Požadavky: Mac s Xcode, Apple ID (pro instalaci na vlastní iPhone stačí bezplatný
vývojářský účet).

```bash
cd app
open ios/Runner.xcworkspace     # v Xcode nastavte Signing & Capabilities → Team
flutter run -d <iPhone>
flutter build ipa               # pro TestFlight / App Store
```

Minimální verze iOS je 15.0.

## Možný další vývoj

- **Model přímo v telefonu:** malé modely (např. `qwen3.5:4b` v GGUF) lze spouštět
  přes llama.cpp; stačí implementovat další `LlmClient` (rozhraní v
  `packages/ssh_agent_core/lib/src/llm/llm_client.dart`). Kvalita volání nástrojů
  u modelů do 4B je ale znatelně horší.
- **Sdílení serverů mezi PC a telefonem:** export/import profilů (bez hesel) do JSON.
