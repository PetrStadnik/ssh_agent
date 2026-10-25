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
    script: (a) => fill(r'''ls -ld -- @P@ || exit 1
echo '--- every component of the path ---'
if command -v namei >/dev/null 2>&1; then
  namei -l -- @P@
else
  p=$(readlink -f -- @P@)
  while [ -n "$p" ]; do ls -ld -- "$p"; [ "$p" = / ] && break; p=$(dirname -- "$p"); done
fi
if command -v getfacl >/dev/null 2>&1; then echo '--- ACL ---'; getfacl -p -- @P@ 2>&1; fi
if command -v lsattr >/dev/null 2>&1; then echo '--- attributes ---'; lsattr -d -- @P@ 2>&1; fi
true''', {'P': a.path('path', allowGlob: false)}),
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
      final buf = StringBuffer(fill(r'''id @U@ || exit 1
[ -e @P@ ] || echo 'Note: the path does not exist or is not visible to the current user.'
echo '--- path components ---'
if command -v namei >/dev/null 2>&1; then namei -l -- @P@; else ls -ld -- @P@; fi
echo '--- effective access of the user ---'
''', {'U': u, 'P': p}));
      const labels = {'r': 'read', 'w': 'write', 'x': 'execute/enter'};
      for (final mode in labels.keys) {
        final inner = shQuote('test -$mode $p');
        buf.writeln(fill(r'''if [ "$(id -u)" = 0 ]; then su -s /bin/sh @U@ -c @INNER@ 2>/dev/null; rc=$?
elif command -v sudo >/dev/null 2>&1 && sudo -n -u @U@ true 2>/dev/null; then sudo -n -u @U@ test -@M@ @P@ 2>/dev/null; rc=$?
else rc=x; fi
case $rc in 0) echo '@L@: yes';; x) echo '@L@: unknown (needs root or passwordless sudo)';; *) echo '@L@: no';; esac''',
            {'U': u, 'INNER': inner, 'M': mode, 'P': p, 'L': labels[mode]!}));
      }
      buf.write('true');
      return buf.toString();
    },
  ),
  ToolDefinition(
    name: 'list_users',
    category: ToolCategory.users,
    summary: 'Seznam uživatelů (UID, domovský adresář, shell)',
    description:
        'List user accounts with uid, gid, home directory and login shell '
        '(from `getent passwd`).',
    params: [
      ToolParam.boolean('only_login_users',
          'Only accounts with a real login shell (not nologin/false).',
          defaultValue: false),
    ],
    script: (a) {
      final filter = a.flag('only_login_users')
          ? r'$7 !~ /(nologin|false|sync|shutdown|halt)$/'
          : '';
      return fill(r'''(getent passwd 2>/dev/null || cat /etc/passwd) | awk -F: '@FILTER@ {printf "%-24s uid=%-6s gid=%-6s home=%-30s shell=%s\n", $1, $3, $4, $6, $7}' ''',
          {'FILTER': filter}).trimRight();
    },
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
    script: (a) => fill(r'''u=@U@
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
true''', {'U': _user(a)}),
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
        return r'''(getent group 2>/dev/null || cat /etc/group) | awk -F: '{printf "%-24s gid=%-6s members=%s\n", $1, $3, $4}' ''' .trimRight();
      }
      return fill(r'''g=@G@
getent group "$g" || { echo "Group $g not found" >&2; exit 1; }
gid=$(getent group "$g" | cut -d: -f3)
echo '--- users with this primary group ---'
getent passwd | awk -F: -v g="$gid" '$4==g {print $1}'
true''', {'G': a.ident('group', userNamePattern, 'expected a group name')});
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
          ? fill(r'''if [ "$(id -u)" = 0 ]; then sudo -n -l -U @U@ 2>&1; else echo 'Listing sudo rights of another user requires root.'; fi''',
              {'U': _user(a)})
          : 'sudo -n -l 2>&1';
      return fill(r'''if command -v sudo >/dev/null 2>&1; then
@CHECK@
else echo 'sudo is not installed'; fi
echo '--- members of admin groups ---'
getent group sudo wheel admin 2>/dev/null
echo '--- sudoers rules ---'
for f in /etc/sudoers /etc/sudoers.d/*; do
  [ -f "$f" ] || continue
  if [ -r "$f" ]; then echo "# $f"; grep -v -E '^[[:space:]]*(#|$)' "$f"; else echo "# $f (not readable - needs root)"; fi
done
true''', {'CHECK': check});
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
          ? fill(r'''home=$(getent passwd @U@ | cut -d: -f6) || exit 1
list_keys "$home/.ssh/authorized_keys"
list_keys "$home/.ssh/authorized_keys2"''', {'U': _user(a)})
          : r'''getent passwd | while IFS=: read -r name _ _ _ _ home _; do
  for f in "$home/.ssh/authorized_keys" "$home/.ssh/authorized_keys2"; do
    if [ -f "$f" ]; then echo "== user $name"; list_keys "$f"; fi
  done
done''';
      return fill(r'''@FN@
echo '=== authorized keys ==='
@KEYS@
echo '=== sshd settings ==='
sshd_bin=$(command -v sshd || echo /usr/sbin/sshd)
if "$sshd_bin" -T >/dev/null 2>&1; then
  "$sshd_bin" -T 2>/dev/null | grep -i -E '^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|authorizedkeysfile|allowusers|allowgroups|denyusers|denygroups|permitemptypasswords|maxauthtries|usepam) '
else
  grep -H -i -E '^[[:space:]]*(Port|ListenAddress|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|KbdInteractiveAuthentication|AuthorizedKeysFile|AllowUsers|AllowGroups|DenyUsers|DenyGroups|PermitEmptyPasswords|MaxAuthTries|Match|Include)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
fi
true''', {'FN': _keysFunction, 'KEYS': keys});
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
      ToolParam.integer('lines', 'Lines per history file.',
          defaultValue: 50, min: 1, max: 2000),
    ],
    script: (a) => fill(r'''home=@HOME@
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
true''', {
      'HOME': a.has('user')
          ? '\$(getent passwd ${_user(a)} | cut -d: -f6)'
          : r'"$HOME"',
      'N': '${a.integer('lines')}',
    }),
  ),
];
