import '../llm/chat_message.dart';
import 'agent_event.dart';

/// A saved chat. Plain data with JSON (de)serialisation - the app stores it
/// on disk, the history for the model is rebuilt from it.
class Conversation {
  Conversation({
    required this.id,
    this.title = 'Nová konverzace',
    this.profileId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatTurn>? turns,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       turns = turns ?? [];

  final String id;
  String title;

  /// Server profile used by this chat (can be switched any time).
  String? profileId;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatTurn> turns;

  bool get isEmpty => turns.isEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'profileId': profileId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'turns': [for (final t in turns) t.toJson()],
  };

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Konverzace',
    profileId: json['profileId'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    turns: [
      for (final t in (json['turns'] as List?) ?? const [])
        if (t is Map) ChatTurn.fromJson(Map<String, Object?>.from(t)),
    ],
  );

  /// Messages for the model (without system prompt), shortened to roughly
  /// [maxChars] characters: older tool outputs are cut first, then the
  /// oldest turns are dropped. The newest turn is always kept whole.
  List<ChatMessage> toHistory({int maxChars = 60000}) {
    final perTurn = <List<ChatMessage>>[];
    for (final turn in turns) {
      if (turn is UserTurn) {
        perTurn.add([ChatMessage.user(turn.text)]);
      } else if (turn is AgentTurn) {
        final messages = turn.toMessages();
        if (messages.isNotEmpty) perTurn.add(messages);
      }
    }
    int size(List<List<ChatMessage>> groups) => groups.fold(
      0,
      (sum, g) =>
          sum +
          g.fold(0, (s, m) => s + m.content.length + m.toolCalls.length * 80),
    );

    // 1) Shorten tool outputs of all but the last two groups.
    for (var i = 0; i < perTurn.length - 2 && size(perTurn) > maxChars; i++) {
      perTurn[i] = [
        for (final m in perTurn[i])
          m.role == ChatRole.tool && m.content.length > 400
              ? m.copyWith(
                  content:
                      '${m.content.substring(0, 400)}\n'
                      '[... older output shortened ...]',
                )
              : m,
      ];
    }
    // 2) Drop the oldest turns.
    while (perTurn.length > 2 && size(perTurn) > maxChars) {
      perTurn.removeAt(0);
    }
    // History must not start with an orphaned assistant/tool message.
    while (perTurn.isNotEmpty && perTurn.first.first.role != ChatRole.user) {
      perTurn.removeAt(0);
    }
    return [for (final g in perTurn) ...g];
  }
}

sealed class ChatTurn {
  ChatTurn({DateTime? at}) : at = at ?? DateTime.now();

  final DateTime at;

  Map<String, Object?> toJson();

  factory ChatTurn.fromJson(Map<String, Object?> json) => json['type'] == 'user'
      ? UserTurn.fromJson(json)
      : AgentTurn.fromJson(json);
}

class UserTurn extends ChatTurn {
  UserTurn(this.text, {super.at});

  final String text;

  @override
  Map<String, Object?> toJson() => {
    'type': 'user',
    'text': text,
    'at': at.toIso8601String(),
  };

  factory UserTurn.fromJson(Map<String, Object?> json) => UserTurn(
    json['text'] as String? ?? '',
    at: DateTime.tryParse(json['at'] as String? ?? ''),
  );
}

enum AgentTurnStatus { running, done, error, cancelled }

/// What the agent is doing right now (shown live, not saved).
enum AgentPhase {
  /// Opening the SSH connection.
  connecting,

  /// Request sent, the model has not produced anything yet (loading the
  /// model, reading the prompt).
  waitingForModel,

  /// The model streams its reasoning.
  thinking,

  /// The model streams the answer text.
  writing,

  /// A command runs on the server.
  runningTool,

  /// A tool finished, its result goes back to the model.
  processing,

  /// Nothing (finished).
  idle,
}

/// The agent's answer to one user message: possibly several steps, each
/// with reasoning, text and tool calls.
class AgentTurn extends ChatTurn {
  AgentTurn({
    super.at,
    List<AgentStepRecord>? steps,
    this.status = AgentTurnStatus.running,
    this.error,
    this.model,
    this.server,
    List<String>? notices,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.connectMs,
  }) : steps = steps ?? [],
       notices = notices ?? [];

