# Lokální model – výběr, stažení a zprovoznění

Agent nepotřebuje žádnou cloudovou službu: jazykový model běží na vašem počítači
(nebo na jiném počítači ve vaší síti) a aplikace s ním mluví přes HTTP API.
Doporučená a nejjednodušší cesta je **Ollama + Qwen3.5 9B**.

- [1. Doporučení v kostce](#1-doporučení-v-kostce)
- [2. Instalace Ollama na Windows krok za krokem](#2-instalace-ollama-na-windows-krok-za-krokem)
- [3. Propojení s aplikací](#3-propojení-s-aplikací)
- [4. Analýza: proč právě tyto modely](#4-analýza-proč-právě-tyto-modely)
- [5. Alternativy k Ollamě: LM Studio, llama.cpp](#5-alternativy-k-ollamě-lm-studio-llamacpp)
- [6. Model pro telefon (Android/iOS)](#6-model-pro-telefon-androidios)
- [7. Řešení problémů](#7-řešení-problémů)

---

## 1. Doporučení v kostce

> Stav k **říjnu 2026**. Modely se vyvíjejí rychle – názvy (tagy) si ověřte na
> <https://ollama.com/library> a v aplikaci tlačítkem **Nastavení → Model → Ověřit**,
> které zkontroluje, že model existuje a podporuje volání nástrojů (`tools`).

| Váš hardware | Doporučený model | Alternativa |
|---|---|---|
| **GPU s 8 GB VRAM** (RTX 3060/4060, …) – *nejčastější* | **`qwen3.5:9b`** (≈ 6,6 GB) | `gemma4:e4b` |
| GPU 12–16 GB VRAM | `qwen3.5:9b` s kontextem 64k | `gemma4:26b` (část v RAM), `gpt-oss:20b` |
| GPU 24 GB VRAM (RTX 3090/4090) | `gemma4:31b` nebo `gemma4:26b` | novější Qwen (27B), pokud je v knihovně |
| Jen CPU, 16 GB RAM | `qwen3.5:4b` (≈ 3,4 GB), přemýšlení vypnout | `gemma4:e4b` |
| Jen CPU, 32+ GB RAM | `gemma4:26b` (MoE – aktivní jen ~4B parametrů, na CPU použitelný) | `gpt-oss:20b` |

**Hlavní doporučení: `qwen3.5:9b`.** Důvody (podrobně v kapitole 4):

1. **Nejlepší volání nástrojů ve své velikosti** – výrobce uvádí BFCL‑V4 66,1 a TAU2 79,1,
   tedy výsledky srovnatelné s mnohem většími modely staršími o generaci.
2. **Čeština** – rodina Qwen3.5 je trénovaná na 201 jazycích; rozumí česky položeným
   otázkám a odpovídá česky.
3. **Vejde se na běžnou herní kartu** (8 GB VRAM) a v nouzi poběží i na CPU.
4. **Kontext až 256k tokenů** – výstupy příkazů jsou dlouhé, velký kontext pomáhá.
5. **Licence Apache 2.0**, nativní podpora `tools` a `thinking` v Ollamě.

Na slabších počítačích použijte `qwen3.5:4b`, na silných `gemma4:26b`/`gemma4:31b`.

---

## 2. Instalace Ollama na Windows krok za krokem

### 2.1 Požadavky

- Windows 10 22H2 nebo Windows 11, 64bit.
- Ideálně grafická karta **NVIDIA** (aktuální ovladač) nebo **AMD Radeon** (ROCm/Vulkan).
  Bez GPU vše funguje na CPU, jen pomaleji.
- Volné místo na disku: 5–25 GB podle modelu.

### 2.2 Instalace

1. Stáhněte instalátor z <https://ollama.com/download> (soubor `OllamaSetup.exe`)
   a spusťte ho. Instalace nepotřebuje administrátorská práva.

   *Alternativa přes příkazovou řádku:* `winget install --id Ollama.Ollama -e`
2. Po instalaci Ollama běží na pozadí (ikona lamy v oznamovací oblasti) a poslouchá
   na adrese `http://127.0.0.1:11434`.
3. Otevřete **PowerShell** a ověřte instalaci:

   ```powershell
   ollama --version
   ```

### 2.3 Stažení modelu

```powershell
# doporučený model (~6,6 GB)
ollama pull qwen3.5:9b

# slabší PC / jen CPU
ollama pull qwen3.5:4b
```

Ověřte, že model umí volat nástroje – v části **Capabilities** musí být `tools`:

```powershell
ollama show qwen3.5:9b
```

Krátký test (první spuštění chvíli trvá, model se načítá do paměti):

```powershell
ollama run qwen3.5:9b "Odpověz jednou větou česky: co dělá příkaz ls -la?"
```

Jestli model běží na GPU, zjistíte během běhu příkazem `ollama ps`
(sloupec PROCESSOR: `100% GPU` je ideální; `CPU/GPU` znamená, že se část modelu
nevešla do VRAM).

### 2.4 Doporučená nastavení Ollamy (volitelné)

Nastavují se jako **uživatelské proměnné prostředí** (Start → „Upravit proměnné
prostředí pro váš účet“, nebo příkazem `setx`). **Po změně Ollamu ukončete
(pravým na ikonu → Quit) a spusťte znovu.**

| Proměnná | Hodnota | K čemu |
|---|---|---|
| `OLLAMA_CONTEXT_LENGTH` | `32768` | Výchozí kontext. Aplikace ho u Ollamy posílá sama (`num_ctx`), ale hodí se pro jiné klienty a pro OpenAI endpoint `/v1`. Výchozí hodnota Ollamy bývá jen 4k. |
| `OLLAMA_FLASH_ATTENTION` | `1` | Rychlejší a úspornější výpočet pozornosti. |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | Asi poloviční paměť pro kontext (vyžaduje flash attention) – víc kontextu se vejde do VRAM. |
| `OLLAMA_MODELS` | např. `D:\ollama\models` | Uložení modelů na jiný disk. |
| `OLLAMA_HOST` | `0.0.0.0:11434` | Jen pokud se k modelu má připojit **telefon nebo jiný počítač** (viz kap. 6). |

```powershell
setx OLLAMA_FLASH_ATTENTION 1
setx OLLAMA_KV_CACHE_TYPE q8_0
setx OLLAMA_CONTEXT_LENGTH 32768
```

---

## 3. Propojení s aplikací

1. Spusťte SSH Agent → **Nastavení → Model**.
2. Server modelu: **Ollama**, adresa `http://127.0.0.1:11434` (výchozí).
3. Model: `qwen3.5:9b` (rozbalovací šipka nabídne modely stažené v Ollamě i doporučené).
4. Klikněte na **Ověřit** – aplikace vypíše počet modelů na serveru, zda model existuje
   a zda podporuje `tools` a `thinking`.
5. Doporučené hodnoty:
   - **Kontextové okno: 32k** (16k minimum; 64k pokud máte ≥ 12 GB VRAM),
   - **Teplota: 0,2** (spolehlivější volání nástrojů),
   - **Přemýšlení:** „Výchozí“. Pokud jsou odpovědi pomalé, dejte „Vypnuto“;
     u složitého pátrání může „Zapnuto“ zlepšit výsledek.

Rychlý test bez GUI (stejné jádro jako aplikace) – viz [VYVOJ.md](VYVOJ.md#cli):

```powershell
cd packages\ssh_agent_core
dart run ssh_agent_core:ssh_agent --host 203.0.113.10 --user admin `
  --key $HOME\.ssh\id_ed25519 --model qwen3.5:9b "Kdo se včera přihlásil přes SSH?"
```

---

## 4. Analýza: proč právě tyto modely

### 4.1 Co úloha od modelu vyžaduje

| Požadavek | Proč |
|---|---|
| **Spolehlivé volání funkcí (tool calling)** | Agent má 47 nástrojů; model musí vybrat správný, vyplnit platné JSON argumenty a nevymýšlet si neexistující. |
| **Vícekrokové uvažování** | Typický dotaz = 2–6 volání (např. `stat` → `last` → `journal`), model musí číst výstupy a rozhodnout o dalším kroku. |
| **Práce s dlouhým textem** | Výstupy `ls`, logů a `ps` jsou dlouhé; definice nástrojů samy zaberou ~6,6k tokenů. Potřeba je kontext ≥ 16k, ideálně 32k+. |
| **Čeština** | Dotazy i odpovědi jsou česky. |
| **Běh na běžném PC s Windows** | 8 GB VRAM je nejčastější konfigurace; musí fungovat i bez GPU. |
| **Volná licence** | Bez omezení komerčního použití. |
| **Podpora v Ollamě / LM Studiu** | Nativní parser tool calls, žádné ruční šablony. |

### 4.2 Srovnání kandidátů (stav 10/2026)

Hodnoty benchmarků jsou **údaje výrobců**; velikosti stažení odpovídají výchozí
kvantizaci v knihovně Ollama (Q4) a mohou se lišit.

| Model | Tag v Ollamě | Velikost | Kontext | Tool calling (výrobce) | Čeština | Licence | Poznámka |
|---|---|---|---|---|---|---|---|
| **Qwen3.5 9B** | `qwen3.5:9b` | ≈ 6,6 GB | 256k | BFCL‑V4 66,1 · TAU2 79,1 | ✔ (201 jazyků) | Apache 2.0 | **nejlepší poměr kvalita/velikost**, thinking zapnutý ve výchozím stavu |
| Qwen3.5 4B | `qwen3.5:4b` | ≈ 3,4 GB | 256k | nižší než 9B | ✔ | Apache 2.0 | pro slabý HW / CPU |
| Gemma 4 E4B | `gemma4:e4b` | několik GB | 128k | τ2 (průměr) 42,2 | ✔ (35+ jazyků) | Apache 2.0 | rychlý, ale v agentních úlohách slabší |
| Gemma 4 26B (MoE, ~4B aktivních) | `gemma4:26b` | ≈ 16–19 GB | 256k | τ2‑retail 85,5 | ✔ | Apache 2.0 | výborný pro 16–24 GB VRAM nebo CPU s 32 GB RAM |
| Gemma 4 31B | `gemma4:31b` | ≈ 19–20 GB | 256k | τ2‑retail 86,4 | ✔ | Apache 2.0 | nejkvalitnější z dostupných pro 24 GB VRAM |
| gpt-oss 20B | `gpt-oss:20b` | ≈ 14 GB | 128k | Tau‑bench retail 54,8 (high) | slabší | Apache 2.0 | silný v angličtině, thinking nelze vypnout |
| Ministral 3 8B/14B | `ministral-3:8b` | ≈ 6 GB | 256k | – | částečně | Apache 2.0 | alternativa, bez thinking |
| Llama 3.x 8B | `llama3.1:8b` | ≈ 5 GB | 128k | výrazně slabší | slabá | Llama licence | zastaralé, nedoporučeno |

Další novinky (např. Qwen3.6/3.8 27B, Granite 4.2 s oficiální podporou češtiny,
Nemotron 3.5) jsou slibné pro silnější HW, ale v době psaní nebyly k dispozici
nezávislé výsledky tool callingu – vyzkoušejte je stejným postupem jako v kap. 4.4.

### 4.3 Známé problémy a jak je aplikace řeší

- **Občas chybně zformátované volání nástroje** (Qwen3.5/3.6 v Ollamě – Ollama vrátí
  HTTP 500 nebo volání pošle jako text). Aplikace požadavek automaticky zopakuje
  (až 2×, potřetí s nápovědou) a umí přečíst i volání zapsané textem
  (`<tool_call>{…}</tool_call>`, JSON, `[TOOL_CALLS]`).
- **Malý výchozí kontext Ollamy** – aplikace posílá `num_ctx` z nastavení (výchozí 32k).
- **Model nepodporuje `think`** – aplikace to pozná a pošle požadavek znovu bez něj.
- **Dlouhé výstupy** – modelu se předá jen zkrácená verze (začátek + konec,
  výchozí 12 000 znaků), vy v chatu vidíte vše.
- **Smyčky** – stejné volání se 3× neprovede, počet kroků je omezen (výchozí 20).

### 4.4 Jak si modely porovnat sami

Nejlepší test je váš vlastní server. Položte každému modelu stejné otázky
(ideálně v novém chatu) a sledujte, zda volá správné nástroje a zda odpověď sedí:

1. „Kdy se naposledy změnil soubor /etc/passwd?“ (očekáváno: `stat`)
2. „Kdo se přihlásil přes SSH za posledních 7 dní a odkud?“ (`last`, případně `lastb`)
3. „Jaká oprávnění má uživatel www-data k /var/www?“ (`user_info`, `permissions`, `check_access`)
4. „Kde přesně ukládá nginx logy a konfiguraci?“ (`service_status`, `grep`/`find`)
5. „Obsahuje /etc/ssh/sshd_config povolené přihlášení roota heslem?“ (`grep` nebo `ssh_access`)
6. „Které procesy poslouchají na síti a pod jakým uživatelem?“ (`network`, `ps`)

Pod každou odpovědí vidíte model, počet příkazů a tokenů – snadno porovnáte i rychlost.

---

## 5. Alternativy k Ollamě: LM Studio, llama.cpp

Aplikace umí i **OpenAI‑kompatibilní API** (Nastavení → Model → *OpenAI‑kompatibilní*).

### LM Studio (grafické prostředí)

1. Nainstalujte z <https://lmstudio.ai>, v záložce *Discover* stáhněte např. Qwen3.5 9B (GGUF Q4_K_M).
2. Záložka *Developer* → **Start Server** (port 1234). Při načítání modelu nastavte
   *Context Length* na 32768.
3. V aplikaci: adresa `http://127.0.0.1:1234/v1`, název modelu přesně podle LM Studia.
   Modely s „Native“ podporou nástrojů mají v LM Studiu ikonu kladívka.

### llama.cpp (`llama-server`)

```powershell
llama-server -m C:\models\Qwen3.5-9B-Q4_K_M.gguf --jinja -c 32768 -ngl 99 --host 127.0.0.1 --port 8080
```

- `--jinja` zapne šablonu s podporou nástrojů (v nových verzích je výchozí – nevadí ho uvést),
- `-c` velikost kontextu, `-ngl 99` vše na GPU,
- **port uvádějte vždy explicitně** (výchozí port se mezi verzemi mění),
- v aplikaci adresa `http://127.0.0.1:8080/v1`.

---

## 6. Model pro telefon (Android/iOS)

Telefon dobrý agentní model neutáhne – aplikace na telefonu se připojuje k Ollamě
běžící na vašem PC:

1. Na PC nastavte `OLLAMA_HOST=0.0.0.0:11434` (viz 2.4) a restartujte Ollamu.
2. Povolte port ve firewallu (PowerShell jako správce):

   ```powershell
   New-NetFirewallRule -DisplayName "Ollama" -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow -Profile Private
   ```
3. V aplikaci na telefonu zadejte adresu PC, např. `http://192.168.1.20:11434`
   (IP zjistíte příkazem `ipconfig`). Android emulátor používá `http://10.0.2.2:11434`.
4. Mimo domácí síť použijte VPN (např. WireGuard/Tailscale) – **nevystavujte port
   11434 do internetu**, Ollama nemá autentizaci.

---

## 7. Řešení problémů

| Problém | Řešení |
|---|---|
| „Nelze se spojit se serverem modelu“ | Běží Ollama (ikona v liště)? Funguje `curl http://127.0.0.1:11434/api/tags`? Správná adresa v nastavení? |
| „model … not found“ | `ollama pull <model>`; název musí přesně odpovídat (`ollama list`). |
| „does not support tools“ | Zvolte model s `tools` v `ollama show`. |
| Odpovědi jsou velmi pomalé | `ollama ps` – běží model na GPU? Zkuste menší model, vypněte přemýšlení, zmenšete kontext. |
| Dlouho svítí „Model … zpracovává dotaz“ | Řádek „Krok 1 · …“ ukazuje, kolik trvalo načtení modelu a čtení vstupu. První dotaz čte ~9 000 tokenů (zadání + definice nástrojů) – na CPU to jsou i minuty. Aplikace model načítá do paměti hned po spuštění; pomůže GPU, menší model nebo vypnutí nepotřebných skupin nástrojů v Nastavení → Agent (méně definic = kratší vstup). |
| Model „zapomíná“ výsledky nebo odpovídá nesmyslně po mnoha krocích | Zvětšete kontext (64k), zmenšete „Délku výstupu předanou modelu“, zkuste větší model. |
| Model volá neexistující nástroje / špatné argumenty | Aplikace mu vrátí chybu a on to obvykle opraví. Pomůže nižší teplota, vypnutí nepotřebných skupin nástrojů, větší model. |
| Nedostatek VRAM | `OLLAMA_KV_CACHE_TYPE=q8_0`, menší kontext, menší model. |
