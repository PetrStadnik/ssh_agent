import 'common.dart';

String _user(ToolArgs a, [String name = 'user']) =>
    a.ident(name, userNamePattern, 'expected a Linux user name');

String _since(ToolArgs a, String name) => a.ident(name, timeExpressionPattern,
    'use e.g. "2026-10-01", "2026-10-01 12:00", "yesterday", "-2h" or "today"');

const _authFailurePattern =
    'Failed password|Failed publickey|Invalid user|authentication failure|'
    'maximum authentication attempts|Connection closed by authenticating user';

final List<ToolDefinition> loginTools = [
  ToolDefinition(
    name: 'logged_in_users',
    category: ToolCategory.logins,
    summary: 'Kdo je právě přihlášený (w / who)',
    description:
        'Show who is logged in right now, from where and what they run '
        '(`w`, `who`), plus the last boot time.',
    script: (_) => r'''if command -v w >/dev/null 2>&1; then w; else who -a; fi
echo
echo '--- last boot ---'
who -b 2>/dev/null || uptime -s 2>/dev/null
true''',
  ),
  ToolDefinition(
    name: 'last',
    category: ToolCategory.logins,
    summary: 'Historie přihlášení (last) - kdo, odkud, kdy',
    description:
        'Login history from wtmp (`last`): user, terminal, source IP, login '
        'and logout time; also reboots. Optionally for one user and/or since '
        'a date.',
    params: [
      ToolParam.string('user', 'Only this user.'),
      ToolParam.integer('limit', 'Maximum number of entries.',
          defaultValue: 50, min: 1, max: 2000),
      ToolParam.string('since',
          'Only logins since this time, e.g. "2026-10-01" or "-7days" or "yesterday".'),
    ],
    script: (a) {
      final n = a.integer('limit');
      final user = a.has('user') ? ' ${_user(a)}' : '';
      final since = a.has('since') ? ' --since ${_since(a, 'since')}' : '';
      return fill(r'''command -v last >/dev/null 2>&1 || { echo 'The last command is not available on this server.' >&2; exit 127; }
if last -F -w -i -n 1 >/dev/null 2>&1; then
  last -F -w -i -n @N@@SINCE@@USER@
else
  last -n @N@@USER@
fi''', {'N': '$n', 'SINCE': since, 'USER': user});
    },
  ),
  ToolDefinition(
    name: 'lastb',
    category: ToolCategory.logins,
    summary: 'Neúspěšné pokusy o přihlášení (lastb + log sshd)',
    description:
        'Failed login attempts: `lastb` (btmp, needs root) and failed SSH '
        'authentications from the journal or /var/log/auth.log|secure.',
    params: [
      ToolParam.integer('limit', 'Maximum number of entries per source.',
          defaultValue: 50, min: 1, max: 2000),
      ToolParam.string('since', 'Only since this time, e.g. "2026-10-01" or "-1d".'),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) {
      final since = a.has('since') ? ' --since ${_since(a, 'since')}' : '';
      return fill(r'''echo '=== lastb (needs root) ==='
if ! command -v lastb >/dev/null 2>&1; then echo 'lastb is not available'
elif lastb -F -w -i -n 1 >/dev/null 2>&1; then lastb -F -w -i -n @N@
else lastb -n @N@ 2>&1; fi
echo '=== failed SSH authentications (system log) ==='
pat=@PAT@
out=''
if command -v journalctl >/dev/null 2>&1; then
  out=$(journalctl --no-pager -o short-iso@SINCE@ _COMM=sshd _COMM=sshd-session 2>/dev/null | grep -E "$pat" | tail -n @N@)
fi
if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  grep -h -E "$pat" /var/log/auth.log /var/log/secure 2>/dev/null | tail -n @N@
fi
true''', {
        'N': '${a.integer('limit')}',
        'PAT': shQuote(_authFailurePattern),
        'SINCE': since,
      });
    },
  ),
];