  final List<AgentStepRecord> steps;
  AgentTurnStatus status;
  String? error;
  String? model;
  String? server;
  final List<String> notices;
  int promptTokens;
  int completionTokens;

  /// How long opening the SSH connection took (null = already connected).
  int? connectMs;

  /// Live state for the UI (not saved).
  AgentPhase phase = AgentPhase.waitingForModel;
  DateTime phaseSince = DateTime.now();

  /// E.g. the server name or the running tool.
  String? phaseDetail;

  bool get isRunning => status == AgentTurnStatus.running;

  void _setPhase(AgentPhase value, [String? detail]) {
    if (value == phase && detail == phaseDetail) return;
    phase = value;
    phaseDetail = detail;
    phaseSince = DateTime.now();
  }

  Iterable<ToolInvocation> get toolCalls => steps.expand((s) => s.tools);

  /// The final answer (text of the last step that has text).
  String get answer {
    for (final step in steps.reversed) {
      if (step.text.trim().isNotEmpty) return step.text;
    }
    return '';
  }

  AgentStepRecord get _current {
    if (steps.isEmpty) steps.add(AgentStepRecord());
    return steps.last;
  }

  /// Updates the record with an event coming from [Agent.run].
  void apply(AgentEvent event) {
    switch (event) {
      case AgentConnecting(:final server):
        _setPhase(AgentPhase.connecting, server);
      case AgentConnected(:final duration):
        connectMs = duration.inMilliseconds;
        _setPhase(AgentPhase.waitingForModel);
      case AgentStepStarted(:final retry, :final approxPromptTokens):
        if (retry && steps.isNotEmpty && steps.last.tools.isEmpty) {
          steps.last
            ..text = ''
            ..thinking = ''
            ..retries += 1;
        } else if (steps.isEmpty ||
            steps.last.tools.isNotEmpty ||
            steps.last.text.isNotEmpty ||
            steps.last.thinking.isNotEmpty) {
          steps.add(AgentStepRecord());
        }
        steps.last
          ..startedAt = DateTime.now()
          ..approxPromptTokens = approxPromptTokens;
        _setPhase(AgentPhase.waitingForModel, '${steps.length}');
      case AgentThinkingDelta(:final text):
        _current.thinking += text;
        _setPhase(AgentPhase.thinking);
      case AgentTextDelta(:final text):
        _current.text += text;
        _setPhase(AgentPhase.writing);
      case AgentAssistantMessage(
        :final content,
        :final thinking,
        :final usage,
        :final elapsed,
        :final toolCalls,
      ):
        _current
          ..text = content
          ..thinking = thinking
          ..modelMs = elapsed?.inMilliseconds
          ..promptTokens = usage?.promptTokens
          ..completionTokens = usage?.completionTokens
          ..loadMs = usage?.loadDuration?.inMilliseconds
          ..promptEvalMs = usage?.promptDuration?.inMilliseconds;
        promptTokens += usage?.promptTokens ?? 0;
        completionTokens += usage?.completionTokens ?? 0;
        if (toolCalls.isNotEmpty) _setPhase(AgentPhase.processing);
      case AgentToolCallStarted():
        _setPhase(AgentPhase.runningTool, event.name);
        _current.tools.add(
          ToolInvocation(
            id: event.callId,
            name: event.name,
            arguments: Map.of(event.arguments),
            server: event.server,
            script: event.script,
            fullCommand: event.fullCommand,
            runAs: event.runAs,
            cwd: event.cwd,
          )..startedAt = DateTime.now(),
        );
      case AgentToolOutput(:final callId, :final text, :final isStderr):
        toolCalls
            .where((t) => t.id == callId)
            .lastOrNull
            ?.addLiveOutput(text, isStderr: isStderr);
      case AgentToolCallFinished(
        :final callId,
        :final result,
        :final modelText,
      ):
        final call = toolCalls.where((t) => t.id == callId).lastOrNull;
        if (call == null) return;
        call
          ..status = result.isError ? ToolStatus.failed : ToolStatus.done
          ..stdout = result.stdout
          ..stderr = result.stderr
          ..exitCode = result.exitCode
          ..durationMs = result.duration.inMilliseconds
          ..timedOut = result.timedOut
          ..truncated = result.truncated
          ..error = result.error
          ..note = result.note
          ..modelText = modelText;
        _setPhase(AgentPhase.processing);
      case AgentNotice(:final message):
        notices.add(message);
      case AgentCompleted():
        status = AgentTurnStatus.done;
        _setPhase(AgentPhase.idle);
      case AgentFailed(:final message):
        status = AgentTurnStatus.error;
        error = message;
        _finishRunningTools();
        _setPhase(AgentPhase.idle);
      case AgentCancelled():
        status = AgentTurnStatus.cancelled;
        _finishRunningTools();
        _setPhase(AgentPhase.idle);
    }
  }

