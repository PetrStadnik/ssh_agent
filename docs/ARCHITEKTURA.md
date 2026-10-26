# Architektura

## Přehled

```
┌────────────────────────────── Flutter aplikace (app/) ──────────────────────────────┐
│  UI ve stylu Claude                    │  Stav a data                                │
│  ─ postranní panel (servery, chaty)    │  AppState (provider/ChangeNotifier)         │
│  ─ chat: bubliny, markdown, přemýšlení │  ─ nastavení, profily serverů, konverzace   │
│  ─ karty volaných funkcí + výstupy     │  ─ běžící agenti, rušení, TOFU klíčů        │
│  ─ composer: výběr serveru a modelu    │  Storage: JSON soubory + úložiště klíčů OS  │
└──────────────────────────────────────────┬──────────────────────────────────────────┘
                                           │ events (Stream<AgentEvent>)
┌──────────────────────── ssh_agent_core (čistý Dart, packages/) ─────────────────────┐
│  agent/   Agent – smyčka model → nástroje → model; AgentTurn/Conversation          │
│  llm/     OllamaClient (/api/chat) · OpenAiCompatibleClient (/v1/chat/completions)  │
│           parser volání nástrojů zapsaných textem                                   │
│  tools/   47 read-only nástrojů, validace argumentů, sestavení příkazu, ToolRegistry│
│  remote/  RemoteSession (pracovní adresář, su/sudo) · SshExecutor (dartssh2)        │
└───────────────┬───────────────────────────────────────────────┬─────────────────────┘
                │ HTTP (localhost nebo LAN)                     │ SSH (exec kanály)
        ┌───────▼────────┐                              ┌───────▼────────┐
        │ Ollama /       │                              │  VPS / server  │
        │ LM Studio /    │                              │  (Linux)       │
        │ llama.cpp      │                              └────────────────┘
        └────────────────┘
```

**Proč takto:**

- **Jádro je čistý Dart bez Flutteru** → stejný kód běží ve Windows aplikaci,
  na Androidu, iOS, macOS, Linuxu i v CLI a dá se testovat obyčejným `dart test`
  (včetně integračních testů proti skutečnému `sshd`).
- **Flutter** dává jeden kód UI pro Windows, Android i iOS (viz [MOBIL.md](MOBIL.md)).
- **SSH v čistém Dartu** (`dartssh2`) – žádná nativní knihovna, žádný `ssh.exe`,
  funguje na mobilu stejně jako na desktopu.
- **Model za abstrakcí `LlmClient`** – Ollama (doporučeno) nebo jakýkoli
  OpenAI‑kompatibilní server; přidání dalšího je jedna třída.

## Průběh jednoho dotazu

1. Uživatel napíše otázku; `AppState.send()` vytvoří `UserTurn` a prázdný `AgentTurn`.
2. Naváže se (nebo znovu použije) SSH spojení k vybranému serveru – agent při tom
   pošle `AgentConnecting` / `AgentConnected` (s dobou připojení). Klíč serveru se
   ověří proti uloženému otisku (TOFU – při prvním připojení se zeptá uživatele,
   při změně varuje).
3. `Agent.run()` sestaví zprávy: systémový prompt (server, uživatel, adresář, pravidla
   read-only, jazyk odpovědi), zkrácenou historii konverzace a otázku. Přidá definice
   nástrojů (JSON schema) – jen povolené skupiny.
4. `AgentStepStarted` (číslo kroku, odhad velikosti vstupu v tokenech) a model
   streamuje odpověď. Text a „přemýšlení“ se průběžně zobrazují; `AgentAssistantMessage`
   nese dobu kroku a statistiky z Ollamy (načtení modelu, čtení vstupu, tokeny).
5. Pokud model zavolá funkce:
   - `ToolRegistry.prepare()` ověří název a argumenty (typy, rozsahy, výčty, zakázané
     znaky) a sestaví **skript z pevné šablony**, argumenty vždy v uvozovkách;
   - UI dostane `AgentToolCallStarted` (název, argumenty, skript, přesný příkaz,
     server, uživatel, adresář) – **uživatel vždy vidí, co se spouští**;
   - volitelně potvrzení uživatelem;
   - `RemoteSession.run()` → SSH exec s timeoutem a limitem výstupu; stdout a stderr
     se během běhu posílají jako `AgentToolOutput`, takže UI ukazuje výstup ze serveru
     živě (karta funkce, počet řádků, uplynulý čas);
   - výsledek (`AgentToolCallFinished`) se zobrazí celý; modelu se pošle zkrácená verze
     (začátek + konec) s návratovým kódem a poznámkami.
