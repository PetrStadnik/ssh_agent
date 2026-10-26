# Katalog nástrojů agenta

> Soubor je generovaný z kódu (`packages/ssh_agent_core/tool/gen_tools_doc.dart`), needitujte ho ručně.

Agent smí volat **jen** tyto předdefinované funkce (48). Všechny pouze čtou – žádná nevytváří, nemění ani nemaže soubory, nemění oprávnění, nespouští/nezastavuje služby ani neukončuje procesy. Každý argument od modelu je validován a v příkazu je vždy v uvozovkách (viz [BEZPECNOST.md](BEZPECNOST.md)). Popisy pro model jsou anglicky, protože lokální modely angličtině v definicích nástrojů rozumí nejspolehlivěji.

Velikost všech definic posílaných modelu: ~25.0 tis. znaků (≈ 6.9 tis. tokenů). Skupiny lze v nastavení vypnout.

## Relace a navigace

| Funkce | Co dělá | Parametry |
|---|---|---|
| `pwd` | Aktuální pracovní adresář agenta | – |
| `cd` | Přesun do jiného adresáře (mění jen stav agenta, ne server) | `path` (text) **povinný** |
| `whoami` | Kdo jsem: uživatel, UID, skupiny | – |
| `switch_user` | Spouštět další příkazy jako jiný uživatel (su / sudo) *(jen když profil povoluje přepínání uživatele)* | `user` (text) **povinný** |
| `system_info` | Systém, distribuce, hostname, čas a časové pásmo serveru | – |

## Soubory a adresáře

| Funkce | Co dělá | Parametry |
|---|---|---|
| `ls` | Výpis adresáře (ls -la) s oprávněními, vlastníkem a časy | `path` (text, výchozí `.`)<br>`all` (ano/ne, výchozí `true`)<br>`sort` (name\|time\|size, výchozí `name`)<br>`recursive` (ano/ne, výchozí `false`)<br>`directory_itself` (ano/ne, výchozí `false`)<br>`max_lines` (číslo, výchozí `400`) |
| `tree` | Stromová struktura adresáře do zadané hloubky | `path` (text, výchozí `.`)<br>`depth` (číslo, výchozí `2`)<br>`dirs_only` (ano/ne, výchozí `false`)<br>`max_entries` (číslo, výchozí `300`) |
| `stat` | Metadata souboru: časy změn, vlastník, oprávnění, velikost | `path` (text) **povinný** |
| `file_type` | Typ souboru (text, binárka, archiv, ...) | `path` (text) **povinný** |
| `cat` | Obsah souboru (s limitem velikosti) | `path` (text) **povinný**<br>`max_bytes` (číslo, výchozí `16000`) |
| `head` | Prvních N řádků souboru | `path` (text) **povinný**<br>`lines` (číslo, výchozí `40`) |
| `tail` | Posledních N řádků souboru (např. logu) | `path` (text) **povinný**<br>`lines` (číslo, výchozí `40`) |
| `read_lines` | Konkrétní rozsah řádků souboru s čísly řádků | `path` (text) **povinný**<br>`start_line` (číslo) **povinný**<br>`end_line` (číslo) **povinný** |
| `wc` | Počet řádků, slov a bajtů | `path` (text) **povinný** |
| `grep` | Hledání textu v souborech (grep) | `pattern` (text) **povinný**<br>`path` (text, výchozí `.`)<br>`mode` (fixed\|basic\|extended\|perl, výchozí `extended`)<br>`ignore_case` (ano/ne, výchozí `false`)<br>`recursive` (ano/ne, výchozí `true`)<br>`include` (text)<br>`context_lines` (číslo, výchozí `0`)<br>`files_only` (ano/ne, výchozí `false`)<br>`max_results` (číslo, výchozí `150`) |
| `find` | Vyhledání souborů podle jména, typu, vlastníka, času, velikosti | `path` (text, výchozí `.`)<br>`name` (text)<br>`iname` (text)<br>`type` (file\|directory\|symlink)<br>`user` (text)<br>`group` (text)<br>`perm` (text)<br>`size` (text)<br>`modified_within_days` (číslo)<br>`modified_older_than_days` (číslo)<br>`modified_within_minutes` (číslo)<br>`newer_than` (text)<br>`max_depth` (číslo)<br>`details` (ano/ne, výchozí `false`)<br>`max_results` (číslo, výchozí `200`) |
| `recent_changes` | Nedávno změněné soubory, seřazené od nejnovějších | `path` (text, výchozí `/etc`)<br>`within_days` (číslo, výchozí `1`)<br>`within_minutes` (číslo)<br>`max_results` (číslo, výchozí `100`) |
| `du` | Velikost adresářů (du), největší první | `path` (text, výchozí `.`)<br>`depth` (číslo, výchozí `1`) |
| `disk_usage` | Obsazení disků a připojené souborové systémy | `include_mounts` (ano/ne, výchozí `false`) |
| `checksum` | Kontrolní součet souboru (sha256/md5/...) | `path` (text) **povinný**<br>`algorithm` (sha256\|sha1\|md5\|sha512, výchozí `sha256`) |
| `diff` | Rozdíly mezi dvěma soubory | `path_a` (text) **povinný**<br>`path_b` (text) **povinný** |
| `binary_peek` | Nahlédnutí do binárního souboru (hex / čitelné řetězce) | `path` (text) **povinný**<br>`mode` (hex\|strings, výchozí `hex`)<br>`offset` (číslo, výchozí `0`)<br>`length` (číslo, výchozí `512`) |
| `read_compressed` | Čtení komprimovaných (rotovaných) logů .gz/.xz/.bz2/.zst | `path` (text) **povinný**<br>`pattern` (text)<br>`lines` (číslo, výchozí `100`)<br>`from_end` (ano/ne, výchozí `false`) |

