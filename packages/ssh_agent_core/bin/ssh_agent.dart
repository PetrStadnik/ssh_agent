// Command line client of SSH Agent - the same core as the app, handy for
// testing a model or a server without the GUI.
//
//   dart run ssh_agent_core:ssh_agent --host 10.0.0.5 --user root \
//       --key ~/.ssh/id_ed25519 --model qwen3.5:9b "Kdo se včera přihlásil?"
//
// Without a question an interactive session starts. Run with --help.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ssh_agent_core/ssh_agent_core.dart';

const usage = '''
SSH Agent CLI - read-only AI agent for Linux servers

Usage: ssh_agent [options] [question]

Connection:
  --host HOST            server address (required)
  --port N               SSH port (default 22)
  --user NAME            login user (required)
  --key PATH             private key file
  --passphrase-env VAR   environment variable with the key passphrase
  --password-env VAR     environment variable with the SSH password
  --sudo | --su          allow switch_user via sudo / su
  --elevation-password-env VAR   password for sudo/su
  --host-key SHA256:...  expected host key fingerprint (otherwise asked)
  --cwd DIR              initial working directory

Model:
  --provider ollama|openai   (default ollama)
  --url URL              model server (default http://127.0.0.1:11434)
  --model NAME           (default qwen3.5:9b)
  --ctx N                context window (default 32768)
  --think auto|off|on|low|medium|high
  --max-steps N          (default 20)

Other:
  --list-tools           print the tools and exit
  --tool NAME --args JSON   run one tool directly (no model)
  --approve              ask before every command
''';