6. Model dostane výsledky a buď volá další funkce, nebo odpoví. Limit kroků (výchozí 20),
   ochrana proti opakování stejného volání.
   UI z událostí odvozuje aktuální fázi (`AgentTurn.phase`: připojování, čekání na
   model, přemýšlení, psaní, běh příkazu, předání výsledku) a ukazuje ji s časem –
   uživatel tak nikdy nekouká na prázdné „Pracuji…“.
7. Konverzace se uloží (JSON). Při další otázce se z ní zrekonstruuje historie
   pro model (staré výstupy se zkracují, aby se vešly do kontextu).

## Klíčové soubory

| Soubor | Účel |
|---|---|
| `packages/ssh_agent_core/lib/src/tools/catalog/*.dart` | definice všech nástrojů (šablony příkazů) |
| `packages/ssh_agent_core/lib/src/tools/tool_registry.dart` | výběr, validace, spuštění, formátování výstupu pro model |
| `packages/ssh_agent_core/lib/src/util/shell.dart` | uvozování argumentů (`shQuote`, `shPath`) |
| `packages/ssh_agent_core/lib/src/remote/remote_session.dart` | obálka příkazu: prostředí, `cd`, `sudo`/`su` |
| `packages/ssh_agent_core/lib/src/remote/ssh_executor.dart` | SSH spojení, timeouty, limity, heslo pro `su` přes PTY |
| `packages/ssh_agent_core/lib/src/llm/*.dart` | klienti modelů, streamování, záložní parser volání |
| `packages/ssh_agent_core/lib/src/agent/agent.dart` | smyčka agenta, opakování při chybách modelu |
| `packages/ssh_agent_core/lib/src/agent/conversation.dart` | ukládaný model konverzace, historie pro model |
| `app/lib/state/app_state.dart` | stav aplikace, napojení agenta na UI |
| `app/lib/ui/tool_card.dart` | karta volané funkce (příkaz, výstup, stav) |

## Obálka příkazu

Každý nástroj má jen „skript“ (např. `stat -- '/etc/passwd'`). `RemoteSession` ho obalí:

```
sh -c '<spouštěč: bash pokud existuje, jinak sh>' sh '<skript>'
         └─ export LC_ALL=C … (anglické, předvídatelné výstupy, žádný pager/barvy)
         └─ set -o pipefail (správné návratové kódy i při zkracování výstupu)
         └─ AWK_LINEWISE='-W interactive', pokud je awk = mawk (Debian/Ubuntu) –
            omezovač řádků pak pouští výstup hned, ne až po skončení příkazu
         └─ cd -- '<pracovní adresář agenta>'
```

Při přepnutí uživatele: `sudo -n|-S -u '<uživatel>' -- …` nebo
`su -s /bin/sh '<uživatel>' -c …` (heslo se zadá na pseudo-terminálu, modelu se nikdy
neposílá).

## Přidání nového nástroje

1. Do příslušného souboru v `tools/catalog/` přidejte `ToolDefinition`:
   název, kategorie, anglický popis pro model, český `summary`, parametry
   a `script` – **jen čtecí příkazy, argumenty pouze přes `a.path()`, `a.quoted()`,
   `a.ident()` nebo validovaná čísla**.
2. Přidejte vzorové argumenty do `test/tool_samples.dart`.
3. `dart test` – statický test ověří, že skript neobsahuje zapisující příkazy ani
   přesměrování do souborů a že nepřátelské argumenty zůstanou v uvozovkách;
   integrační test ho spustí na skutečném serveru.
4. Vygenerujte dokumentaci: `dart run tool/gen_tools_doc.dart > ../../docs/NASTROJE.md`.

## Rozšíření o další model / server

Implementujte `LlmClient` (`chat`, `listModels`, `modelInfo`) a přidejte hodnotu do
`LlmProvider`. Agent i UI zůstávají beze změny.