final List<ToolDefinition> processTools = [
  ToolDefinition(
    name: 'ps',
    category: ToolCategory.processes,
    summary: 'Běžící procesy (ps) s filtrem, řazením a stromem',
    description:
        'List running processes (`ps`): pid, parent, user, CPU, memory, start '
        'time and full command line. Filter by text and/or user, sort, or '
        'show as a tree.',
    params: [
      ToolParam.string('filter', 'Only processes whose line contains this text (case-insensitive).'),
      ToolParam.string('user', 'Only processes of this user.'),
      ToolParam.string('sort', 'Sort order.',
          enumValues: ['cpu', 'memory', 'pid', 'start'], defaultValue: 'cpu'),
      ToolParam.boolean('tree', 'Show parent/child tree.', defaultValue: false),
      ToolParam.integer('limit', 'Maximum number of processes.',
          defaultValue: 50, min: 1, max: 2000),
    ],
    script: (a) {
      final select = a.has('user') ? '-u ${_user(a)} -U ${_user(a)}' : '-e';
      final sortKey = const {
        'cpu': '-%cpu',
        'memory': '-%mem',
        'pid': 'pid',
        'start': 'start_time',
      }[a.str('sort')]!;
      final gnu = a.flag('tree')
          ? 'ps $select -ww -o pid,ppid,user,stat,lstart,args --forest'
          : 'ps $select -ww -o pid,ppid,user,%cpu,%mem,rss,stat,lstart,args --sort=$sortKey';
      // Our own wrapper processes (sh -c, sudo, su) contain the prelude
      // "SYSTEMD_COLORS=0" and are hidden, as are children of this shell.
      return fill(r'''@FILTER@
if ps -o pid= -p 1 --sort=pid >/dev/null 2>&1; then
  @GNU@
else
  ps aux 2>/dev/null || ps
fi | awk -v me="$$" 'NR==1 {print; next} $1==me || $2==me {next} index($0, "SYSTEMD_COLORS=0") || index($0, "PS_FILTER") || index($0, "-ww -o pid,ppid,user") {next} ENVIRON["PS_FILTER"]=="" || index(tolower($0), tolower(ENVIRON["PS_FILTER"])) {print}' @LIMIT@''',
          {
            'FILTER': exportVar('PS_FILTER', a.strOrNull('filter')),
            'GNU': gnu,
            'LIMIT': limit(a.integer('limit') + 1),
          });
    },
  ),
  ToolDefinition(
    name: 'process_details',
    category: ToolCategory.processes,
    summary: 'Detail procesu: binárka, pracovní adresář, otevřené soubory, sockety',
    description:
        'Details of one process: owner, start time, executable, working '
        'directory, full command line, status, cgroup/systemd unit, open '
        'file descriptors and network sockets. Good for "where does this '
        'service store data".',
    params: [ToolParam.integer('pid', 'Process ID.', required: true, min: 1)],
    script: (a) => fill(r'''p=@PID@
[ -d /proc/$p ] || { echo "No process with PID $p" >&2; exit 1; }
ps -ww -o pid,ppid,user,group,stat,lstart,etime,%cpu,%mem,rss,args -p $p
echo '--- executable / working directory / root ---'
ls -l /proc/$p/exe /proc/$p/cwd /proc/$p/root 2>&1
echo '--- command line ---'
tr '\0' ' ' < /proc/$p/cmdline; echo
echo '--- status ---'
grep -E '^(Name|State|PPid|Uid|Gid|Groups|Threads|VmRSS|VmSize):' /proc/$p/status
echo '--- cgroup (systemd unit / container) ---'
cat /proc/$p/cgroup 2>/dev/null @LIM5@
echo '--- open file descriptors ---'
ls -l /proc/$p/fd 2>&1 @LIM80@
echo '--- network sockets ---'
if command -v ss >/dev/null 2>&1; then ss -tunap 2>/dev/null | grep "pid=$p,"; fi
true''', {
      'PID': '${a.integer('pid')}',
      'LIM5': limit(5),
      'LIM80': limit(80),
    }),
  ),
  ToolDefinition(
    name: 'open_files',
    category: ToolCategory.processes,
    summary: 'Otevřené soubory procesu nebo kdo drží otevřený soubor (lsof)',
    description:
        'List files opened by a process (pid) or the processes that have a '
        'file open (path), using `lsof` (falls back to /proc). Give pid or path.',
    params: [
      ToolParam.integer('pid', 'Process ID.', min: 1),
      ToolParam.string('path', 'File or socket path (no wildcards).'),
    ],
    exitCodeMeaning: const {1: 'Nothing found.'},
    script: (a) {
      if (a.has('pid')) {
        return fill(r'''if command -v lsof >/dev/null 2>&1; then lsof -nP -p @PID@ 2>&1 @LIM@
else ls -l /proc/@PID@/fd 2>&1 @LIM@; fi''',
            {'PID': '${a.integer('pid')}', 'LIM': limit(300)});
      }
      if (!a.has('path')) {
        throw ToolArgumentException('Provide either "pid" or "path".');
      }
      return fill(r'''if command -v lsof >/dev/null 2>&1; then lsof -nP -- @P@ 2>&1 @LIM@
elif command -v fuser >/dev/null 2>&1; then fuser -v -- @P@ 2>&1
else
  target=$(readlink -f -- @P@)
  for fd in /proc/[0-9]*/fd/*; do t=$(readlink "$fd" 2>/dev/null) && [ "$t" = "$target" ] && echo "$fd -> $t"; done
fi''', {'P': a.path('path', allowGlob: false), 'LIM': limit(300)});
    },
  ),
  ToolDefinition(
    name: 'resource_usage',
    category: ToolCategory.processes,
    summary: 'Zátěž: CPU, paměť, load, nejnáročnější procesy',
    description:
        'Show load average, memory and swap usage, CPU count and the top '
        'processes (`uptime`, `free -h`, `top -b -n 1`).',
    script: (_) => fill(r'''uptime
echo '--- memory ---'
free -h 2>/dev/null || grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
printf 'cpus: %s, load: %s\n' "$(nproc 2>/dev/null)" "$(cat /proc/loadavg)"
echo '--- top ---'
top -b -n 1 2>/dev/null @LIM@
true''', {'LIM': limit(30)}),
  ),
];

