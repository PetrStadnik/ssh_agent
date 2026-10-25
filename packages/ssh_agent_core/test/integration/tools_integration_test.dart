// Runs every tool against a real SSH server.
//
// Skipped unless SSH_TEST_HOST is set. Example (see docs/VYVOJ.md):
//   SSH_TEST_HOST=127.0.0.1 SSH_TEST_PORT=2222 SSH_TEST_USER=agent \
//   SSH_TEST_KEY=/home/agent/.ssh/id_ed25519 SSH_TEST_SUDO=1 \
//   dart test test/integration
@Tags(['integration'])
library;

import 'dart:io';

import 'package:ssh_agent_core/ssh_agent_core.dart';
import 'package:test/test.dart';

import '../tool_samples.dart';

final env = Platform.environment;
final host = env['SSH_TEST_HOST'];

void main() {
  late SshExecutor executor;
  late RemoteSession session;
  final registry = ToolRegistry();
  final report = StringBuffer();

  setUpAll(() async {
    final keyPath = env['SSH_TEST_KEY'];
    final profile = ConnectionProfile(
      id: 'test',
      name: 'test',
      host: host!,
      port: int.parse(env['SSH_TEST_PORT'] ?? '22'),
      username: env['SSH_TEST_USER'] ?? 'agent',
      authMethod: keyPath != null
          ? SshAuthMethod.privateKey
          : SshAuthMethod.password,
      privateKeyPath: keyPath,
      elevation: env['SSH_TEST_SUDO'] == '1'
          ? ElevationMethod.sudo
          : ElevationMethod.none,
    );
    executor = SshExecutor(
      profile: profile,
      secrets: ProfileSecrets(password: env['SSH_TEST_PASSWORD']),
      verifyHostKey: (type, fingerprint) => true,
    );
    session = RemoteSession(executor: executor, elevation: profile.elevation);
    await executor.connect();
  });

  tearDownAll(() async {
    await executor.close();
    final out = env['SSH_TEST_REPORT'];
    if (out != null) File(out).writeAsStringSync(report.toString());
  });

  test('every tool has sample arguments', () {
    final missing = [
      for (final t in allTools)
        if (!samples.containsKey(t.name)) t.name,
    ];
    expect(missing, isEmpty);
  });

  for (final entry in samples.entries) {
    test('tool ${entry.key}', () async {
      // Each tool starts from a neutral state.
      session.cwd = null;
      session.runAs = null;
      final call = registry.prepare('id', entry.key, entry.value, session);
      final result = await registry.execute(call, session);
      final text = ToolRegistry.formatForModel(result);
      report
        ..writeln('=' * 70)
        ..writeln('${entry.key} ${entry.value}')
        ..writeln('\$ ${call.script}')
        ..writeln(text);
      expect(result.error, isNull, reason: text);
      expect(result.timedOut, isFalse, reason: text);
    }, skip: host == null ? 'SSH_TEST_HOST not set' : false);
  }

  test('cd changes the working directory of the session', () async {
    session.cwd = null;
    final call = registry.prepare('1', 'cd', {'path': '/var/log'}, session);
    await registry.execute(call, session);
    expect(session.cwd, '/var/log');
    final pwd = registry.prepare('2', 'pwd', {}, session);
    final result = await registry.execute(pwd, session);
    expect(result.stdout.trim(), '/var/log');
    session.cwd = null;
  }, skip: host == null ? 'SSH_TEST_HOST not set' : false);

  test(
    'switch_user runs following commands as the other user',
    () async {
      final call = registry.prepare('1', 'switch_user', {
        'user': 'root',
      }, session);
      final result = await registry.execute(call, session);
      expect(result.exitCode, 0, reason: ToolRegistry.formatForModel(result));
      final who = await registry.execute(
        registry.prepare('2', 'whoami', {}, session),
        session,
      );
      expect(who.stdout, startsWith('root'));
      await registry.execute(
        registry.prepare('3', 'switch_user', {'user': '-'}, session),
        session,
      );
      expect(session.runAs, isNull);
    },
    skip: host == null || env['SSH_TEST_SUDO'] != '1'
        ? 'needs SSH_TEST_HOST and SSH_TEST_SUDO=1'
        : false,
  );

  test('shell injection attempts are never executed', () async {
    final marker =
        '/tmp/ssh_agent_pwned_${DateTime.now().microsecondsSinceEpoch}';
    final attacks = <String, Map<String, Object?>>{
      'ls': {'path': "/tmp'; touch $marker; echo '"},
      'cat': {'path': '\$(touch $marker)'},
      'grep': {'pattern': '`touch $marker`', 'path': '/etc/hostname'},
      'find': {
        'path': '/tmp',
        'name': "x' -o -exec touch $marker ';' -o -name 'y",
      },
      'head': {'path': '-n 1 /etc/passwd; touch $marker'},
      'journal': {'grep': "x' | touch $marker; echo '"},
      'ps': {'filter': "\$(touch $marker)"},
      'installed_packages': {'filter': "'; touch $marker; '"},
      'read_compressed': {
        'path': "a.gz; touch $marker",
        'pattern': '\$(touch $marker)',
      },
    };
    for (final attack in attacks.entries) {
      session.cwd = null;
      try {
        final call = registry.prepare('x', attack.key, attack.value, session);
        await registry.execute(call, session);
      } on ToolArgumentException {
        // Rejected before execution - also fine.
      }
    }
    final check = await session.run(
      'test -e $marker && echo EXISTS || echo OK',
    );
    expect(check.stdout.trim(), 'OK');
  }, skip: host == null ? 'SSH_TEST_HOST not set' : false);

  test(
    'su elevation types the password on a pseudo terminal',
    () async {
      final profile = ConnectionProfile(
        id: 'su',
        name: 'su',
        host: host!,
        port: int.parse(env['SSH_TEST_PORT'] ?? '22'),
        username: env['SSH_TEST_USER'] ?? 'agent',
        privateKeyPath: env['SSH_TEST_KEY'],
        elevation: ElevationMethod.su,
      );
      final suExecutor = SshExecutor(
        profile: profile,
        secrets: const ProfileSecrets(),
        verifyHostKey: (_, _) => true,
      );
      final suSession = RemoteSession(
        executor: suExecutor,
        elevation: ElevationMethod.su,
        elevationPassword: env['SSH_TEST_ROOT_PASSWORD'],
      );
      try {
        final call = registry.prepare('1', 'switch_user', {
          'user': 'root',
        }, suSession);
        final result = await registry.execute(call, suSession);
        expect(result.exitCode, 0, reason: ToolRegistry.formatForModel(result));
        expect(result.stdout, startsWith('root'));
        expect(result.stdout, isNot(contains('Password')));
        final ls = await registry.execute(
          registry.prepare('2', 'head', {
            'path': '/etc/shadow',
            'lines': 1,
          }, suSession),
          suSession,
        );
        expect(ls.stdout, startsWith('root:'));
      } finally {
        await suExecutor.close();
      }
    },
    skip: host == null || env['SSH_TEST_ROOT_PASSWORD'] == null
        ? 'needs SSH_TEST_ROOT_PASSWORD'
        : false,
  );

  test(
    'password authentication and encrypted keys work',
    () async {
      Future<String> whoami(
        SshAuthMethod method,
        ProfileSecrets secrets, {
        String? keyPath,
      }) async {
        final executor = SshExecutor(
          profile: ConnectionProfile(
            id: 'auth',
            name: 'auth',
            host: host!,
            port: int.parse(env['SSH_TEST_PORT'] ?? '22'),
            username: env['SSH_TEST_USER'] ?? 'agent',
            authMethod: method,
            privateKeyPath: keyPath,
          ),
          secrets: secrets,
          verifyHostKey: (_, _) => true,
        );
        try {
          final r = await executor.execute('whoami');
          return r.stdout.trim();
        } finally {
          await executor.close();
        }
      }

      final user = env['SSH_TEST_USER'] ?? 'agent';
      expect(
        await whoami(
          SshAuthMethod.password,
          ProfileSecrets(password: env['SSH_TEST_PASSWORD']),
        ),
        user,
      );
      expect(
        await whoami(
          SshAuthMethod.privateKey,
          ProfileSecrets(passphrase: env['SSH_TEST_ENC_PASSPHRASE']),
          keyPath: env['SSH_TEST_ENC_KEY'],
        ),
        user,
      );
      await expectLater(
        whoami(
          SshAuthMethod.password,
          const ProfileSecrets(password: 'wrong-password'),
        ),
        throwsA(isA<RemoteConnectionException>()),
      );
    },
    skip: host == null || env['SSH_TEST_ENC_KEY'] == null
        ? 'needs SSH_TEST_PASSWORD, SSH_TEST_ENC_KEY, SSH_TEST_ENC_PASSPHRASE'
        : false,
  );

  test('host key fingerprint has the OpenSSH SHA256 format', () async {
    String? seen;
    final executor = SshExecutor(
      profile: ConnectionProfile(
        id: 'hk',
        name: 'hk',
        host: host!,
        port: int.parse(env['SSH_TEST_PORT'] ?? '22'),
        username: env['SSH_TEST_USER'] ?? 'agent',
        privateKeyPath: env['SSH_TEST_KEY'],
      ),
      secrets: const ProfileSecrets(),
      verifyHostKey: (type, fingerprint) {
        seen = '$type $fingerprint';
        return false;
      },
    );
    await expectLater(
      executor.connect(),
      throwsA(isA<RemoteConnectionException>()),
    );
    expect(seen, matches(RegExp(r'^\S+ SHA256:[A-Za-z0-9+/]{43}$')));
  }, skip: host == null ? 'SSH_TEST_HOST not set' : false);
}
