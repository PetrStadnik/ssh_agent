# Bezpečnost a záruka „jen pro čtení“

## Co agent nemůže

Agent nemá k dispozici obecný příkaz shellu. Smí volat **jen 54 předdefinovaných
funkcí** ([NASTROJE.md](NASTROJE.md)), z nichž žádná:

- nevytváří, nemění, nepřesouvá ani nemaže soubory a adresáře,
- nemění oprávnění, vlastníky, ACL ani atributy,
- nespouští, nezastavuje ani nerestartuje služby, neukončuje procesy,
- neinstaluje balíčky, nemění uživatele, cron, firewall ani síť,
- nestahuje nic z internetu a nikam neposílá data ze serveru.

Výjimkou jsou jen síťové diagnostiky (`ping`, `dns_lookup`, `port_check`,
`internet_check`), které ze serveru odešlou pár malých testovacích paketů: ICMP ping,
DNS dotaz nebo otevření a hned zavření TCP spojení (`internet_check` kontaktuje
1.1.1.1, example.com a OpenDNS kvůli veřejné IP). Nic se tím nemění ani nestahuje.
Pokud ani to nechcete, vypněte skupinu **Síť** v Nastavení → Agent.

## Jak je to zajištěno

1. **Uzavřená sada příkazů.** Každá funkce má pevnou šablonu skriptu v kódu
   (`packages/ssh_agent_core/lib/src/tools/catalog/`). Model vybírá jen funkci a
   hodnoty parametrů.
2. **Argumenty nikdy nejsou interpretovány shellem.** Každá textová hodnota je v
   jednoduchých uvozovkách (`shQuote`), cesty začínající `-` dostanou předponu `./`,
   za přepínači je `--`. Jména uživatelů, služeb, kontejnerů a časové výrazy se navíc
   validují regulárním výrazem; čísla se ořežou do povoleného rozsahu; znaky NUL a konce
   řádků jsou zakázané. Nelze tak „podstrčit“ `; rm -rf /`, `$(…)`, `` `…` ``,
   přesměrování `>` ani další přepínače (např. `-delete`/`-exec` u `find`).
3. **Automatické testy** (`packages/ssh_agent_core/test/tools_test.dart`):
   - žádný sestavený skript neobsahuje zapisující příkazy (`rm`, `mv`, `cp`, `chmod`,
     `tee`, `dd`, `sed -i`, `find -delete/-exec`, `systemctl start/stop`, `crontab -e`,
     `kill`, …) ani přesměrování do souboru,
   - `crontab` se nikde nevolá jinak než s `-l` (bez něj by crontab nahradil),
   - pro každý textový parametr každé funkce se zkouší nepřátelské hodnoty a ověřuje,
     že po rozboru shellem zůstanou celé v uvozovkách,
   - integrační test spouští útoky (`'; touch /tmp/x; '`, `$(touch …)`, …) proti
     skutečnému SSH serveru a ověřuje, že soubor nevznikl.
4. **Stdin je vždy uzavřený**, žádný příkaz nemůže čekat na vstup; každý příkaz má
   časový limit a limit velikosti výstupu.
5. **Transparentnost:** u každého volání vidíte název funkce, argumenty, skript,
   přesný příkaz odeslaný přes SSH, server, uživatele, adresář, návratový kód a celý
   výstup. Volitelně lze vyžadovat **potvrzení každého příkazu** (Nastavení → Agent).

## Zbytková rizika (čtěte!)

- **Čtení citlivých dat.** Čtecí přístup je pořád přístup: agent může přečíst např.
  konfigurační soubory s hesly. Výstupy jdou jen do lokálního modelu a do vaší
  aplikace (nic se neposílá do cloudu), konverzace se ukládají lokálně.
- **SSH účet může víc než agent.** Záruka read-only je vynucena aplikací, ne serverem.
  Kdo získá uložené přihlašovací údaje, může s nimi dělat cokoli, co účet dovolí.
  Proto doporučujeme samostatný účet s minimálními právy (níže).
- **Přepínání uživatele (sudo/su).** Funkce `switch_user` spouští *stejné čtecí
  funkce* jako jiný uživatel (typicky root). Aby to šlo, musí mít SSH účet právo
  spustit `sh` jako cílový uživatel – tedy na serveru fakticky plná práva. Zapínejte to
  jen pro servery, kde je to potřeba. Použití sudo/su se zapisuje do systémového logu.
- **Prompt injection.** Text přečtený ze serveru (soubory, logy) může obsahovat
  „instrukce“ pro model. Systémový prompt modelu říká, aby je ignoroval, a hlavně:
  i zmanipulovaný model může volat jen čtecí funkce.
- **Neověřený klíč serveru.** Při prvním připojení porovnejte otisk klíče
  (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` na serveru). Při změně klíče
  aplikace důrazně varuje.
- **Server modelu bez autentizace.** Nevystavujte port Ollamy (11434) do internetu.

## Doporučené nastavení serveru: účet jen pro čtení

```bash
# 1) samostatný uživatel bez sudo
sudo useradd -m -s /bin/bash ssh-agent-ro

# 2) čtení systémových logů (journal, /var/log/auth.log apod.)
sudo usermod -aG adm,systemd-journal ssh-agent-ro

# 3) čtení konkrétních adresářů aplikací přes ACL (bez změny vlastníků)
sudo setfacl -R -m u:ssh-agent-ro:rX /var/www /etc/nginx
sudo setfacl -R -d -m u:ssh-agent-ro:rX /var/www   # i pro nově vzniklé soubory

# 4) přihlášení jen klíčem (veřejný klíč z aplikace / vašeho PC)
sudo install -d -m 700 -o ssh-agent-ro -g ssh-agent-ro /home/ssh-agent-ro/.ssh
echo 'ssh-ed25519 AAAA... ssh-agent' | sudo tee /home/ssh-agent-ro/.ssh/authorized_keys
sudo chown ssh-agent-ro: /home/ssh-agent-ro/.ssh/authorized_keys
sudo chmod 600 /home/ssh-agent-ro/.ssh/authorized_keys
```

Volitelně v `/etc/ssh/sshd_config.d/ssh-agent-ro.conf` zakažte přesměrování:

```
Match User ssh-agent-ro
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    AllowAgentForwarding no
```

Některé informace (`lastb`, `/etc/shadow`, cizí crontaby, `sshd -T`, firewall) vyžadují
roota – bez něj vám agent řekne, že nemá oprávnění. To je u účtu jen pro čtení
očekávané a správné chování.

## Kde jsou uložené přihlašovací údaje

| Údaj | Úložiště |
|---|---|
| Hesla, privátní klíče, passphrase, hesla pro sudo/su, API klíč | zabezpečené úložiště OS přes `flutter_secure_storage` (Windows: soubory šifrované AES‑GCM s klíčem ve Správci pověření Windows, Android: Keystore, iOS/macOS: Keychain, Linux: Secret Service) |
| Profily serverů (bez tajemství), nastavení, konverzace | JSON v adresáři dat aplikace (cesta je vidět v Nastavení → Vzhled a data) |

Modelu se nikdy neposílají hesla ani klíče – jen výstupy čtecích příkazů.
