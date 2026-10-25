# ssh_agent_core

Platformně nezávislé jádro aplikace SSH Agent (čistý Dart, `dart:io`):

- `lib/src/remote/` – SSH spojení (dartssh2), relace agenta (pracovní adresář, `su`/`sudo`), profily serverů,
- `lib/src/tools/` – katalog **read-only** nástrojů, validace argumentů, sestavení a spuštění příkazů,
- `lib/src/llm/` – klienti lokálních modelů (Ollama `/api/chat`, OpenAI-kompatibilní `/v1/chat/completions`),
- `lib/src/agent/` – smyčka agenta, události pro UI, systémový prompt, model konverzace.

Stejný kód používá Flutter aplikace (Windows/Android/iOS/Linux/macOS) i CLI:

```bash
dart run ssh_agent_core:ssh_agent --help
dart run ssh_agent_core:ssh_agent --list-tools
```

Testy: `dart test --exclude-tags integration` (integrační viz `docs/VYVOJ.md`).