  void _finishRunningTools() {
    for (final call in toolCalls) {
      if (call.status == ToolStatus.running) {
        call
          ..status = ToolStatus.failed
          ..error = 'Přerušeno.'
          ..modelText = '[error] Cancelled by the user.';
      }
    }
  }

  /// Messages for the model history.
  List<ChatMessage> toMessages() {
    final out = <ChatMessage>[];
    for (final step in steps) {
      if (step.tools.isEmpty && step.text.trim().isEmpty) continue;
      out.add(
        ChatMessage.assistant(
          step.text,
          toolCalls: [
            for (final t in step.tools)
              ToolCall(id: t.id, name: t.name, arguments: t.arguments),
          ],
        ),
      );
      for (final t in step.tools) {
        out.add(
          ChatMessage.tool(
            t.modelText ?? '[error] No result.',
            toolCallId: t.id,
            toolName: t.name,
          ),
        );
      }
    }
    if (out.isNotEmpty && out.last.role == ChatRole.tool) {
      // Interrupted turn: close it so that the history stays valid.
      out.add(
        ChatMessage.assistant(
          status == AgentTurnStatus.cancelled
              ? '(The user stopped this answer.)'
              : '(This answer was not finished${error == null ? '' : ': $error'}.)',
        ),
      );
    }
    return out;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'agent',
    'at': at.toIso8601String(),
    'status': status.name,
    'error': error,
    'model': model,
    'server': server,
    'notices': notices,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'connectMs': connectMs,
    'steps': [for (final s in steps) s.toJson()],
  };

  factory AgentTurn.fromJson(Map<String, Object?> json) {
    var status = AgentTurnStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => AgentTurnStatus.done,
    );
    // A turn saved while running was interrupted by closing the app.
    final interrupted = status == AgentTurnStatus.running;
    if (interrupted) status = AgentTurnStatus.cancelled;
    final turn = AgentTurn(
      at: DateTime.tryParse(json['at'] as String? ?? ''),
      status: status,
      error: json['error'] as String?,
      model: json['model'] as String?,
      server: json['server'] as String?,
      notices: [
        for (final n in (json['notices'] as List?) ?? const [])
          if (n is String) n,
      ],
      promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
      completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
      connectMs: (json['connectMs'] as num?)?.toInt(),
      steps: [
        for (final s in (json['steps'] as List?) ?? const [])
          if (s is Map) AgentStepRecord.fromJson(Map<String, Object?>.from(s)),
      ],
    );
    if (interrupted) turn._finishRunningTools();
    turn.phase = AgentPhase.idle;
    return turn;
  }
}

/// One model call and the tools it requested.
class AgentStepRecord {
  AgentStepRecord({
    this.thinking = '',
    this.text = '',
    List<ToolInvocation>? tools,
    this.startedAt,
    this.modelMs,
    this.approxPromptTokens,
    this.promptTokens,
    this.completionTokens,
    this.loadMs,
    this.promptEvalMs,
    this.retries = 0,
  }) : tools = tools ?? [];

  String thinking;
  String text;
  final List<ToolInvocation> tools;

  /// When the request was sent to the model.
  DateTime? startedAt;

  /// How long the model call took (null while it runs).
  int? modelMs;
  int? approxPromptTokens;
  int? promptTokens;
  int? completionTokens;