final List<ToolDefinition> serviceTools = [
  ToolDefinition(
    name: 'services',
    category: ToolCategory.services,
    summary: 'Seznam služeb (běžící / selhané / všechny / povolené)',
    description:
        'List system services (systemd units; OpenRC/SysV as fallback): '
        'running, failed, all or enabled at boot.',
    params: [
      ToolParam.string('state', 'Which services.',
          enumValues: ['running', 'failed', 'all', 'enabled'],
          defaultValue: 'running'),
    ],
    script: (a) {
      final systemd = switch (a.str('state')) {
        'running' =>
          'systemctl list-units --type=service --state=running --no-pager --no-legend --plain',
        'failed' => 'systemctl list-units --state=failed --no-pager --plain',
        'all' =>
          'systemctl list-units --type=service --all --no-pager --no-legend --plain',
        _ =>
          'systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend',
      };
      return fill(r'''if [ -d /run/systemd/system ]; then
  @SYSTEMD@ @LIM@
elif command -v rc-status >/dev/null 2>&1; then rc-status -a
else service --status-all 2>&1; fi''', {'SYSTEMD': systemd, 'LIM': limit(400)});
    },
  ),
  ToolDefinition(
    name: 'service_status',
    category: ToolCategory.services,
    summary: 'Stav služby, její konfigurace, spouštěný příkaz a poslední logy',
    description:
        'Status of one service (`systemctl status`): active state, main PID, '
        'recent log lines, unit file path, ExecStart, user and working '
        'directory; optionally the full unit file (`systemctl cat`).',
    params: [
      ToolParam.string('name', 'Service name, e.g. nginx or ssh.service.',
          required: true),
      ToolParam.boolean('show_unit_file', 'Also print the unit file.',
          defaultValue: false),
    ],
    exitCodeMeaning: const {
      3: 'The service is not running (inactive or failed).',
      4: 'No such service.',
    },
    script: (a) {
      final n = a.ident('name', unitNamePattern, 'expected a systemd unit name');
      final unitFile = a.flag('show_unit_file')
          ? '\necho "--- unit file ---"\nsystemctl cat --no-pager $n 2>&1'
          : '';
      return fill(r'''[ -d /run/systemd/system ] || { echo 'systemd is not running, using the service command'; service @N@ status 2>&1; exit $?; }
systemctl status --no-pager -l -n 25 @N@ 2>&1
rc=$?
echo '--- properties ---'
systemctl show --no-pager -p Id,Description,LoadState,ActiveState,SubState,UnitFileState,FragmentPath,DropInPaths,MainPID,ExecMainStartTimestamp,User,Group,WorkingDirectory,ExecStart @N@ 2>&1@UNIT@
exit $rc''', {'N': n, 'UNIT': unitFile});
    },
  ),
  ToolDefinition(
    name: 'journal',
    category: ToolCategory.services,
    summary: 'Systémový log (journalctl) podle služby, času, priority, textu',
    description:
        'Read system logs with `journalctl` (or /var/log/syslog|messages): '
        'filter by service unit, time range, priority, text, kernel '
        'messages or current boot.',
    params: [
      ToolParam.string('unit', 'Service unit, e.g. nginx or sshd.'),
      ToolParam.string('since', 'Start time, e.g. "2026-10-01 08:00", "yesterday", "-2h".'),
      ToolParam.string('until', 'End time, same format as since.'),
      ToolParam.string('priority', 'Show this priority and more severe.',
          enumValues: ['emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug']),
      ToolParam.string('grep', 'Only entries matching this extended regex (case-insensitive).'),
      ToolParam.boolean('kernel', 'Kernel messages only (like dmesg).',
          defaultValue: false),
      ToolParam.boolean('current_boot', 'Only the current boot.',
          defaultValue: false),
      ToolParam.integer('lines', 'Maximum number of entries (newest).',
          defaultValue: 100, min: 1, max: 3000),
    ],
    timeout: const Duration(seconds: 90),
    exitCodeMeaning: const {1: 'No matching log entries.'},
    script: (a) {
      final n = a.integer('lines');
      final opts = <String>['--no-pager', '-o short-iso'];
      if (a.has('unit')) {
        opts.add('-u ${a.ident('unit', unitNamePattern, 'expected a unit name')}');
      }
      if (a.flag('kernel')) opts.add('-k');
      if (a.flag('current_boot')) opts.add('-b');
      if (a.has('priority')) opts.add('-p ${a.str('priority')}');
      if (a.has('since')) opts.add('--since ${_since(a, 'since')}');
      if (a.has('until')) opts.add('--until ${_since(a, 'until')}');
      final grep = a.has('grep') ? a.quoted('grep') : null;
      final journal = grep == null
          ? 'journalctl ${opts.join(' ')} -n $n'
          : 'journalctl ${opts.join(' ')}${a.has('since') ? '' : ' -n 50000'} | grep -i -E -e $grep | tail -n $n';
      final fallback = grep == null
          ? 'tail -n $n "\$f"'
          : 'grep -i -E -e $grep "\$f" | tail -n $n';
      return fill(r'''if command -v journalctl >/dev/null 2>&1 && { [ -d /run/systemd/system ] || [ -d /var/log/journal ]; }; then
  @JOURNAL@
else
  if [ "@KERNEL@" = 1 ]; then dmesg -T 2>&1 | tail -n @N@; exit; fi
  f=/var/log/syslog; [ -f "$f" ] || f=/var/log/messages
  echo "(journalctl not available, reading $f)"
  @FALLBACK@
fi''', {
        'JOURNAL': journal,
        'FALLBACK': fallback,
        'KERNEL': a.flag('kernel') ? '1' : '0',
        'N': '$n',
      });
    },
  ),
  ToolDefinition(
    name: 'cron_jobs',
    category: ToolCategory.services,
    summary: 'Naplánované úlohy: crontab, cron.d, systemd timery, at',
    description:
        'Show scheduled jobs: /etc/crontab, /etc/cron.d, cron.daily etc., '
        'user crontabs (`crontab -l`), systemd timers and at jobs.',
    params: [ToolParam.string('user', 'Only the crontab of this user (needs root for others).')],
    script: (a) {
      final userCron = a.has('user')
          ? 'crontab -l -u ${_user(a)} 2>&1'
          : r'''crontab -l 2>&1
if [ "$(id -u)" = 0 ]; then
  for f in /var/spool/cron/crontabs/* /var/spool/cron/*; do
    [ -f "$f" ] && { echo "# $f"; grep -v -E '^[[:space:]]*(#|$)' "$f"; }
  done
fi''';
      return fill(r'''echo '=== /etc/crontab ==='
grep -v -E '^[[:space:]]*(#|$)' /etc/crontab 2>&1
echo '=== /etc/cron.d ==='
for f in /etc/cron.d/*; do [ -f "$f" ] && { echo "# $f"; grep -v -E '^[[:space:]]*(#|$)' "$f"; }; done
echo '=== /etc/cron.{hourly,daily,weekly,monthly} ==='
ls -la /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly 2>/dev/null
echo '=== user crontabs ==='
@USER@
echo '=== systemd timers ==='
systemctl list-timers --all --no-pager 2>/dev/null
echo '=== at jobs ==='
atq 2>/dev/null
true''', {'USER': userCron});
    },
  ),
];

