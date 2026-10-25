import 'dart:convert';

import 'package:ssh_agent_core/ssh_agent_core.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'tool_samples.dart';

/// Commands / options that modify the system. None of them may ever appear
/// in a script built by a tool.
final List<RegExp> forbidden = [
  for (final word in [
    'rm', 'rmdir', 'mv', 'cp', 'ln', 'touch', 'mkdir', 'chmod', 'chown',
    'chgrp', 'chattr', 'setfacl', 'tee', 'dd', 'truncate', 'shred', 'install',
    'kill', 'pkill', 'killall', 'reboot', 'shutdown', 'halt', 'poweroff',
    'useradd', 'userdel', 'usermod', 'groupadd', 'groupdel', 'chpasswd', 'mount', 'umount', 'mkfs', 'fdisk', 'parted', 'apt', 'apt-get',
    'yum', 'dnf', 'pip', 'npm', 'curl', 'wget', 'scp', 'rsync', 'nc', 'ncat',
    'visudo', 'vi', 'vim', 'nano', 'ed', 'patch', 'git',
  ])
    RegExp('(^|[\\s;&(`])$word(\$|[\\s;|&)])'),
  RegExp(r'sed\s+(-[a-zA-Z]*i|--in-place)'),
  RegExp(r'-delete\b'),
  RegExp(r'-exec(dir)?\b'),
  RegExp(r'-fprint'),
  RegExp(r'-ok\b'),
  RegExp(r'crontab\s+-[er]'),
  RegExp(r'systemctl\s+(start|stop|restart|reload|enable|disable|mask|unmask|kill|edit|set-property|daemon-reload)'),
  RegExp(r'docker\s+(rm|run|exec|kill|stop|start|restart|pull|push|cp|commit)'),
  RegExp(r'nft\s+(add|delete|flush|insert|replace|create)'),
  RegExp(r'iptables\s+-[ADIFXNPR]\b'),
  RegExp(r'ufw\s+(allow|deny|delete|enable|disable|reset)'),
  RegExp(r'fuser\s+.*-k'),
  RegExp(r'(^|\s)passwd\s+-[^S]'),
  // Redirection into a file (only /dev/null and file descriptors allowed).
  RegExp(r'''[^<>=!\-\s]\s*>>?\s*(?!/dev/null|&\d)["'/~$]'''),
];

String? violation(String script) {
  for (final pattern in forbidden) {
    final match = pattern.firstMatch(script);
    if (match != null) return '${pattern.pattern} -> "${match.group(0)}"';
  }
  return null;
}

/// The parts of a POSIX shell script that are not inside quotes (what the
/// shell would interpret as syntax).
String unquotedText(String script) {
  final out = StringBuffer();
  var i = 0;
  while (i < script.length) {
    final ch = script[i];
    if (ch == "'") {
      final end = script.indexOf("'", i + 1);
      i = end == -1 ? script.length : end + 1;
      out.write('_');
    } else if (ch == '\\') {
      i += 2;
      out.write('_');
    } else if (ch == '"') {
      i++;
      while (i < script.length && script[i] != '"') {
        if (script[i] == '\\') i++;
        i++;
      }
      i++;
      out.write('_');
    } else {
      out.write(ch);
      i++;
    }
  }
  return out.toString();
}

/// Values a malicious model (or a prompt injection) might send.
const List<String> hostile = [
  "'; rm -rf / #",
  r'$(rm -rf /)',
  '`rm -rf /`',
  '/tmp/x > /etc/passwd',
  '-delete',
  '-exec rm {} ;',
  r'a" ; touch /tmp/p ; "',
  '| tee /etc/x',
];