Future<void> main(List<String> argv) async {
  final opts = <String, String>{};
  final flags = <String>{};
  final rest = <String>[];
  const boolFlags = {
    '--sudo',
    '--su',
    '--list-tools',
    '--approve',
    '--help',
    '-h',
  };
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (boolFlags.contains(a)) {
      flags.add(a);
    } else if (a.startsWith('--')) {
      if (i + 1 >= argv.length) _fail('Missing value for $a');
      opts[a] = argv[++i];
    } else {
      rest.add(a);
    }
  }
  if (flags.contains('--help') || flags.contains('-h')) {
    stdout.write(usage);
    return;
  }
  if (flags.contains('--list-tools')) {
    for (final category in ToolCategory.values) {
      stdout.writeln('\n${category.label}:');
      for (final t in allTools.where((t) => t.category == category)) {
        stdout.writeln('  ${t.name.padRight(20)} ${t.summary}');
      }
    }
    return;
  }

  final host = opts['--host'] ?? _fail('--host is required\n\n$usage');
  final user = opts['--user'] ?? _fail('--user is required');
  String? env(String option) =>
      opts[option] == null ? null : Platform.environment[opts[option]!];
  final elevation = flags.contains('--sudo')
      ? ElevationMethod.sudo
      : flags.contains('--su')
      ? ElevationMethod.su
      : ElevationMethod.none;
  final profile = ConnectionProfile(
    id: 'cli',
    name: host,
    host: host,
    port: int.tryParse(opts['--port'] ?? '') ?? 22,
    username: user,
    authMethod: opts['--key'] != null
        ? SshAuthMethod.privateKey
        : SshAuthMethod.password,
    privateKeyPath: opts['--key'],
    elevation: elevation,
  );
  final executor = SshExecutor(
    profile: profile,
    secrets: ProfileSecrets(
      password: env('--password-env'),
      passphrase: env('--passphrase-env'),
    ),
    verifyHostKey: (type, fingerprint) {
      final expected = opts['--host-key'];
      if (expected != null) return expected == fingerprint;
      stderr.writeln('Host key of $host: $type $fingerprint');
      stderr.write('Trust it? Next time pass --host-key $fingerprint [y/N] ');
      return (stdin.readLineSync() ?? '').trim().toLowerCase().startsWith('y');
    },
  );
  final session = RemoteSession(
    executor: executor,
    elevation: elevation,
    elevationPassword: env('--elevation-password-env'),
    initialDirectory: opts['--cwd'],
  );
  final registry = ToolRegistry();
  final ui = _Printer();

  try {
    await executor.connect();
  } on RemoteConnectionException catch (e) {
    _fail(e.message);
  }

  if (opts['--tool'] != null) {
    final args = opts['--args'] == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(opts['--args']!) as Map);
    final call = registry.prepare('cli', opts['--tool']!, args, session);
    ui.toolStarted(
      call.tool.name,
      call.args.values,
      call.script,
      session.effectiveUser,
      session.cwd,
      profile.name,
    );
    final result = await registry.execute(call, session);
    ui.toolFinished(result, full: true);
    await executor.close();
    return;
  }

  final llm = createLlmClient(
    LlmConfig(
      provider: opts['--provider'] == 'openai'
          ? LlmProvider.openAiCompatible
          : LlmProvider.ollama,
      baseUrl:
          opts['--url'] ??
          (opts['--provider'] == 'openai'
              ? 'http://127.0.0.1:1234/v1'
              : 'http://127.0.0.1:11434'),
      model: opts['--model'] ?? 'qwen3.5:9b',
      contextLength: int.tryParse(opts['--ctx'] ?? '') ?? 32768,
      thinking: ThinkingMode.values.firstWhere(
        (t) => t.name == opts['--think'],
        orElse: () => ThinkingMode.auto,
      ),
    ),
  );
  final agent = Agent(
    llm: llm,
    tools: registry,
    session: session,
    serverName: profile.name,
    config: AgentConfig(
      maxSteps: int.tryParse(opts['--max-steps'] ?? '') ?? 20,
    ),
    approver: flags.contains('--approve')
        ? (call) async {
            stderr.write('Run `${call.script.split('\n').first}`? [Y/n] ');
            final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
            return answer.isEmpty || answer.startsWith('y');
          }
        : null,
  );

  final conversation = Conversation(id: 'cli');
  Future<void> ask(String question) async {
    final history = conversation.toHistory();
    conversation.turns.add(UserTurn(question));
    final turn = AgentTurn();
    conversation.turns.add(turn);
    final cancel = CancelToken();
    final sub = ProcessSignal.sigint.watch().listen((_) => cancel.cancel());
    try {
      await for (final event in agent.run(
        history: history,
        userMessage: question,
        cancel: cancel,
      )) {
        turn.apply(event);
        ui.event(event);
      }
    } finally {
      await sub.cancel();
    }
  }

  if (rest.isNotEmpty) {
    await ask(rest.join(' '));
  } else {
    stdout.writeln(
      'Připojeno k ${profile.label}. Pište otázky, "exit" ukončí.',
    );
    while (true) {
      stdout.write('\n> ');
      final line = stdin.readLineSync(encoding: utf8);
      if (line == null || line.trim() == 'exit') break;
      if (line.trim().isEmpty) continue;
      await ask(line.trim());
    }
  }
  await executor.close();
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

class _Printer {
  final bool color = stdout.supportsAnsiEscapes;
  bool _inText = false;
  bool _inThinking = false;

  /// Live output of the running tool: partial line and printed lines.
  String _partial = '';
  int _liveLines = 0;
  bool _liveShown = false;
  static const int _maxLiveLines = 200;