## Uživatelé a oprávnění

| Funkce | Co dělá | Parametry |
|---|---|---|
| `permissions` | Oprávnění cesty: vlastník, režim, každý adresář na cestě, ACL | `path` (text) **povinný** |
| `check_access` | Může uživatel X číst / zapisovat / spouštět cestu Y? | `user` (text) **povinný**<br>`path` (text) **povinný** |
| `list_users` | Všichni uživatelé a jejich vlastnosti: jméno, e-mail, heslo, přihlášení heslem (i přes SSH), klíče, skupiny | `only_login_users` (ano/ne, výchozí `false`)<br>`include_system` (ano/ne, výchozí `false`)<br>`limit` (číslo, výchozí `100`) |
| `user_info` | Detail uživatele: skupiny, domov, poslední přihlášení, sudo | `user` (text) **povinný** |
| `list_groups` | Skupiny a jejich členové | `group` (text) |
| `sudo_rights` | Sudo oprávnění, členové admin skupin, pravidla sudoers | `user` (text) |
| `ssh_access` | SSH přístup: authorized_keys uživatelů a nastavení sshd | `user` (text) |
| `shell_history` | Historie příkazů uživatele (bash, zsh, fish, mysql...) | `user` (text)<br>`lines` (číslo, výchozí `50`) |

## Přihlášení

| Funkce | Co dělá | Parametry |
|---|---|---|
| `logged_in_users` | Kdo je právě přihlášený (w / who) | – |
| `last` | Historie přihlášení (last) - kdo, odkud, kdy | `user` (text)<br>`limit` (číslo, výchozí `50`)<br>`since` (text) |
| `lastb` | Neúspěšné pokusy o přihlášení (lastb + log sshd) | `limit` (číslo, výchozí `50`)<br>`since` (text) |

## Procesy a prostředky

| Funkce | Co dělá | Parametry |
|---|---|---|
| `ps` | Běžící procesy (ps) s filtrem, řazením a stromem | `filter` (text)<br>`user` (text)<br>`sort` (cpu\|memory\|pid\|start, výchozí `cpu`)<br>`tree` (ano/ne, výchozí `false`)<br>`limit` (číslo, výchozí `50`) |
| `process_details` | Detail procesu: binárka, pracovní adresář, otevřené soubory, sockety | `pid` (číslo) **povinný** |
| `open_files` | Otevřené soubory procesu nebo kdo drží otevřený soubor (lsof) | `pid` (číslo)<br>`path` (text) |
| `resource_usage` | Zátěž: CPU, paměť, load, nejnáročnější procesy | – |