final List<ToolDefinition> networkTools = [
  ToolDefinition(
    name: 'network',
    category: ToolCategory.network,
    summary: 'Síť: naslouchající porty, spojení, rozhraní, routy, firewall, DNS',
    description:
        'Network information. view=listening: open ports and owning '
        'processes (`ss -tulpn`); connections: established connections; '
        'interfaces: IP addresses; routes: routing table; firewall: '
        'nftables/iptables/ufw rules (needs root); dns: resolv.conf and hosts.',
    params: [
      ToolParam.string('view', 'What to show.',
          enumValues: ['listening', 'connections', 'interfaces', 'routes', 'firewall', 'dns'],
          defaultValue: 'listening'),
    ],
    script: (a) {
      final body = switch (a.str('view')) {
        'listening' =>
          'if command -v ss >/dev/null 2>&1; then ss -tulpn; else netstat -tulpn; fi',
        'connections' =>
          'if command -v ss >/dev/null 2>&1; then ss -tunp state established; else netstat -tunp | grep ESTABLISHED; fi',
        'interfaces' =>
          'ip -br addr 2>/dev/null && echo && ip addr 2>/dev/null || ifconfig -a',
        'routes' => 'ip route 2>/dev/null && ip -6 route 2>/dev/null || route -n',
        'firewall' => r'''if command -v nft >/dev/null 2>&1; then echo '=== nft list ruleset ==='; nft list ruleset 2>&1; fi
if command -v iptables >/dev/null 2>&1; then echo '=== iptables -S ==='; iptables -S 2>&1; fi
if command -v ufw >/dev/null 2>&1; then echo '=== ufw status ==='; ufw status verbose 2>&1; fi
if command -v firewall-cmd >/dev/null 2>&1; then echo '=== firewalld ==='; firewall-cmd --list-all 2>&1; fi''',
        _ => r'''echo '=== /etc/resolv.conf ==='; cat /etc/resolv.conf 2>&1
echo '=== /etc/hosts ==='; cat /etc/hosts 2>&1
if command -v resolvectl >/dev/null 2>&1; then echo '=== resolvectl ==='; resolvectl status 2>/dev/null; fi
true''',
      };
      return '{\n$body\n} ${limit(500)}';
    },
  ),
];

