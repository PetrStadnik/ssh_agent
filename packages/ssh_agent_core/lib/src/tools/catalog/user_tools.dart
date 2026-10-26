import 'common.dart';

String _user(ToolArgs a, [String name = 'user']) =>
    a.ident(name, userNamePattern, 'expected a Linux user name');

const _keysFunction = r'''list_keys() {
  if [ -f "$1" ]; then
    echo "# $1"
    ls -l -- "$1"
    if command -v ssh-keygen >/dev/null 2>&1; then ssh-keygen -l -f "$1" 2>&1
    else grep -v -E '^[[:space:]]*(#|$)' "$1" | awk '{print $1, $NF}'; fi
  fi
}''';

final List<ToolDefinition> userTools = [
  ToolDefinition(
    name: 'permissions',
    category: ToolCategory.users,
    summary: 'Oprávnění cesty: vlastník, režim, každý adresář na cestě, ACL',
    description:
        'Explain who can access a path: owner/group/mode of the path and of '
        'every parent directory (`namei -l`), POSIX ACLs (`getfacl`) and '
        'special attributes (`lsattr`).',
    params: [ToolParam.string('path', 'Path (no wildcards).', required: true)],
    script: (a) => fill(
      r'''ls -ld -- @P@ || exit 1
echo '--- every component of the path ---'
if command -v namei >/dev/null 2>&1; then
  namei -l -- @P@
else
  p=$(readlink -f -- @P@)
  while [ -n "$p" ]; do ls -ld -- "$p"; [ "$p" = / ] && break; p=$(dirname -- "$p"); done
fi
if command -v getfacl >/dev/null 2>&1; then echo '--- ACL ---'; getfacl -p -- @P@ 2>&1; fi
if command -v lsattr >/dev/null 2>&1; then echo '--- attributes ---'; lsattr -d -- @P@ 2>&1; fi
true''',
      {'P': a.path('path', allowGlob: false)},
    ),
  ),
  ToolDefinition(
    name: 'check_access',
    category: ToolCategory.users,
    summary: 'Může uživatel X číst / zapisovat / spouštět cestu Y?',
    description:
        'Test whether a given user can read, write and execute/enter a path '
        '(runs `test -r/-w/-x` as that user via su/sudo; needs root or '
        'passwordless sudo, otherwise analyse the printed permissions). '
        'Nothing is written.',
    params: [
      ToolParam.string('user', 'User name.', required: true),
      ToolParam.string('path', 'Path (no wildcards).', required: true),
    ],
    script: (a) {
      final u = _user(a);
      final p = a.path('path', allowGlob: false);
      final buf = StringBuffer(
        fill(
          r'''id @U@ || exit 1
[ -e @P@ ] || echo 'Note: the path does not exist or is not visible to the current user.'
echo '--- path components ---'
if command -v namei >/dev/null 2>&1; then namei -l -- @P@; else ls -ld -- @P@; fi
echo '--- effective access of the user ---'
''',
          {'U': u, 'P': p},
        ),
      );
      const labels = {'r': 'read', 'w': 'write', 'x': 'execute/enter'};
      for (final mode in labels.keys) {
        final inner = shQuote('test -$mode $p');
        buf.writeln(
          fill(
            r'''if [ "$(id -u)" = 0 ]; then su -s /bin/sh @U@ -c @INNER@ 2>/dev/null; rc=$?
elif command -v sudo >/dev/null 2>&1 && sudo -n -u @U@ true 2>/dev/null; then sudo -n -u @U@ test -@M@ @P@ 2>/dev/null; rc=$?
else rc=x; fi
case $rc in 0) echo '@L@: yes';; x) echo '@L@: unknown (needs root or passwordless sudo)';; *) echo '@L@: no';; esac''',
            {'U': u, 'INNER': inner, 'M': mode, 'P': p, 'L': labels[mode]!},
          ),
        );
      }
      buf.write('true');
      return buf.toString();
    },
  ),
  ToolDefinition(
    name: 'list_users',
    category: ToolCategory.users,
    summary:
        'Všichni uživatelé a jejich vlastnosti: jméno, e-mail, heslo, '
        'přihlášení heslem (i přes SSH), klíče, skupiny',
    description:
        'List all user accounts with their properties: full name and contact '
        '(GECOS), e-mail (Linux has no standard e-mail field - it is looked '
        'up in GECOS, /etc/aliases, ~/.forward and ~/.gitconfig), uid/gid, '
        'shell, home, password status (set/locked/empty, hash type, last '
        'change, expiry - needs root for /etc/shadow), whether the user can '
        'log in with a password locally and over SSH (with the reason if '
        'not), number of SSH keys, groups and admin membership, last login. '
        'System accounts that cannot log in are only listed by name. For one '
        'user in depth use user_info.',
    params: [
      ToolParam.boolean(
        'only_login_users',
        'Only accounts with a real login shell (not nologin/false).',
        defaultValue: false,
      ),
      ToolParam.boolean(
        'include_system',
        'Show full details also for system accounts that cannot log in.',
        defaultValue: false,
      ),
      ToolParam.integer(
        'limit',
        'Maximum number of users shown in detail.',
        defaultValue: 100,
        min: 1,
        max: 2000,
      ),
    ],
    timeout: const Duration(seconds: 90),
    script: (a) => fill(_usersScript, {
      'ONLY': a.flag('only_login_users') ? '1' : '0',
      'SYS': a.flag('include_system') ? '1' : '0',
      'LIMIT': '${a.integer('limit')}',
    }),
  ),
  ToolDefinition(
    name: 'user_info',
    category: ToolCategory.users,
    summary: 'Detail uživatele: skupiny, domov, poslední přihlášení, sudo',
    description:
        'Everything about one user: id and groups, passwd entry, home '
        'directory and ~/.ssh permissions, password aging (`chage -l`, root), '
        'last login and sudo rights (root).',
    params: [ToolParam.string('user', 'User name.', required: true)],
    script: (a) => fill(
      r'''u=@U@
id "$u" || exit 1
getent passwd "$u" 2>/dev/null || grep "^$u:" /etc/passwd
printf 'groups: %s\n' "$(id -nG "$u")"
home=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
if [ -n "$home" ]; then
  echo '--- home directory ---'; ls -ld -- "$home" 2>&1
  if [ -d "$home/.ssh" ]; then echo '--- ~/.ssh ---'; ls -la -- "$home/.ssh" 2>&1; fi
fi
echo '--- password aging (chage -l, needs root) ---'
chage -l "$u" 2>&1
echo '--- last login ---'
if command -v lastlog2 >/dev/null 2>&1; then lastlog2 -u "$u" 2>&1
elif command -v lastlog >/dev/null 2>&1; then lastlog -u "$u" 2>&1
else last -n 3 "$u" 2>&1; fi
echo '--- sudo rights ---'
if ! command -v sudo >/dev/null 2>&1; then echo 'sudo is not installed'
elif [ "$(id -u)" = 0 ]; then sudo -n -l -U "$u" 2>&1
else echo '(listing sudo rights of another user requires root - use sudo_rights or switch_user root)'; fi
true''',
      {'U': _user(a)},
    ),
  ),
  ToolDefinition(
    name: 'list_groups',
    category: ToolCategory.users,
    summary: 'Skupiny a jejich členové',
    description:
        'List groups with members, or show one group including users that '
        'have it as their primary group.',
    params: [ToolParam.string('group', 'Show only this group.')],
    script: (a) {
      if (!a.has('group')) {
        return r'''(getent group 2>/dev/null || cat /etc/group) | awk -F: '{printf "%-24s gid=%-6s members=%s\n", $1, $3, $4}' '''
            .trimRight();
      }
      return fill(
        r'''g=@G@
getent group "$g" || { echo "Group $g not found" >&2; exit 1; }
gid=$(getent group "$g" | cut -d: -f3)
echo '--- users with this primary group ---'
getent passwd | awk -F: -v g="$gid" '$4==g {print $1}'
true''',
        {'G': a.ident('group', userNamePattern, 'expected a group name')},
      );
    },
  ),
  ToolDefinition(
    name: 'sudo_rights',
    category: ToolCategory.users,
    summary: 'Sudo oprávnění, členové admin skupin, pravidla sudoers',
    description:
        'Show sudo privileges (`sudo -l`) of the current user or of a given '
        'user (needs root), members of sudo/wheel/admin groups and the '
        'sudoers rules.',
    params: [ToolParam.string('user', 'User to check (default: current).')],
    script: (a) {
      final check = a.has('user')
          ? fill(
              r'''if [ "$(id -u)" = 0 ]; then sudo -n -l -U @U@ 2>&1; else echo 'Listing sudo rights of another user requires root.'; fi''',
              {'U': _user(a)},
            )
          : 'sudo -n -l 2>&1';
      return fill(
        r'''if command -v sudo >/dev/null 2>&1; then
@CHECK@
else echo 'sudo is not installed'; fi
echo '--- members of admin groups ---'
getent group sudo wheel admin 2>/dev/null
echo '--- sudoers rules ---'
for f in /etc/sudoers /etc/sudoers.d/*; do
  [ -f "$f" ] || continue
  if [ -r "$f" ]; then echo "# $f"; grep -v -E '^[[:space:]]*(#|$)' "$f"; else echo "# $f (not readable - needs root)"; fi
done
true''',
        {'CHECK': check},
      );
    },
  ),
  ToolDefinition(
    name: 'ssh_access',
    category: ToolCategory.users,
    summary: 'SSH přístup: authorized_keys uživatelů a nastavení sshd',
    description:
        'Show which SSH keys may log in (authorized_keys with fingerprints) '
        'for one user or all users, and the important sshd settings '
        '(PermitRootLogin, PasswordAuthentication, AllowUsers...).',
    params: [ToolParam.string('user', 'Only this user (default: all users).')],
    script: (a) {
      final keys = a.has('user')
          ? fill(
              r'''home=$(getent passwd @U@ | cut -d: -f6) || exit 1
list_keys "$home/.ssh/authorized_keys"
list_keys "$home/.ssh/authorized_keys2"''',
              {'U': _user(a)},
            )
          : r'''getent passwd | while IFS=: read -r name _ _ _ _ home _; do
  for f in "$home/.ssh/authorized_keys" "$home/.ssh/authorized_keys2"; do
    if [ -f "$f" ]; then echo "== user $name"; list_keys "$f"; fi
  done
done''';
      return fill(
        r'''@FN@
echo '=== authorized keys ==='
@KEYS@
echo '=== sshd settings ==='
sshd_bin=$(command -v sshd || echo /usr/sbin/sshd)
if "$sshd_bin" -T >/dev/null 2>&1; then
  "$sshd_bin" -T 2>/dev/null | grep -i -E '^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|authorizedkeysfile|allowusers|allowgroups|denyusers|denygroups|permitemptypasswords|maxauthtries|usepam) '
else
  grep -H -i -E '^[[:space:]]*(Port|ListenAddress|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|KbdInteractiveAuthentication|AuthorizedKeysFile|AllowUsers|AllowGroups|DenyUsers|DenyGroups|PermitEmptyPasswords|MaxAuthTries|Match|Include)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
fi
true''',
        {'FN': _keysFunction, 'KEYS': keys},
      );
    },
  ),
  ToolDefinition(
    name: 'shell_history',
    category: ToolCategory.users,
    summary: 'Historie příkazů uživatele (bash, zsh, fish, mysql...)',
    description:
        'Show the end of shell history files (.bash_history, .zsh_history, '
        'fish, mysql, psql, python) of the current or a given user.',
    params: [
      ToolParam.string('user', 'User (default: current user).'),
      ToolParam.integer(
        'lines',
        'Lines per history file.',
        defaultValue: 50,
        min: 1,
        max: 2000,
      ),
    ],
    script: (a) => fill(
      r'''home=@HOME@
[ -n "$home" ] || { echo 'Unknown user' >&2; exit 1; }
found=0
for f in "$home/.bash_history" "$home/.zsh_history" "$home/.local/share/fish/fish_history" "$home/.ash_history" "$home/.sh_history" "$home/.history" "$home/.mysql_history" "$home/.psql_history" "$home/.python_history"; do
  if [ -f "$f" ]; then
    found=1
    echo "=== $f ($(wc -l < "$f" 2>/dev/null | tr -d ' ') lines, modified $(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)) ==="
    tail -n @N@ -- "$f" 2>&1
  fi
done
[ "$found" = 1 ] || echo "No shell history files found in $home"
true''',
      {
        'HOME': a.has('user')
            ? '\$(getent passwd ${_user(a)} | cut -d: -f6)'
            : r'"$HOME"',
        'N': '${a.integer('lines')}',
      },
    ),
  ),
];