## Služby, logy a cron

| Funkce | Co dělá | Parametry |
|---|---|---|
| `services` | Seznam služeb (běžící / selhané / všechny / povolené) | `state` (running\|failed\|all\|enabled, výchozí `running`) |
| `service_status` | Stav služby, její konfigurace, spouštěný příkaz a poslední logy | `name` (text) **povinný**<br>`show_unit_file` (ano/ne, výchozí `false`) |
| `journal` | Systémový log (journalctl) podle služby, času, priority, textu | `unit` (text)<br>`since` (text)<br>`until` (text)<br>`priority` (emerg\|alert\|crit\|err\|warning\|notice\|info\|debug)<br>`grep` (text)<br>`kernel` (ano/ne, výchozí `false`)<br>`current_boot` (ano/ne, výchozí `false`)<br>`lines` (číslo, výchozí `100`) |
| `cron_jobs` | Naplánované úlohy: crontab, cron.d, systemd timery, at | `user` (text) |
| `crontab` | Crontaby všech uživatelů (crontab -l) | `user` (text)<br>`include_comments` (ano/ne, výchozí `false`) |

## Síť

| Funkce | Co dělá | Parametry |
|---|---|---|
| `network` | Síť: naslouchající porty, spojení, rozhraní, routy, firewall, DNS | `view` (listening\|connections\|interfaces\|routes\|firewall\|dns, výchozí `listening`) |

## Balíčky a programy

| Funkce | Co dělá | Parametry |
|---|---|---|
| `installed_packages` | Nainstalované balíčky a verze (dpkg/rpm/apk/pacman) | `filter` (text)<br>`limit` (číslo, výchozí `200`) |
| `package_owner` | Ke kterému balíčku soubor patří (+ ověření změn proti balíčku) | `path` (text) **povinný**<br>`verify` (ano/ne, výchozí `false`) |
| `which` | Kde je program nainstalovaný (which / command -v) | `command` (text) **povinný** |

## Kontejnery

| Funkce | Co dělá | Parametry |
|---|---|---|
| `docker` | Docker/Podman: kontejnery, image, logy, inspect | `view` (containers\|images\|logs\|inspect, výchozí `containers`)<br>`container` (text)<br>`lines` (číslo, výchozí `100`) |

## Příklad: co se skutečně spustí

Volání `grep(pattern: "Failed password", path: "/var/log/auth.log", mode: "fixed")` se na serveru provede jako:

```sh
grep -n -H -I -r -F -e 'Failed password' -- '/var/log/auth.log' | awk ${AWK_LINEWISE-} -v m=150 'NR<=m{print; fflush()} END{if(NR>m) printf "... [%d more lines not shown]\n", NR-m}'
```

Přesný řetězec odeslaný přes SSH (obálka nastaví prostředí, pracovní adresář a použije bash kvůli `pipefail`, jinak POSIX `sh`):

```sh
sh -c 'if command -v bash >/dev/null 2>&1; then exec bash -c "$1"; else eval "$1"; fi' sh 'export LC_ALL=C LANG=C PAGER=cat SYSTEMD_PAGER= SYSTEMD_COLORS=0 NO_COLOR=1 TERM=dumb
(set -o pipefail) 2>/dev/null && set -o pipefail
case $(awk -W version </dev/null 2>/dev/null) in *mawk*) AWK_LINEWISE='\''-W interactive'\'' ;; esac
grep -n -H -I -r -F -e '\''Failed password'\'' -- '\''/var/log/auth.log'\'' | awk ${AWK_LINEWISE-} -v m=150 '\''NR<=m{print; fflush()} END{if(NR>m) printf "... [%d more lines not shown]\n", NR-m}'\'''
```

Obojí vidíte v aplikaci u každého volání (karta funkce → ikona „rozbalit“).
