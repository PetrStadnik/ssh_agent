# Vývoj a testování

## Struktura repozitáře

```
app/                        Flutter aplikace (Windows, Android, iOS, macOS, Linux)
  lib/state/                stav aplikace, ukládání
  lib/ui/                   obrazovky a komponenty (chat, panel, nastavení)
  test/                     widget testy, generátor snímků obrazovky
packages/ssh_agent_core/    jádro v čistém Dartu
  lib/src/                  agent, llm, tools, remote
  bin/ssh_agent.dart        CLI klient
  test/                     unit testy, test/integration = proti skutečnému sshd
  tool/gen_tools_doc.dart   generátor docs/NASTROJE.md
docs/                       dokumentace
.github/workflows/          CI: testy, build Windows a Android
```

## Požadavky

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable, obsahuje Dart),
- Windows build: Visual Studio 2022 s úlohou **Desktop development with C++**,
- Android build: Android Studio (SDK + JDK 17).

## Spuštění aplikace

```bash
cd app
flutter pub get
flutter run -d windows        # nebo: -d linux, -d macos, -d <telefon>
```

Release pro Windows:

```powershell
cd app
flutter build windows --release
# složka app\build\windows\x64\runner\Release\ = hotová aplikace (ssh_agent.exe + DLL + data)
```

Celou složku `Release` lze zkopírovat/zazipovat a spustit na jiném PC (Windows 10/11 x64).
Hotový ZIP sestavuje i GitHub Actions (artefakt `ssh-agent-windows`).

## Testy

```bash
# jádro – unit testy (rychlé, bez sítě)
cd packages/ssh_agent_core
dart pub get
dart analyze
dart test --exclude-tags integration

# aplikace – widget testy
cd app
flutter analyze
flutter test test/app_test.dart

# snímky obrazovky (PNG do zadané složky)
SCREENSHOT_DIR=/tmp/shots flutter test test/screenshots
```

### Integrační testy proti skutečnému SSH serveru

Spustí všech 48 nástrojů, `cd`, `switch_user` (sudo i su s heslem), přihlášení heslem,
zašifrovaný klíč, ověření otisku klíče serveru a pokusy o shell injection.

Nejjednodušší je testovací kontejner:

```bash
docker run -d --name agent-sshd -p 2222:22 ubuntu:24.04 sleep infinity
docker exec agent-sshd bash -c '
  apt-get update -qq && apt-get install -y -qq openssh-server sudo acl lsof file iproute2 cron >/dev/null &&
  useradd -m -s /bin/bash -c "Agent Test,,,,agent@example.com" agent && echo agent:agentpass | chpasswd && echo root:rootpass | chpasswd &&
  echo "*/5 * * * * /usr/bin/uptime" | crontab -u agent - &&
  echo "agent ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent &&
  mkdir -p /run/sshd /srv/data && echo secret=42 > /srv/data/app.conf && gzip -c /etc/passwd > /srv/data/old.log.gz &&
  useradd -m other && /usr/sbin/sshd'
ssh-keygen -t ed25519 -N '' -f /tmp/agent_key
ssh-keygen -t ed25519 -N 'keypass' -f /tmp/agent_key_enc
docker exec -i agent-sshd bash -c 'mkdir -p ~agent/.ssh && cat >> ~agent/.ssh/authorized_keys && chown -R agent: ~agent/.ssh && chmod 700 ~agent/.ssh' < <(cat /tmp/agent_key.pub /tmp/agent_key_enc.pub)

cd packages/ssh_agent_core
SSH_TEST_HOST=127.0.0.1 SSH_TEST_PORT=2222 SSH_TEST_USER=agent \
SSH_TEST_KEY=/tmp/agent_key SSH_TEST_SUDO=1 SSH_TEST_PASSWORD=agentpass \
SSH_TEST_ROOT_PASSWORD=rootpass SSH_TEST_ENC_KEY=/tmp/agent_key_enc \
SSH_TEST_ENC_PASSPHRASE=keypass SSH_TEST_REPORT=/tmp/report.txt \
dart test test/integration
```

`SSH_TEST_REPORT` uloží výstupy všech nástrojů do souboru pro kontrolu.

## CLI

Stejné jádro jako aplikace, užitečné pro ladění modelu nebo serveru:

```bash
cd packages/ssh_agent_core
dart run ssh_agent_core:ssh_agent --help
dart run ssh_agent_core:ssh_agent --list-tools

# jeden nástroj bez modelu
dart run ssh_agent_core:ssh_agent --host 10.0.0.5 --user admin --key ~/.ssh/id_ed25519 \
  --tool stat --args '{"path": "/etc/passwd"}'

# otázka pro agenta (Ollama na localhostu)
dart run ssh_agent_core:ssh_agent --host 10.0.0.5 --user admin --key ~/.ssh/id_ed25519 \
  --model qwen3.5:9b "Které služby naslouchají na síti?"

# interaktivně, s potvrzováním každého příkazu
dart run ssh_agent_core:ssh_agent --host 10.0.0.5 --user admin --key ~/.ssh/id_ed25519 --approve
```

Při prvním připojení CLI vypíše otisk klíče serveru; příště ho předejte přes
`--host-key SHA256:...`.

## Přidání nástroje

Viz [ARCHITEKTURA.md – Přidání nového nástroje](ARCHITEKTURA.md#přidání-nového-nástroje).