/// Script of `list_users`: one block per account. Everything is read-only;
/// without root the password state and other users' files may be unknown.
const _usersScript = r'''root=0; [ "$(id -u)" = 0 ] && root=1
uid_min=$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null)
case $uid_min in ''|*[!0-9]*) uid_min=1000 ;; esac
today=$(( $(date +%s) / 86400 ))
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# shadow line -> "usable|description" (usable: 1 yes, 2 empty password, 0 no)
pwinfo() {
  printf '%s\n' "$1" | awk -F: -v t="$today" '
function ymd(d,  z, era, doe, yoe, y, doy, mp, dy, m) {
  z = d + 719468; era = int(z / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153); dy = doy - int((153 * mp + 2) / 5) + 1
  m = mp < 10 ? mp + 3 : mp - 9
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02d", y, m, dy)
}
{
  h = $2; u = 1
  if (h == "") { u = 2; s = "EMPTY (no password needed)" }
  else if (h ~ /^[!*]/) { u = 0; s = (h ~ /^[!*]+$/) ? "not set" : "locked" }
  else {
    a = "DES (weak)"
    if (h ~ /^\$y\$/) a = "yescrypt"; else if (h ~ /^\$gy\$/) a = "gost-yescrypt"
    else if (h ~ /^\$6\$/) a = "SHA-512"; else if (h ~ /^\$5\$/) a = "SHA-256"
    else if (h ~ /^\$2[aby]?\$/) a = "bcrypt"; else if (h ~ /^\$1\$/) a = "MD5 (weak)"
    s = "set, " a
  }
  if ($3 == "0") s = s ", must be changed at next login"
  else if ($3 != "") s = s ", changed " ymd($3)
  if ($3 != "" && $5 != "" && $5 + 0 < 10000) { e = $3 + $5; s = s (e < t ? ", password EXPIRED " : ", password expires ") ymd(e) }
  if ($8 != "") {
    if ($8 + 0 <= t) { s = s ", ACCOUNT EXPIRED " ymd($8); u = 0 }
    else s = s ", account expires " ymd($8)
  }
  print u "|" s
}'
}
val() { printf '%s\n' "$2" | awk -v k="$1" '$1 == k {print $2; exit}'; }
all() { printf '%s\n' "$2" | awk -v k="$1" '$1 == k {for (i = 2; i <= NF; i++) print $i}'; }
match_any() { n=$1; shift; for p in "$@"; do p=${p%%@*}; case $n in $p) return 0 ;; esac; done; return 1; }
sshd_bin=$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)
exact=0
if [ "$root" = 1 ] && cfg=$("$sshd_bin" -T 2>/dev/null </dev/null) && [ -n "$cfg" ]; then exact=1
else
  cfg=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk 'tolower($1) == "match" {m = 1} !m && $1 !~ /^#/ && NF > 1 {k = tolower($1); if (k ~ /^(allow|deny)(users|groups)$/ || !(k in seen)) {seen[k] = 1; $1 = k; print}}')
fi
settings() {
  printf '%s\n' "$1" | awk '{v[tolower($1)] = tolower($2)} END {
    print (v["passwordauthentication"] ? v["passwordauthentication"] : "yes"), (v["kbdinteractiveauthentication"] ? v["kbdinteractiveauthentication"] : (v["challengeresponseauthentication"] ? v["challengeresponseauthentication"] : "yes")), (v["usepam"] ? v["usepam"] : "no"), (v["permitrootlogin"] ? v["permitrootlogin"] : "prohibit-password"), (v["permitemptypasswords"] ? v["permitemptypasswords"] : "no"), (v["pubkeyauthentication"] ? v["pubkeyauthentication"] : "yes")
  }'
}
read -r g_pw g_kbd g_pam g_prl g_empty g_pub <<EOF
$(settings "$cfg")
EOF
if [ "$exact" = 1 ]; then src='sshd -T'; else src='config files, approximate - exact values need root'; fi
echo "SSH server ($src): PasswordAuthentication=$g_pw KbdInteractiveAuthentication=$g_kbd UsePAM=$g_pam PermitRootLogin=$g_prl PermitEmptyPasswords=$g_empty PubkeyAuthentication=$g_pub"
lists=$(printf '%s\n' "$cfg" | awk '$1 ~ /^(allow|deny)(users|groups)$/')
[ -n "$lists" ] && printf '%s\n' "$lists" | sed 's/^/  /'
[ "$root" = 1 ] || echo "Not root: password status (/etc/shadow) and files of other users may be unknown - switch_user root for the full picture."
echo "E-mail is not a standard account field: it is looked up in GECOS, /etc/aliases, ~/.forward and ~/.gitconfig."
aliases=$(grep -v -E '^[[:space:]]*(#|$)' /etc/aliases 2>/dev/null)
ll_cmd=''
if command -v lastlog >/dev/null 2>&1; then ll_cmd=lastlog; elif command -v lastlog2 >/dev/null 2>&1; then ll_cmd=lastlog2; fi
echo
(getent passwd 2>/dev/null || cat /etc/passwd) | awk -F: '!seen[$1]++' | {
shown=0; skipped=0; hidden_sys=''; hidden_user=''
while IFS=: read -r u pw uid gid gecos home shell; do
  case $shell in ''|*nologin|*false|*sync|*shutdown|*halt) shell_ok=0 ;; *) shell_ok=1 ;; esac
  sl=''
  [ "$root" = 1 ] && sl=$(getent shadow "$u" 2>/dev/null </dev/null | head -n 1)
  [ -z "$sl" ] && [ "$pw" != x ] && sl="$u:$pw:::::::"
  if [ -n "$sl" ]; then info=$(pwinfo "$sl"); usable=${info%%|*}; pwtext=${info#*|}
  else usable=unknown; pwtext='unknown (needs root to read /etc/shadow)'; fi
  if [ @SYS@ = 0 ] && [ "$uid" != 0 ] && [ "$shell_ok" = 0 ] && [ "$usable" != 1 ] && [ "$usable" != 2 ]; then
    if [ "$uid" -lt "$uid_min" ]; then hidden_sys="$hidden_sys $u"; else hidden_user="$hidden_user $u"; fi
    continue
  fi
  if [ @ONLY@ = 1 ] && [ "$shell_ok" = 0 ]; then hidden_user="$hidden_user $u"; continue; fi
  shown=$((shown + 1))
  if [ "$shown" -gt @LIMIT@ ]; then skipped=$((skipped + 1)); continue; fi
  name=${gecos%%,*}
  contact=$(printf '%s\n' "$gecos" | awk -F, '{for (i = 2; i <= NF; i++) if ($i != "" && $i !~ /@/) printf "%s; ", $i}')
  emails=$(printf '%s\n' "$gecos" | awk -F, '{for (i = 1; i <= NF; i++) if ($i ~ /@/) printf "%s (GECOS); ", $i}')
  al=$(printf '%s\n' "$aliases" | awk -F: -v u="$u" '$1 == u {sub(/^[ \t]+/, "", $2); print $2; exit}')
  [ -n "$al" ] && emails="$emails$al (/etc/aliases); "
  if [ -n "$home" ] && [ "$home" != / ]; then
    if [ -r "$home/.forward" ]; then fw=$(head -n 1 "$home/.forward" 2>/dev/null); [ -n "$fw" ] && emails="$emails$fw (~/.forward); "; fi
    for gc in "$home/.gitconfig" "$home/.config/git/config"; do
      if [ -r "$gc" ]; then
        ge=$(awk '/^[ \t]*\[/ {s = tolower($0)} s ~ /^[ \t]*\[user\]/ && tolower($1) ~ /^email/ {sub(/^[^=]*=[ \t]*/, ""); print; exit}' "$gc" 2>/dev/null)
        [ -n "$ge" ] && emails="$emails$ge (~/${gc#"$home"/}); "
      fi
    done
  fi
  keys=0
  if [ -n "$home" ] && [ -d "$home" ] && [ ! -x "$home" ]; then keys='? (home not accessible)'
  else
    for f in "$home/.ssh/authorized_keys" "$home/.ssh/authorized_keys2"; do
      if [ -f "$f" ]; then
        if [ -r "$f" ]; then n=$(grep -c -v -E '^[[:space:]]*(#|$)' "$f" 2>/dev/null); case $keys in \?*) ;; *) keys=$((keys + ${n:-0})) ;; esac
        else keys='? (not readable)'; fi
      elif [ -d "$home/.ssh" ] && [ ! -x "$home/.ssh" ]; then keys='? (not readable)'
      fi
    done
  fi
  groups=$(id -nG "$u" 2>/dev/null </dev/null)
  admin=''
  case " $groups " in *" sudo "*|*" wheel "*|*" admin "*) admin='  [admin group]' ;; esac
  [ "$uid" = 0 ] && admin='  [UID 0 = superuser]'
  ll=''
  [ -n "$ll_cmd" ] && ll=$("$ll_cmd" -u "$u" 2>/dev/null </dev/null | awk 'NR == 2 {$1 = ""; sub(/^ +/, ""); print}')
  case $ll in *'Never logged in'*|*'never logged in'*) ll=never ;; esac
  ucfg=$cfg
  if [ "$exact" = 1 ] && [ "$shell_ok" = 1 ]; then
    c=$("$sshd_bin" -T -C "user=$u,host=localhost,addr=127.0.0.1" 2>/dev/null </dev/null) && [ -n "$c" ] && ucfg=$c
  fi
  read -r s_pw s_kbd s_pam s_prl s_empty s_pub <<EOF
$(settings "$ucfg")
EOF
  block=''
  if [ -n "$lists" ]; then
    set -f
    d_users=$(all denyusers "$ucfg"); a_users=$(all allowusers "$ucfg"); d_groups=$(all denygroups "$ucfg"); a_groups=$(all allowgroups "$ucfg")
    if [ -n "$d_users" ] && match_any "$u" $d_users; then block='DenyUsers'
    elif [ -n "$a_users" ] && ! match_any "$u" $a_users; then block='not in AllowUsers'
    else
      if [ -n "$d_groups" ]; then for g in $groups; do match_any "$g" $d_groups && block='DenyGroups'; done; fi
      if [ -z "$block" ] && [ -n "$a_groups" ]; then
        okg=0; for g in $groups; do match_any "$g" $a_groups && okg=1; done
        [ "$okg" = 1 ] || block='not in AllowGroups'
      fi
    fi
    set +f
  fi
  if [ "$shell_ok" = 0 ]; then local_l="no (shell $shell)"
  else
    case $usable in
      1) local_l=yes ;; 2) local_l='yes, WITHOUT any password' ;;
      0) local_l='no (no usable password)' ;; *) local_l='unknown (needs root)' ;;
    esac
  fi
  via=''
  [ "$s_pw" = yes ] || via=' via keyboard-interactive/PAM'
  if [ "$shell_ok" = 0 ]; then ssh_l='no (no login shell)'
  elif [ -n "$block" ]; then ssh_l="no ($block)"
  elif [ "$s_pw" != yes ] && { [ "$s_kbd" != yes ] || [ "$s_pam" != yes ]; }; then ssh_l='no (PasswordAuthentication no)'
  elif [ "$uid" = 0 ] && [ "$s_prl" != yes ]; then ssh_l="no (PermitRootLogin $s_prl)"
  else
    case $usable in
      1) ssh_l="yes$via" ;;
      2) if [ "$s_empty" = yes ]; then ssh_l='yes, WITHOUT any password'; else ssh_l='no (empty password, PermitEmptyPasswords no)'; fi ;;
      0) ssh_l='no (no usable password)' ;; *) ssh_l='unknown (password status needs root)' ;;
    esac
  fi
  key_l=''
  case $keys in 0|\?*) ;; *)
    if [ "$shell_ok" = 1 ] && [ -z "$block" ] && [ "$s_pub" = yes ] && { [ "$uid" != 0 ] || [ "$s_prl" != no ]; }; then key_l=' (key login allowed)'; fi ;;
  esac
  echo "$u  uid=$uid gid=$gid$admin"
  contact=${contact%; }; emails=${emails%; }
  [ -n "$name$contact" ] && echo "  name: ${name:--}${contact:+; contact: $contact}"
  echo "  e-mail: ${emails:-none found}"
  if [ -n "$home" ] && [ ! -d "$home" ]; then hm="$home (missing)"; else hm=$home; fi
  echo "  shell: $shell; home: $hm"
  echo "  password: $pwtext"
  echo "  password login: local $local_l; SSH $ssh_l"
  echo "  ssh keys: $keys$key_l; groups: ${groups:-?}; last login: ${ll:-unknown}"
done
[ -n "$hidden_user" ] && echo "Other accounts without a login shell:$hidden_user"
[ -n "$hidden_sys" ] && echo "System accounts that cannot log in:$hidden_sys"
[ "$skipped" -gt 0 ] && echo "... $skipped more users not shown (limit)"
true
}''';
