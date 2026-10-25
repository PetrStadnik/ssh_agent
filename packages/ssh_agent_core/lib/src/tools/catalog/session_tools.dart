import 'common.dart';

final List<ToolDefinition> sessionTools = [
  ToolDefinition(
    name: 'pwd',
    category: ToolCategory.session,
    summary: 'Aktuální pracovní adresář agenta',
    description:
        'Print the current working directory of the agent session. Relative '
        'paths in all other tools are resolved against it.',
    script: (_) => 'pwd',
  ),
  ToolDefinition(
    name: 'cd',
    category: ToolCategory.session,
    summary: 'Přesun do jiného adresáře (mění jen stav agenta, ne server)',
    description:
        'Change the working directory of the agent session, like `cd`. It '
        'only affects how relative paths are resolved in later tool calls.',
    params: [
      ToolParam.string(
        'path',
        'Directory to move to (absolute, relative or ~).',
        required: true,
      ),
    ],
    script: (a) => 'cd -- ${a.path('path', allowGlob: false)} && pwd',
    handler: (call, session) async {
      final r = await session.run(call.script, timeout: call.tool.timeout);
      final result = ToolResult.fromCommand(r);
      final lines = r.stdout.trim().split('\n');
      final dir = lines.isEmpty ? '' : lines.last.trim();
      if (r.success && dir.startsWith('/')) {
        session.cwd = dir;
        result.note = 'Working directory is now $dir';
      }
      return result;
    },
  ),
  ToolDefinition(
    name: 'whoami',
    category: ToolCategory.session,
    summary: 'Kdo jsem: uživatel, UID, skupiny',
    description:
        'Show the user the commands run as, with uid, gid and all groups '
        '(`whoami` + `id`).',
    script: (_) => 'whoami 2>/dev/null || id -un\nid',
  ),
  ToolDefinition(
    name: 'switch_user',
    category: ToolCategory.session,
    requiresUserSwitching: true,
    summary: 'Spouštět další příkazy jako jiný uživatel (su / sudo)',
    description:
        'Run all following tool calls as another Linux user, like `su <user>` '
        '(uses the sudo/su method configured for this server). Use it when '
        'you need that user\'s permissions, e.g. root to read /var/log/btmp '
        'or /etc/shadow-protected data, or to see what a given user can '
        'access. Use "-" to switch back to the login user.',
    params: [
      ToolParam.string(
        'user',
        'Target user, e.g. root or www-data; "-" = back to login user.',
        required: true,
      ),
    ],
    script: (a) {
      final user = a.str('user').trim();
      if (user != '-') {
        a.ident('user', userNamePattern, 'expected a Linux user name');
      }
      return 'whoami\nid';
    },
    runAsFor: (a, session) {
      final user = a.str('user').trim();
      return user == '-' ? session.loginUser : user;
    },
    handler: (call, session) async {
      final raw = call.args.str('user').trim();
      final target = raw == '-' ? session.loginUser : raw;
      if (target == session.loginUser) {
        session.runAs = null;
        return ToolResult(
          stdout: '',
          exitCode: 0,
          note: 'Commands now run as the login user ${session.loginUser}.',
        );
      }
      final r = await session.run(
        call.script,
        asUser: target,
        timeout: call.tool.timeout,
      );
      final result = ToolResult.fromCommand(r);
      if (r.success) {
        session.runAs = target;
        result.note = 'All following commands run as $target.';
      } else {
        result.note =
            'Switching to $target failed; commands still run as '
            '${session.effectiveUser}.';
      }
      return result;
    },
  ),
  ToolDefinition(
    name: 'system_info',
    category: ToolCategory.session,
    summary: 'Systém, distribuce, hostname, čas a časové pásmo serveru',
    description:
        'Show OS / kernel / distribution, hostname, current server date and '
        'time zone, uptime and CPU. Call it when timestamps or the OS matter.',
    script: (_) => r'''uname -a
if [ -r /etc/os-release ]; then grep -E '^(PRETTY_NAME|VERSION_ID|ID)=' /etc/os-release; fi
printf 'hostname: %s\n' "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"
printf 'server time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z (UTC%z)')"
if command -v timedatectl >/dev/null 2>&1; then timedatectl 2>/dev/null | grep -i 'time zone'; fi
printf 'uptime: %s\n' "$(uptime)"
printf 'cpus: %s\n' "$(nproc 2>/dev/null)"
if command -v systemd-detect-virt >/dev/null 2>&1; then printf 'virtualization: %s\n' "$(systemd-detect-virt 2>/dev/null)"; fi
true''',
  ),
];