final List<ToolDefinition> packageTools = [
  ToolDefinition(
    name: 'installed_packages',
    category: ToolCategory.packages,
    summary: 'Nainstalované balíčky a verze (dpkg/rpm/apk/pacman)',
    description:
        'List installed packages with versions (dpkg, rpm, apk or pacman), '
        'optionally only those containing a text.',
    params: [
      ToolParam.string('filter', 'Only packages containing this text.'),
      ToolParam.integer('limit', 'Maximum number of packages.',
          defaultValue: 200, min: 1, max: 5000),
    ],
    script: (a) => fill(r'''@FILTER@
if command -v dpkg-query >/dev/null 2>&1; then dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n'
elif command -v rpm >/dev/null 2>&1; then rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} installed:%{INSTALLTIME:date}\n'
elif command -v apk >/dev/null 2>&1; then apk info -v
elif command -v pacman >/dev/null 2>&1; then pacman -Q
else echo 'No supported package manager found' >&2; exit 1; fi | awk 'ENVIRON["PKG_FILTER"]=="" || index(tolower($0), tolower(ENVIRON["PKG_FILTER"]))' | sort @LIM@''',
        {
          'FILTER': exportVar('PKG_FILTER', a.strOrNull('filter')),
          'LIM': limit(a.integer('limit')),
        }),
  ),
  ToolDefinition(
    name: 'package_owner',
    category: ToolCategory.packages,
    summary: 'Ke kterému balíčku soubor patří (+ ověření změn proti balíčku)',
    description:
        'Find which package installed a file (dpkg -S / rpm -qf / apk / '
        'pacman). With verify=true also check whether files of that package '
        'were modified since installation (dpkg --verify / rpm -V).',
    params: [
      ToolParam.string('path', 'File path (no wildcards).', required: true),
      ToolParam.boolean('verify', 'Verify the package files against the package database.',
          defaultValue: false),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) => fill(r'''r=$(readlink -f -- @P@ 2>/dev/null || echo @P@)
if command -v dpkg >/dev/null 2>&1; then
  dpkg -S -- @P@ 2>/dev/null || dpkg -S -- "$r" 2>&1 || exit 1
  if [ @VERIFY@ = 1 ]; then
    pkg=$( (dpkg -S -- @P@ 2>/dev/null || dpkg -S -- "$r" 2>/dev/null) | head -n 1 | cut -d: -f1)
    echo "--- dpkg --verify $pkg (no output = no modified files) ---"
    dpkg --verify "$pkg" 2>&1 @LIM@
  fi
elif command -v rpm >/dev/null 2>&1; then
  rpm -qf -- "$r" || exit 1
  if [ @VERIFY@ = 1 ]; then echo '--- rpm -V (no output = no modified files) ---'; rpm -Vf -- "$r" 2>&1 @LIM@; fi
elif command -v apk >/dev/null 2>&1; then apk info --who-owns "$r"
elif command -v pacman >/dev/null 2>&1; then
  pacman -Qo "$r" || exit 1
  if [ @VERIFY@ = 1 ]; then pacman -Qkk "$(pacman -Qqo "$r")" 2>&1; fi
else echo 'No supported package manager found' >&2; exit 1; fi
true''', {
      'P': a.path('path', allowGlob: false),
      'VERIFY': a.flag('verify') ? '1' : '0',
      'LIM': limit(100),
    }),
  ),
  ToolDefinition(
    name: 'which',
    category: ToolCategory.packages,
    summary: 'Kde je program nainstalovaný (which / command -v)',
    description:
        'Locate an executable in PATH (`command -v`) and show the real file '
        'it points to.',
    params: [ToolParam.string('command', 'Program name, e.g. nginx.', required: true)],
    script: (a) => fill(r'''c=@C@
p=$(command -v "$c") || { echo "$c: not found in PATH ($PATH)"; exit 1; }
echo "$p"
case "$p" in
  /*) ls -l -- "$p"; printf 'resolved: '; readlink -f -- "$p";;
  *) echo '(shell builtin, function or alias)';;
esac''', {'C': a.ident('command', commandNamePattern, 'expected a program name')}),
  ),
];

