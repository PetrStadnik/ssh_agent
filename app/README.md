# SSH Agent – Flutter aplikace

Jedna kódová základna pro Windows, Android, iOS, macOS a Linux.

```bash
flutter pub get
flutter run -d windows     # nebo linux, macos, <telefon>
flutter test test/app_test.dart
```

- `lib/state/` – stav aplikace (`AppState`), nastavení, ukládání (JSON + úložiště klíčů OS)
- `lib/ui/` – rozhraní ve stylu Claude: postranní panel, chat, karty volaných funkcí, nastavení
- `lib/theme.dart` – barvy a písma

Logika agenta, SSH a klienti modelů jsou v `../packages/ssh_agent_core`.
Podrobnosti: [../README.md](../README.md), [../docs](../docs).