  String _c(String code, String text) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  void event(AgentEvent e) {
    switch (e) {
      case AgentConnecting(:final server):
        stdout.writeln(_c('2', '↻ Připojuji se k serveru $server…'));
      case AgentConnected(:final duration):
        stdout.writeln(_c('2', '✓ Připojeno za ${duration.inMilliseconds} ms'));
      case AgentStepStarted(
        :final step,
        :final retry,
        :final approxPromptTokens,
      ):
        _endText();
        stdout.writeln(
          _c(
            '2',
            '◆ Krok ${step + 1}${retry ? ' (opakování)' : ''} – čekám na '
                'model (~${approxPromptTokens ?? '?'} tokenů vstupu)…',
          ),
        );
      case AgentAssistantMessage(:final usage, :final elapsed):
        _endText();
        stdout.writeln(_c('2', '  model: ${_modelStats(elapsed, usage)}'));
      case AgentThinkingDelta(:final text):
        if (!_inThinking) stdout.write(_c('2', '\n💭 '));
        _inThinking = true;
        stdout.write(_c('2', text));
      case AgentTextDelta(:final text):
        if (_inThinking) stdout.writeln();
        _inThinking = false;
        _inText = true;
        stdout.write(text);
      case AgentToolCallStarted():
        _endText();
        toolStarted(e.name, e.arguments, e.script, e.runAs, e.cwd, e.server);
      case AgentToolOutput(:final text):
        _liveShown = true;
        _partial += text;
        final lines = _partial.split('\n');
        _partial = lines.removeLast();
        for (final line in lines) {
          _printLive(line);
        }
      case AgentToolCallFinished(:final result):
        if (_partial.isNotEmpty) _printLive(_partial);
        toolFinished(result, outputShown: _liveShown);
        _partial = '';
        _liveLines = 0;
        _liveShown = false;
      case AgentNotice(:final message):
        _endText();
        stdout.writeln(_c('33', 'ℹ $message'));
      case AgentCompleted():
        _endText();
      case AgentFailed(:final message):
        _endText();
        stdout.writeln(_c('31', '✖ $message'));
      case AgentCancelled():
        _endText();
        stdout.writeln(_c('33', '■ Zrušeno'));
    }
  }

  void _printLive(String line) {
    _liveLines++;
    if (_liveLines <= _maxLiveLines) {
      stdout.writeln(_c('2', '  │ $line'));
    } else if (_liveLines == _maxLiveLines + 1) {
      stdout.writeln(_c('2', '  │ … (další výstup se nevypisuje)'));
    }
  }

  static String _modelStats(Duration? elapsed, LlmUsage? usage) {
    String seconds(Duration? d) =>
        d == null ? '?' : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
    return [
      seconds(elapsed),
      if (usage?.loadDuration != null &&
          usage!.loadDuration!.inMilliseconds > 500)
        'načtení modelu ${seconds(usage.loadDuration)}',
      if (usage?.promptTokens != null)
        'vstup ${usage!.promptTokens} tok.'
            '${usage.promptDuration == null ? '' : ' za ${seconds(usage.promptDuration)}'}',
      if (usage?.completionTokens != null)
        'výstup ${usage!.completionTokens} tok.',
    ].join(' · ');
  }

  void _endText() {
    if (_inText || _inThinking) stdout.writeln();
    _inText = false;
    _inThinking = false;
  }

  void toolStarted(
    String name,
    Map<String, Object?> args,
    String? script,
    String? runAs,
    String? cwd,
    String server,
  ) {
    final argText = args.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    stdout.writeln(
      _c('36', '⚙ $name($argText)  [$runAs@$server ${cwd ?? '~'}]'),
    );
    if (script != null) {
      for (final line in script.split('\n').take(6)) {
        stdout.writeln(_c('2', '  \$ $line'));
      }
    }
  }

  void toolFinished(
    ToolResult r, {
    bool full = false,
    bool outputShown = false,
  }) {
    final status = r.error != null
        ? _c('31', '✖ ${r.error}')
        : _c(
            r.isError ? '33' : '32',
            '→ exit ${r.exitCode ?? '?'} · ${r.duration.inMilliseconds} ms',
          );
    stdout.writeln('  $status');
    if (r.note != null) stdout.writeln(_c('33', '  ℹ ${r.note}'));
    if (outputShown) return;
    final lines = '${r.stdout}${r.stderr.isEmpty ? '' : '\n${r.stderr}'}'
        .trimRight()
        .split('\n');
    final shown = full ? lines : lines.take(15).toList();
    for (final line in shown) {
      if (line.isNotEmpty || shown.length > 1) {
        stdout.writeln(_c('2', '  │ $line'));
      }
    }
    if (shown.length < lines.length) {
      stdout.writeln(
        _c('2', '  │ ... (${lines.length - shown.length} dalších řádků)'),
      );
    }
  }
}