final List<ToolDefinition> containerTools = [
  ToolDefinition(
    name: 'docker',
    category: ToolCategory.containers,
    summary: 'Docker/Podman: kontejnery, image, logy, inspect',
    description:
        'Read-only Docker/Podman information: list containers (all), '
        'images, logs of a container or `inspect` output (mounts, env, '
        'network). Needs docker group or root.',
    params: [
      ToolParam.string('view', 'What to show.',
          enumValues: ['containers', 'images', 'logs', 'inspect'],
          defaultValue: 'containers'),
      ToolParam.string('container', 'Container name or ID (for logs/inspect).'),
      ToolParam.integer('lines', 'Log lines (logs view).',
          defaultValue: 100, min: 1, max: 3000),
    ],
    script: (a) {
      final view = a.str('view');
      String command;
      if (view == 'containers') {
        command =
            r'''"$d" ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' ''' .trimRight();
      } else if (view == 'images') {
        command = r'"$d" images';
      } else {
        if (!a.has('container')) {
          throw ToolArgumentException('Parameter "container" is required for view=$view.');
        }
        final c = a.ident('container', containerNamePattern, 'expected a container name or ID');
        command = view == 'logs'
            ? '"\$d" logs --tail ${a.integer('lines')} -t $c 2>&1'
            : '"\$d" inspect $c';
      }
      return fill(r'''d=docker
command -v docker >/dev/null 2>&1 || d=podman
command -v "$d" >/dev/null 2>&1 || { echo 'Neither docker nor podman is installed.' >&2; exit 127; }
@CMD@ @LIM@''', {'CMD': command, 'LIM': limit(600)});
    },
  ),
];