  /// Loading the model into memory / reading the prompt (Ollama).
  int? loadMs;
  int? promptEvalMs;
  int retries;

  Map<String, Object?> toJson() => {
    'thinking': thinking,
    'text': text,
    'tools': [for (final t in tools) t.toJson()],
    'startedAt': startedAt?.toIso8601String(),
    'modelMs': modelMs,
    'approxPromptTokens': approxPromptTokens,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'loadMs': loadMs,
    'promptEvalMs': promptEvalMs,
    'retries': retries,
  };

  factory AgentStepRecord.fromJson(Map<String, Object?> json) {
    int? number(String key) => (json[key] as num?)?.toInt();
    return AgentStepRecord(
      thinking: json['thinking'] as String? ?? '',
      text: json['text'] as String? ?? '',
      tools: [
        for (final t in (json['tools'] as List?) ?? const [])
          if (t is Map) ToolInvocation.fromJson(Map<String, Object?>.from(t)),
      ],
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      modelMs: number('modelMs'),
      approxPromptTokens: number('approxPromptTokens'),
      promptTokens: number('promptTokens'),
      completionTokens: number('completionTokens'),
      loadMs: number('loadMs'),
      promptEvalMs: number('promptEvalMs'),
      retries: number('retries') ?? 0,
    );
  }
}

enum ToolStatus { running, done, failed }

/// One executed tool call as shown to the user.
class ToolInvocation {
  ToolInvocation({
    required this.id,
    required this.name,
    required this.arguments,
    required this.server,
    this.script,
    this.fullCommand,
    this.runAs,
    this.cwd,
    this.status = ToolStatus.running,
    this.stdout = '',
    this.stderr = '',
    this.exitCode,
    this.durationMs = 0,
    this.timedOut = false,
    this.truncated = false,
    this.error,
    this.note,
    this.modelText,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
  final String server;
  final String? script;
  final String? fullCommand;
  final String? runAs;
  final String? cwd;
  ToolStatus status;
  String stdout;
  String stderr;
  int? exitCode;
  int durationMs;
  bool timedOut;
  bool truncated;
  String? error;
  String? note;
  String? modelText;

  /// Live state while the command runs (not saved).
  DateTime? startedAt;

  /// The end of the output received so far (at most [liveTailChars]).
  String liveStdout = '';
  String liveStderr = '';
  int liveBytes = 0;
  int liveLines = 0;

  static const int liveTailChars = 16000;

  void addLiveOutput(String text, {bool isStderr = false}) {
    liveBytes += text.length;
    liveLines += '\n'.allMatches(text).length;
    String append(String current) {
      final joined = current + text;
      return joined.length <= liveTailChars
          ? joined
          : joined.substring(joined.length - liveTailChars);
    }

    if (isStderr) {
      liveStderr = append(liveStderr);
    } else {
      liveStdout = append(liveStdout);
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    'server': server,
    'script': script,
    'fullCommand': fullCommand,
    'runAs': runAs,
    'cwd': cwd,
    'status': status.name,
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'durationMs': durationMs,
    'timedOut': timedOut,
    'truncated': truncated,
    'error': error,
    'note': note,
    'modelText': modelText,
  };

  factory ToolInvocation.fromJson(Map<String, Object?> json) => ToolInvocation(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    arguments: Map<String, Object?>.from(
      (json['arguments'] as Map?) ?? const <String, Object?>{},
    ),
    server: json['server'] as String? ?? '',
    script: json['script'] as String?,
    fullCommand: json['fullCommand'] as String?,
    runAs: json['runAs'] as String?,
    cwd: json['cwd'] as String?,
    status: ToolStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => ToolStatus.failed,
    ),
    stdout: json['stdout'] as String? ?? '',
    stderr: json['stderr'] as String? ?? '',
    exitCode: (json['exitCode'] as num?)?.toInt(),
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    timedOut: json['timedOut'] as bool? ?? false,
    truncated: json['truncated'] as bool? ?? false,
    error: json['error'] as String?,
    note: json['note'] as String?,
    modelText: json['modelText'] as String?,
  );
}