void main() {
  final session = RemoteSession(
    executor: FakeExecutor(),
    elevation: ElevationMethod.sudo,
  );
  final registry = ToolRegistry();

  test('tool names are unique and valid identifiers', () {
    final names = [for (final t in allTools) t.name];
    expect(names.toSet().length, names.length);
    for (final n in names) {
      expect(n, matches(RegExp(r'^[a-z][a-z0-9_]{1,40}$')));
    }
  });

  test('every tool exports a valid JSON schema', () {
    for (final tool in allTools) {
      final schema = tool.toFunctionSchema();
      final encoded = jsonEncode(schema);
      final function = (jsonDecode(encoded) as Map)['function'] as Map;
      expect(function['name'], tool.name);
      expect((function['description'] as String).length, greaterThan(20),
          reason: tool.name);
      final params = function['parameters'] as Map;
      expect(params['type'], 'object');
      for (final required in params['required'] as List) {
        expect((params['properties'] as Map).containsKey(required), isTrue);
      }
    }
  });

  test('all tool definitions together stay reasonably small', () {
    final size = jsonEncode(registry.schemas(session)).length;
    // ~4 characters per token: keep the definitions well below 8k tokens.
    expect(size, lessThan(32000), reason: 'schemas are $size characters');
  });

  test('scripts built from sample arguments contain no modifying command', () {
    for (final entry in samples.entries) {
      final call = registry.prepare('x', entry.key, entry.value, session);
      expect(violation(call.script), isNull,
          reason: '${entry.key}: ${call.script}');
    }
  });

  test('hostile argument values never produce a modifying command', () {
    var built = 0;
    for (final tool in registry.available(session)) {
      final base = samples[tool.name]!;
      for (final param in tool.params) {
        if (param.type != ParamType.string || param.enumValues != null) {
          continue;
        }
        for (final value in hostile) {
          final args = {...base, param.name: value};
          try {
            final call = registry.prepare('x', tool.name, args, session);
            built++;
            // Every hostile value must appear only inside quotes: removing
            // all single-quoted parts must remove the payload.
            final unquoted = unquotedText(call.script);
            expect(unquoted, isNot(contains('rm -rf')),
                reason: '${tool.name}.${param.name}: ${call.script}');
            expect(unquoted, isNot(contains('touch /tmp/p')),
                reason: '${tool.name}.${param.name}: ${call.script}');
            expect(unquoted, isNot(contains('tee /etc/x')),
                reason: '${tool.name}.${param.name}: ${call.script}');
          } on ToolArgumentException {
            // Rejected by validation - fine.
          }
        }
      }
    }
    expect(built, greaterThan(50));
  });

  group('argument handling', () {
    test('missing required parameter is reported to the model', () {
      expect(() => registry.prepare('x', 'stat', {}, session),
          throwsA(isA<ToolArgumentException>()));
    });

    test('unknown tool lists the available ones', () {
      expect(
          () => registry.prepare('x', 'rm', {'path': '/'}, session),
          throwsA(isA<UnknownToolException>().having(
              (e) => e.toString(), 'message', contains('stat'))));
    });

    test('numbers and booleans sent as strings are coerced and clamped', () {
      final call = registry.prepare(
          'x', 'tail', {'path': '/var/log/syslog', 'lines': '999999'}, session);
      expect(call.args.integer('lines'), 3000);
      final ls = registry.prepare(
          'x', 'ls', {'path': '/', 'recursive': 'true'}, session);
      expect(ls.args.flag('recursive'), isTrue);
    });

    test('enum values are case-insensitive and validated', () {
      final call =
          registry.prepare('x', 'checksum', {'path': '/a', 'algorithm': 'MD5'}, session);
      expect(call.script, startsWith('md5sum'));
      expect(
          () => registry.prepare(
              'x', 'checksum', {'path': '/a', 'algorithm': 'crc'}, session),
          throwsA(isA<ToolArgumentException>()));
    });

    test('switch_user is only offered when the profile allows it', () {
      final plain = RemoteSession(executor: FakeExecutor());
      expect(registry.available(plain).map((t) => t.name),
          isNot(contains('switch_user')));
      expect(registry.available(session).map((t) => t.name),
          contains('switch_user'));
    });

    test('disabled categories are not offered', () {
      final limited = ToolRegistry(enabledCategories: {ToolCategory.files});
      expect(limited.available(session).every((t) => t.category == ToolCategory.files),
          isTrue);
    });
  });

  group('command wrapping', () {
    test('runs in the working directory with a predictable environment', () {
      final s = RemoteSession(executor: FakeExecutor(), initialDirectory: '/var/www');
      final command = s.buildCommand('ls');
      expect(command, startsWith('sh -c '));
      expect(s.scriptWithContext('ls'), contains("cd -- '/var/www' || exit 1"));
      expect(s.scriptWithContext('ls'), contains('LC_ALL=C'));
    });

    test('sudo without password never prompts (-n)', () {
      final s = RemoteSession(executor: FakeExecutor(), elevation: ElevationMethod.sudo)
        ..runAs = 'root';
      expect(s.buildCommand('id'), startsWith("sudo -n -u 'root' -- sh -c "));
    });

    test('sudo with password reads it from stdin (-S)', () {
      final s = RemoteSession(
          executor: FakeExecutor(),
          elevation: ElevationMethod.sudo,
          elevationPassword: 'pw')
        ..runAs = 'root';
      expect(s.buildCommand('id'), startsWith("sudo -S -p '' -u 'root' -- "));
    });

    test('su runs a POSIX shell as the target user', () {
      final s = RemoteSession(executor: FakeExecutor(), elevation: ElevationMethod.su)
        ..runAs = 'www-data';
      expect(s.buildCommand('id'), startsWith("LC_ALL=C su -s /bin/sh 'www-data' -c "));
    });
  });

  test('formatForModel keeps head and tail of long output', () {
    final long = List.generate(5000, (i) => 'line $i').join('\n');
    final text = ToolRegistry.formatForModel(
        ToolResult(stdout: long, exitCode: 0),
        maxChars: 2000);
    expect(text.length, lessThan(2300));
    expect(text, contains('line 0'));
    expect(text, contains('line 4999'));
    expect(text, contains('omitted'));
  });

  test('binary output is replaced by a notice', () async {
    final s = RemoteSession(
        executor: FakeExecutor(
            respond: (_) => const CommandResult(
                stdout: 'ELF\u0000\u0001',
                stderr: '',
                exitCode: 0,
                duration: Duration.zero)));
    final call = registry.prepare('x', 'cat', {'path': '/bin/ls'}, s);
    final result = await registry.execute(call, s);
    expect(result.stdout, contains('Binary content'));
  });

  test('exit code meaning is added as a note', () async {
    final s = RemoteSession(
        executor: FakeExecutor(
            respond: (_) => const CommandResult(
                stdout: '', stderr: '', exitCode: 1, duration: Duration.zero)));
    final call = registry.prepare('x', 'grep', {'pattern': 'x'}, s);
    final result = await registry.execute(call, s);
    expect(result.note, 'No matches found.');
  });
}
