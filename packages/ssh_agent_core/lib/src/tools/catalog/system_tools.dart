import 'common.dart';

String _user(ToolArgs a, [String name = 'user']) =>
    a.ident(name, userNamePattern, 'expected a Linux user name');

String _since(ToolArgs a, String name) => a.ident(
  name,
  timeExpressionPattern,
  'use e.g. "2026-10-01", "2026-10-01 12:00", "yesterday", "-2h" or "today"',
);

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
      ToolParam.integer(
        'limit',
        'Maximum number of entries.',
        defaultValue: 50,
        min: 1,
        max: 2000,
      ),
      ToolParam.string(
        'since',
        'Only logins since this time, e.g. "2026-10-01" or "-7days" or "yesterday".',
      ),
    ],
    script: (a) {
      final n = a.integer('limit');
      final user = a.has('user') ? ' ${_user(a)}' : '';
      final since = a.has('since') ? ' --since ${_since(a, 'since')}' : '';
      return fill(
        r'''command -v last >/dev/null 2>&1 || { echo 'The last command is not available on this server.' >&2; exit 127; }
if last -F -w -i -n 1 >/dev/null 2>&1; then
  last -F -w -i -n @N@@SINCE@@USER@
else
  last -n @N@@USER@
fi''',
        {'N': '$n', 'SINCE': since, 'USER': user},
      );
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
      ToolParam.integer(
        'limit',
        'Maximum number of entries per source.',
        defaultValue: 50,
        min: 1,
        max: 2000,
      ),
      ToolParam.string(
        'since',
        'Only since this time, e.g. "2026-10-01" or "-1d".',
      ),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) {
      final since = a.has('since') ? ' --since ${_since(a, 'since')}' : '';
      return fill(
        r'''echo '=== lastb (needs root) ==='
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
true''',
        {
          'N': '${a.integer('limit')}',
          'PAT': shQuote(_authFailurePattern),
          'SINCE': since,
        },
      );
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
      ToolParam.string(
        'filter',
        'Only processes whose line contains this text (case-insensitive).',
      ),
      ToolParam.string('user', 'Only processes of this user.'),
      ToolParam.string(
        'sort',
        'Sort order.',
        enumValues: ['cpu', 'memory', 'pid', 'start'],
        defaultValue: 'cpu',
      ),
      ToolParam.boolean('tree', 'Show parent/child tree.', defaultValue: false),
      ToolParam.integer(
        'limit',
        'Maximum number of processes.',
        defaultValue: 50,
        min: 1,
        max: 2000,
      ),
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
      return fill(
        r'''@FILTER@
if ps -o pid= -p 1 --sort=pid >/dev/null 2>&1; then
  @GNU@
else
  ps aux 2>/dev/null || ps
fi | awk -v me="$$" 'NR==1 {print; next} $1==me || $2==me {next} index($0, "SYSTEMD_COLORS=0") || index($0, "PS_FILTER") || index($0, "-ww -o pid,ppid,user") {next} ENVIRON["PS_FILTER"]=="" || index(tolower($0), tolower(ENVIRON["PS_FILTER"])) {print}' @LIMIT@''',
        {
          'FILTER': exportVar('PS_FILTER', a.strOrNull('filter')),
          'GNU': gnu,
          'LIMIT': limit(a.integer('limit') + 1),
        },
      );
    },
  ),
  ToolDefinition(
    name: 'process_details',
    category: ToolCategory.processes,
    summary:
        'Detail procesu: binárka, pracovní adresář, otevřené soubory, sockety',
    description:
        'Details of one process: owner, start time, executable, working '
        'directory, full command line, status, cgroup/systemd unit, open '
        'file descriptors and network sockets. Good for "where does this '
        'service store data".',
    params: [ToolParam.integer('pid', 'Process ID.', required: true, min: 1)],
    script: (a) => fill(
      r'''p=@PID@
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
true''',
      {'PID': '${a.integer('pid')}', 'LIM5': limit(5), 'LIM80': limit(80)},
    ),
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
        return fill(
          r'''if command -v lsof >/dev/null 2>&1; then lsof -nP -p @PID@ 2>&1 @LIM@
else ls -l /proc/@PID@/fd 2>&1 @LIM@; fi''',
          {'PID': '${a.integer('pid')}', 'LIM': limit(300)},
        );
      }
      if (!a.has('path')) {
        throw ToolArgumentException('Provide either "pid" or "path".');
      }
      return fill(
        r'''if command -v lsof >/dev/null 2>&1; then lsof -nP -- @P@ 2>&1 @LIM@
elif command -v fuser >/dev/null 2>&1; then fuser -v -- @P@ 2>&1
else
  target=$(readlink -f -- @P@)
  for fd in /proc/[0-9]*/fd/*; do t=$(readlink "$fd" 2>/dev/null) && [ "$t" = "$target" ] && echo "$fd -> $t"; done
fi''',
        {'P': a.path('path', allowGlob: false), 'LIM': limit(300)},
      );
    },
  ),
  ToolDefinition(
    name: 'resource_usage',
    category: ToolCategory.processes,
    summary: 'Zátěž: CPU, paměť, load, nejnáročnější procesy',
    description:
        'Show load average, memory and swap usage, CPU count and the top '
        'processes (`uptime`, `free -h`, `top -b -n 1`).',
    script: (_) => fill(
      r'''uptime
echo '--- memory ---'
free -h 2>/dev/null || grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
printf 'cpus: %s, load: %s\n' "$(nproc 2>/dev/null)" "$(cat /proc/loadavg)"
echo '--- top ---'
top -b -n 1 2>/dev/null @LIM@
true''',
      {'LIM': limit(30)},
    ),
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
      ToolParam.string(
        'state',
        'Which services.',
        enumValues: ['running', 'failed', 'all', 'enabled'],
        defaultValue: 'running',
      ),
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
      return fill(
        r'''if [ -d /run/systemd/system ]; then
  @SYSTEMD@ @LIM@
elif command -v rc-status >/dev/null 2>&1; then rc-status -a
else service --status-all 2>&1; fi''',
        {'SYSTEMD': systemd, 'LIM': limit(400)},
      );
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
      ToolParam.string(
        'name',
        'Service name, e.g. nginx or ssh.service.',
        required: true,
      ),
      ToolParam.boolean(
        'show_unit_file',
        'Also print the unit file.',
        defaultValue: false,
      ),
    ],
    exitCodeMeaning: const {
      3: 'The service is not running (inactive or failed).',
      4: 'No such service.',
    },
    script: (a) {
      final n = a.ident(
        'name',
        unitNamePattern,
        'expected a systemd unit name',
      );
      final unitFile = a.flag('show_unit_file')
          ? '\necho "--- unit file ---"\nsystemctl cat --no-pager $n 2>&1'
          : '';
      return fill(
        r'''[ -d /run/systemd/system ] || { echo 'systemd is not running, using the service command'; service @N@ status 2>&1; exit $?; }
systemctl status --no-pager -l -n 25 @N@ 2>&1
rc=$?
echo '--- properties ---'
systemctl show --no-pager -p Id,Description,LoadState,ActiveState,SubState,UnitFileState,FragmentPath,DropInPaths,MainPID,ExecMainStartTimestamp,User,Group,WorkingDirectory,ExecStart @N@ 2>&1@UNIT@
exit $rc''',
        {'N': n, 'UNIT': unitFile},
      );
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
      ToolParam.string(
        'since',
        'Start time, e.g. "2026-10-01 08:00", "yesterday", "-2h".',
      ),
      ToolParam.string('until', 'End time, same format as since.'),
      ToolParam.string(
        'priority',
        'Show this priority and more severe.',
        enumValues: [
          'emerg',
          'alert',
          'crit',
          'err',
          'warning',
          'notice',
          'info',
          'debug',
        ],
      ),
      ToolParam.string(
        'grep',
        'Only entries matching this extended regex (case-insensitive).',
      ),
      ToolParam.boolean(
        'kernel',
        'Kernel messages only (like dmesg).',
        defaultValue: false,
      ),
      ToolParam.boolean(
        'current_boot',
        'Only the current boot.',
        defaultValue: false,
      ),
      ToolParam.integer(
        'lines',
        'Maximum number of entries (newest).',
        defaultValue: 100,
        min: 1,
        max: 3000,
      ),
    ],
    timeout: const Duration(seconds: 90),
    exitCodeMeaning: const {1: 'No matching log entries.'},
    script: (a) {
      final n = a.integer('lines');
      final opts = <String>['--no-pager', '-o short-iso'];
      if (a.has('unit')) {
        opts.add(
          '-u ${a.ident('unit', unitNamePattern, 'expected a unit name')}',
        );
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
      return fill(
        r'''if command -v journalctl >/dev/null 2>&1 && { [ -d /run/systemd/system ] || [ -d /var/log/journal ]; }; then
  @JOURNAL@
else
  if [ "@KERNEL@" = 1 ]; then dmesg -T 2>&1 | tail -n @N@; exit; fi
  f=/var/log/syslog; [ -f "$f" ] || f=/var/log/messages
  echo "(journalctl not available, reading $f)"
  @FALLBACK@
fi''',
        {
          'JOURNAL': journal,
          'FALLBACK': fallback,
          'KERNEL': a.flag('kernel') ? '1' : '0',
          'N': '$n',
        },
      );
    },
  ),
  ToolDefinition(
    name: 'cron_jobs',
    category: ToolCategory.services,
    summary: 'Naplánované úlohy: crontab, cron.d, systemd timery, at',
    description:
        'Show scheduled jobs: /etc/crontab, /etc/cron.d, cron.daily etc., '
        'user crontabs (`crontab -l`), systemd timers and at jobs.',
    params: [
      ToolParam.string(
        'user',
        'Only the crontab of this user (needs root for others).',
      ),
    ],
    script: (a) {
      final userCron = a.has('user')
          ? 'crontab -l -u ${_user(a)} 2>&1'
          : r'''crontab -l 2>&1
if [ "$(id -u)" = 0 ]; then
  for f in /var/spool/cron/crontabs/* /var/spool/cron/*; do
    [ -f "$f" ] && { echo "# $f"; grep -v -E '^[[:space:]]*(#|$)' "$f"; }
  done
fi''';
      return fill(
        r'''echo '=== /etc/crontab ==='
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
true''',
        {'USER': userCron},
      );
    },
  ),
  ToolDefinition(
    name: 'crontab',
    category: ToolCategory.services,
    summary: 'Crontaby všech uživatelů (crontab -l)',
    description:
        'Show user crontabs with `crontab -l`: by default of every user '
        'account on the server (`crontab -l -u <user>` for each), or of one '
        'user. Reading crontabs of other users needs root (use switch_user '
        'first); without root only the current user is shown. System-wide '
        'jobs (/etc/crontab, /etc/cron.d, systemd timers) are in cron_jobs.',
    params: [
      ToolParam.string('user', 'Only this user (default: all users).'),
      ToolParam.boolean(
        'include_comments',
        'Also show comment and empty lines.',
        defaultValue: false,
      ),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) {
      final users = a.has('user')
          ? _user(a)
          : r'''$(if [ "$(id -u)" = 0 ]; then (getent passwd 2>/dev/null || cat /etc/passwd) | cut -d: -f1 | awk '!seen[$0]++'; else id -un; fi)''';
      final filter = a.flag('include_comments')
          ? 'cat'
          : "grep -v -E '^[[:space:]]*(#|\$)'";
      return fill(
        r'''command -v crontab >/dev/null 2>&1 || { echo 'The crontab command is not available on this server.' >&2; exit 127; }
me=$(id -un)
if [ "$(id -u)" != 0 ]; then
  echo "Not root: only the crontab of $me can be read (switch_user root to see all users)."
fi
none=''
for u in @USERS@; do
  if [ "$u" = "$me" ]; then out=$(crontab -l 2>&1); else out=$(crontab -l -u "$u" 2>&1); fi
  rc=$?
  if [ $rc -ne 0 ]; then
    case $out in
      *'no crontab'*) none="$none $u" ;;
      *) echo "=== $u: $out" ;;
    esac
    continue
  fi
  echo "=== $u ==="
  jobs=$(printf '%s\n' "$out" | @FILTER@)
  if [ -n "$jobs" ]; then printf '%s\n' "$jobs"; else echo '(only comments)'; fi
done
[ -n "$none" ] && echo "No crontab:$none"
true''',
        {'USERS': users, 'FILTER': filter},
      );
    },
  ),
];

String _host(ToolArgs a, [String name = 'host']) =>
    a.ident(name, hostPattern, 'expected a host name or IP address');

final List<ToolDefinition> networkTools = [
  ToolDefinition(
    name: 'ports',
    category: ToolCategory.network,
    summary: 'Otevřené porty (kdo naslouchá a zda zvenku) a aktivní spojení',
    description:
        'Open ports: listening TCP/UDP sockets with the owning process and '
        'whether they are reachable from outside (all interfaces) or only '
        'locally (`ss -tulpn`). state=established lists active connections '
        'and counts them per remote address. Process names of other users '
        'need root.',
    params: [
      ToolParam.string(
        'state',
        'What to show.',
        enumValues: ['listening', 'established'],
        defaultValue: 'listening',
      ),
      ToolParam.integer(
        'port',
        'Only this port (local or remote).',
        min: 1,
        max: 65535,
      ),
    ],
    script: (a) {
      final port = '${a.intOrNull('port') ?? 0}';
      if (a.str('state') == 'listening') {
        return fill(
          r'''if ! command -v ss >/dev/null 2>&1; then netstat -tulpn 2>&1 @LIMIT@; exit; fi
[ "$(id -u)" = 0 ] || echo 'Note: processes of other users are shown only to root.'
ss -tulpn 2>/dev/null | awk -v p=@PORT@ '
NR == 1 {printf "%-4s %-30s %-20s %s\n", "PROTO", "LOCAL ADDRESS:PORT", "REACHABLE FROM", "PROCESS"; next}
{
  port = $5; sub(/.*:/, "", port)
  if (p != 0 && port != p) next
  addr = $5; sub(/:[^:]*$/, "", addr)
  if (addr ~ /^(127\.|\[::1\]|::1$|\[::ffff:127\.)/) scope = "this server only"
  else if (addr ~ /^(\*|0\.0\.0\.0|\[::\]|::)(%.*)?$/) scope = "ALL interfaces"
  else scope = "address " addr
  proc = ""; for (i = 7; i <= NF; i++) proc = proc $i
  gsub(/users:\(\(|\)\)$/, "", proc); gsub(/"/, "", proc); gsub(/\),\(/, " ", proc)
  if (proc == "") proc = "?"
  printf "%-4s %-30s %-20s %s\n", $1, $5, scope, proc
  n++
}
END {if (n == 0) print "No listening sockets" (p != 0 ? " on port " p : "") "."}' @LIMIT@''',
          {'PORT': port, 'LIMIT': limit(500)},
        );
      }
      return fill(
        r'''if ! command -v ss >/dev/null 2>&1; then netstat -tunp 2>&1 | grep ESTABLISHED @LIMIT@; exit; fi
listening=$(ss -tuln 2>/dev/null | awk 'NR > 1 {p = $5; sub(/.*:/, "", p); printf " %s", p}')
conns=$(ss -tunp state established 2>/dev/null | awk -v p=@PORT@ -v l="$listening " 'NR > 1 {
  lp = $4; sub(/.*:/, "", lp); rp = $5; sub(/.*:/, "", rp)
  if (p != 0 && lp != p && rp != p) next
  dir = index(l, " " lp " ") ? "in" : "out"
  proc = ""; for (i = 6; i <= NF; i++) proc = proc $i
  gsub(/users:\(\(|\)\)$/, "", proc); gsub(/"/, "", proc)
  print dir, $1, $4, $5, proc
}')
if [ -z "$conns" ]; then echo 'No established connections.'; exit 0; fi
printf '%s\n' "$conns" | awk '{n[$1]++} END {printf "Established connections: %d (incoming %d, outgoing %d)\n", n["in"] + n["out"], n["in"], n["out"]}'
echo '=== incoming, per local port (count, protocol, port) ==='
printf '%s\n' "$conns" | awk '$1 == "in" {lp = $3; sub(/.*:/, "", lp); n[$2 " " lp]++} END {for (k in n) print n[k], k}' | sort -rn | head -n 20
echo '=== per remote address (count, address) ==='
printf '%s\n' "$conns" | awk '{ip = $4; sub(/:[^:]*$/, "", ip); n[ip]++} END {for (ip in n) print n[ip], ip}' | sort -rn | head -n 20
echo '=== connections (direction, protocol, local, remote, process) ==='
printf '%s\n' "$conns" @LIMIT@''',
        {'PORT': port, 'LIMIT': limit(300)},
      );
    },
  ),
  ToolDefinition(
    name: 'ifconfig',
    category: ToolCategory.network,
    summary:
        'Síťová rozhraní jako ipconfig: IP adresy, MAC, brána, DNS servery',
    description:
        'Network configuration like ipconfig / ifconfig / ip addr: '
        'interfaces with IPv4/IPv6 addresses, MAC and state, default '
        'gateway, DNS servers and host name. details=true adds the full '
        'routing table and traffic counters.',
    params: [
      ToolParam.string('interface', 'Only this interface, e.g. eth0.'),
      ToolParam.boolean(
        'details',
        'Also routing tables and RX/TX counters.',
        defaultValue: false,
      ),
    ],
    script: (a) => fill(
      r'''i=@IFACE@
if command -v ip >/dev/null 2>&1; then
  if [ -n "$i" ]; then
    ip addr show dev "$i" || exit 1
    echo '=== traffic counters ==='; ip -s link show dev "$i"
  else
    echo '=== interfaces and IP addresses (ip -br addr) ==='; ip -br addr
    echo '=== MAC addresses and state (ip -br link) ==='; ip -br link
  fi
  echo '=== default gateway ==='; ip route show default; ip -6 route show default 2>/dev/null
  if [ @DETAILS@ = 1 ]; then
    [ -n "$i" ] || { echo '=== ip addr ==='; ip addr; echo '=== traffic counters (ip -s link) ==='; ip -s link; }
    echo '=== routing table ==='; ip route; ip -6 route 2>/dev/null
  fi
elif command -v ifconfig >/dev/null 2>&1; then
  if [ -n "$i" ]; then ifconfig "$i" || exit 1; else ifconfig -a; fi
  echo '=== routing table ==='; route -n 2>/dev/null || netstat -rn
else
  echo 'Neither ip nor ifconfig is available on this server.' >&2; exit 127
fi
echo '=== DNS servers ==='
grep -E '^[[:space:]]*(nameserver|search|domain)' /etc/resolv.conf 2>/dev/null
if command -v resolvectl >/dev/null 2>&1; then resolvectl dns 2>/dev/null; fi
echo '=== host name ==='
uname -n; getent hosts "$(uname -n)" 2>/dev/null
true''',
      {
        'IFACE': a.has('interface')
            ? a.ident(
                'interface',
                interfaceNamePattern,
                'expected an interface name such as eth0',
              )
            : "''",
        'DETAILS': a.flag('details') ? '1' : '0',
      },
    ),
  ),
  ToolDefinition(
    name: 'firewall',
    category: ToolCategory.network,
    summary: 'Firewall: ufw status, firewalld, nftables, iptables, fail2ban',
    description:
        'Firewall state and rules: `ufw status verbose`, firewalld zones, '
        '`nft list ruleset`, `iptables -L -n -v` (IPv4 and IPv6) and '
        'fail2ban jails with banned IPs. Usually needs root.',
    params: [
      ToolParam.string(
        'which',
        'Only this firewall.',
        enumValues: [
          'all',
          'ufw',
          'firewalld',
          'nftables',
          'iptables',
          'fail2ban',
        ],
        defaultValue: 'all',
      ),
    ],
    script: (a) => fill(
      r'''{
w=@WHICH@
found=0
want() { [ "$w" = all ] || [ "$w" = "$1" ]; }
[ "$(id -u)" = 0 ] || echo 'Note: most firewall commands need root (switch_user root).'
if want ufw && command -v ufw >/dev/null 2>&1; then
  found=1; echo '=== ufw status verbose ==='; ufw status verbose 2>&1
fi
if want firewalld && command -v firewall-cmd >/dev/null 2>&1; then
  found=1; echo '=== firewalld ==='
  if firewall-cmd --state 2>&1; then firewall-cmd --get-active-zones 2>&1; firewall-cmd --list-all 2>&1; fi
fi
if want nftables && command -v nft >/dev/null 2>&1; then
  found=1; echo '=== nft list ruleset ==='; nft list ruleset 2>&1
fi
if want iptables && command -v iptables >/dev/null 2>&1; then
  found=1; echo '=== iptables -L -n -v (IPv4) ==='; iptables -L -n -v --line-numbers 2>&1
  if command -v ip6tables >/dev/null 2>&1; then echo '=== ip6tables -L -n -v (IPv6) ==='; ip6tables -L -n -v --line-numbers 2>&1; fi
fi
if want fail2ban && command -v fail2ban-client >/dev/null 2>&1; then
  found=1; echo '=== fail2ban ==='
  fail2ban-client status 2>&1
  for j in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do
    fail2ban-client status "$j" 2>&1
  done
fi
[ "$found" = 1 ] || echo "No firewall tool found (checked: $w)."
true
} @LIMIT@''',
      {'WHICH': shQuote(a.str('which')), 'LIMIT': limit(600)},
    ),
  ),
  ToolDefinition(
    name: 'dns_lookup',
    category: ToolCategory.network,
    summary: 'DNS: přeloží jméno na IP (nebo IP na jméno), záznamy MX, TXT…',
    description:
        'Resolve a host name with the system resolver and with dig / host / '
        'nslookup (record type A, AAAA, MX, TXT, NS, CNAME, SOA); an IP '
        'address gives a reverse (PTR) lookup. Optionally ask a given DNS '
        'server.',
    params: [
      ToolParam.string('name', 'Host name or IP address.', required: true),
      ToolParam.string(
        'type',
        'Record type.',
        enumValues: ['A', 'AAAA', 'MX', 'TXT', 'NS', 'CNAME', 'SOA', 'ANY'],
        defaultValue: 'A',
      ),
      ToolParam.string('server', 'DNS server to ask (IP or name).'),
    ],
    script: (a) => fill(
      r'''n=@NAME@; t=@TYPE@; s=@SERVER@
ip=0
case $n in *:*) ip=1 ;; *[!0-9.]*) ;; *) ip=1 ;; esac
echo '=== system resolver (getent) ==='
if [ "$ip" = 1 ]; then r=$(getent hosts "$n" 2>/dev/null); else r=$(getent ahosts "$n" 2>/dev/null | awk '!seen[$1]++ {print $1}'); fi
if [ -n "$r" ]; then printf '%s\n' "$r"; else echo '(not resolved)'; fi
if command -v dig >/dev/null 2>&1; then
  if [ "$ip" = 1 ]; then echo '=== dig -x ==='; set -- -x "$n"; else echo "=== dig $t ==="; set -- "$n" "$t"; fi
  [ -n "$s" ] && set -- "$@" "@$s"
  out=$(dig +noall +answer +time=3 +tries=2 "$@" 2>&1)
  if [ -n "$out" ]; then printf '%s\n' "$out"; else dig +time=3 +tries=2 "$@" 2>&1 | grep -E 'status:|SERVER:|timed out' || echo '(no answer)'; fi
elif command -v host >/dev/null 2>&1; then
  echo '=== host ==='
  if [ "$ip" = 1 ]; then host "$n" ${s:+"$s"} 2>&1; else host -t "$t" "$n" ${s:+"$s"} 2>&1; fi
elif command -v nslookup >/dev/null 2>&1; then
  echo '=== nslookup ==='; nslookup -type="$t" "$n" ${s:+"$s"} 2>&1
else
  echo '(dig, host and nslookup are not installed - only the system resolver was asked)'
fi
true''',
      {
        'NAME': _host(a, 'name'),
        'TYPE': shQuote(a.str('type')),
        'SERVER': a.has('server') ? _host(a, 'server') : "''",
      },
    ),
  ),
  ToolDefinition(
    name: 'ping',
    category: ToolCategory.network,
    summary: 'Ping na hostitele, případně trasa (traceroute / tracepath)',
    description:
        'Check whether a host answers (`ping -c N`) or, with trace=true, '
        'show the network path to it (tracepath / traceroute / mtr). Sends '
        'a few packets from the server.',
    params: [
      ToolParam.string('host', 'Host name or IP address.', required: true),
      ToolParam.integer(
        'count',
        'Number of pings.',
        defaultValue: 4,
        min: 1,
        max: 10,
      ),
      ToolParam.boolean(
        'trace',
        'Show the route instead (traceroute).',
        defaultValue: false,
      ),
    ],
    timeout: const Duration(seconds: 70),
    exitCodeMeaning: const {
      1: 'No reply - the host is down, unreachable or blocks ping.',
    },
    script: (a) => fill(
      r'''h=@HOST@
lim=''; command -v timeout >/dev/null 2>&1 && lim='timeout 60'
if [ @TRACE@ = 1 ]; then
  if command -v tracepath >/dev/null 2>&1; then $lim tracepath -m 20 "$h"
  elif command -v traceroute >/dev/null 2>&1; then $lim traceroute -m 20 -w 2 -q 1 "$h"
  elif command -v mtr >/dev/null 2>&1; then $lim mtr --report --report-cycles 1 "$h"
  else echo 'No traceroute tool (tracepath, traceroute, mtr) is installed.' >&2; exit 127; fi
else
  command -v ping >/dev/null 2>&1 || { echo 'ping is not installed on this server.' >&2; exit 127; }
  ping -c @COUNT@ -W 2 "$h"
fi''',
      {
        'HOST': _host(a),
        'TRACE': a.flag('trace') ? '1' : '0',
        'COUNT': '${a.integer('count')}',
      },
    ),
  ),
  ToolDefinition(
    name: 'port_check',
    category: ToolCategory.network,
    summary: 'Je port na hostiteli dostupný ze serveru? (TCP spojení)',
    description:
        'Test from the server whether a TCP port on a host accepts '
        'connections (e.g. is the database db1:5432 reachable): OPEN, '
        'CLOSED (refused) or TIMEOUT (filtered). Opens and immediately '
        'closes one connection; nothing is sent.',
    params: [
      ToolParam.string('host', 'Host name or IP address.', required: true),
      ToolParam.integer(
        'port',
        'TCP port.',
        required: true,
        min: 1,
        max: 65535,
      ),
      ToolParam.integer(
        'timeout_seconds',
        'How long to wait.',
        defaultValue: 3,
        min: 1,
        max: 10,
      ),
    ],
    exitCodeMeaning: const {
      1: 'The port is not reachable (see the output).',
      2: 'The host name could not be resolved.',
    },
    script: (a) => fill(
      r'''h=@HOST@; p=@PORT@; w=@WAIT@
addr=$(getent ahosts "$h" 2>/dev/null | awk 'NR == 1 {print $1}')
[ -n "$addr" ] || { echo "Cannot resolve $h"; exit 2; }
[ "$addr" = "$h" ] || echo "$h resolves to $addr"
if ! command -v bash >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
  echo 'This check needs bash and timeout on the server.' >&2; exit 127
fi
timeout "$w" bash -c ': </dev/tcp/"$1"/"$2"' _ "$h" "$p" 2>/dev/null
case $? in
  0) echo "OPEN: $h:$p accepts TCP connections" ;;
  124) echo "TIMEOUT: no answer from $h:$p within ${w}s (filtered by a firewall, or the host is down)"; exit 1 ;;
  *) echo "CLOSED: connection to $h:$p refused or no route to host"; exit 1 ;;
esac''',
      {
        'HOST': _host(a),
        'PORT': '${a.integer('port')}',
        'WAIT': '${a.integer('timeout_seconds')}',
      },
    ),
  ),
  ToolDefinition(
    name: 'internet_check',
    category: ToolCategory.network,
    summary: 'Má server internet? Brána, DNS, ping, HTTPS, proxy, veřejná IP',
    description:
        'Check whether the server can reach the internet: default route, '
        'DNS resolution (example.com), ping and HTTPS port 443 to 1.1.1.1, '
        'proxy settings and the public IP address (DNS query to OpenDNS, '
        'needs dig). Sends a few small packets to these public services.',
    timeout: const Duration(seconds: 45),
    script: (a) => r'''echo '=== default route ==='
ip route show default 2>/dev/null || route -n 2>/dev/null | grep '^0\.0\.0\.0'
echo '=== DNS (example.com) ==='
r=$(getent ahosts example.com 2>/dev/null | awk 'NR == 1 {print $1}')
if [ -n "$r" ]; then echo "OK - example.com is $r"; else echo 'FAILED - host names cannot be resolved'; fi
echo '=== ping 1.1.1.1 ==='
if command -v ping >/dev/null 2>&1; then ping -c 2 -W 2 1.1.1.1 2>&1 | tail -n 2; else echo 'ping is not installed'; fi
echo '=== HTTPS port 443 on 1.1.1.1 ==='
if command -v bash >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  if timeout 5 bash -c ': </dev/tcp/1.1.1.1/443' 2>/dev/null; then echo 'OK - outgoing HTTPS works'; else echo 'FAILED - outgoing HTTPS is blocked or there is no internet'; fi
else echo 'unknown (needs bash and timeout)'; fi
echo '=== proxy settings ==='
{ env; cat /etc/environment 2>/dev/null; } | grep -i -E '^(https?|ftp|all|no)_proxy=' | sed -E 's#//[^/@]*@#//***@#' | sort -u | cut -c 1-200
echo '=== public IP address ==='
if command -v dig >/dev/null 2>&1; then
  pub=$(dig +short +time=3 +tries=1 myip.opendns.com A @resolver1.opendns.com 2>/dev/null | tail -n 1)
  echo "${pub:-unknown (OpenDNS did not answer)}"
else echo 'unknown (dig is not installed)'; fi
true''',
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
      ToolParam.integer(
        'limit',
        'Maximum number of packages.',
        defaultValue: 200,
        min: 1,
        max: 5000,
      ),
    ],
    script: (a) => fill(
      r'''@FILTER@
if command -v dpkg-query >/dev/null 2>&1; then dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n'
elif command -v rpm >/dev/null 2>&1; then rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} installed:%{INSTALLTIME:date}\n'
elif command -v apk >/dev/null 2>&1; then apk info -v
elif command -v pacman >/dev/null 2>&1; then pacman -Q
else echo 'No supported package manager found' >&2; exit 1; fi | awk 'ENVIRON["PKG_FILTER"]=="" || index(tolower($0), tolower(ENVIRON["PKG_FILTER"]))' | sort @LIM@''',
      {
        'FILTER': exportVar('PKG_FILTER', a.strOrNull('filter')),
        'LIM': limit(a.integer('limit')),
      },
    ),
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
      ToolParam.boolean(
        'verify',
        'Verify the package files against the package database.',
        defaultValue: false,
      ),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) => fill(
      r'''r=$(readlink -f -- @P@ 2>/dev/null || echo @P@)
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
true''',
      {
        'P': a.path('path', allowGlob: false),
        'VERIFY': a.flag('verify') ? '1' : '0',
        'LIM': limit(100),
      },
    ),
  ),
  ToolDefinition(
    name: 'which',
    category: ToolCategory.packages,
    summary: 'Kde je program nainstalovaný (which / command -v)',
    description:
        'Locate an executable in PATH (`command -v`) and show the real file '
        'it points to.',
    params: [
      ToolParam.string('command', 'Program name, e.g. nginx.', required: true),
    ],
    script: (a) => fill(
      r'''c=@C@
p=$(command -v "$c") || { echo "$c: not found in PATH ($PATH)"; exit 1; }
echo "$p"
case "$p" in
  /*) ls -l -- "$p"; printf 'resolved: '; readlink -f -- "$p";;
  *) echo '(shell builtin, function or alias)';;
esac''',
      {'C': a.ident('command', commandNamePattern, 'expected a program name')},
    ),
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
      ToolParam.string(
        'view',
        'What to show.',
        enumValues: ['containers', 'images', 'logs', 'inspect'],
        defaultValue: 'containers',
      ),
      ToolParam.string('container', 'Container name or ID (for logs/inspect).'),
      ToolParam.integer(
        'lines',
        'Log lines (logs view).',
        defaultValue: 100,
        min: 1,
        max: 3000,
      ),
    ],
    script: (a) {
      final view = a.str('view');
      String command;
      if (view == 'containers') {
        command =
            r'''"$d" ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' '''
                .trimRight();
      } else if (view == 'images') {
        command = r'"$d" images';
      } else {
        if (!a.has('container')) {
          throw ToolArgumentException(
            'Parameter "container" is required for view=$view.',
          );
        }
        final c = a.ident(
          'container',
          containerNamePattern,
          'expected a container name or ID',
        );
        command = view == 'logs'
            ? '"\$d" logs --tail ${a.integer('lines')} -t $c 2>&1'
            : '"\$d" inspect $c';
      }
      return fill(
        r'''d=docker
command -v docker >/dev/null 2>&1 || d=podman
command -v "$d" >/dev/null 2>&1 || { echo 'Neither docker nor podman is installed.' >&2; exit 127; }
@CMD@ @LIM@''',
        {'CMD': command, 'LIM': limit(600)},
      );
    },
  ),
];
