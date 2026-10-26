import 'package:ssh_agent_core/ssh_agent_core.dart';

/// Executor that records commands and answers from a callback.
class FakeExecutor implements RemoteExecutor {
  FakeExecutor({this.respond});

  final CommandResult Function(String command)? respond;
  final List<String> commands = [];

  @override
  String get label => 'test (agent@example.org)';

  @override
  String get username => 'agent';

  @override
  String get host => 'example.org';

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> close() async {}

  @override
  Future<CommandResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 512 * 1024,
    String? stdinData,
    bool pty = false,
    String? promptPassword,
    OutputListener? onOutput,
  }) async {
    commands.add(command);
    final result =
        respond?.call(command) ??
        const CommandResult(
          stdout: 'fake output\n',
          stderr: '',
          exitCode: 0,
          duration: Duration(milliseconds: 5),
        );
    // Deliver the output live in two pieces, like a real server.
    if (onOutput != null && result.stdout.isNotEmpty) {
      final half = result.stdout.length ~/ 2;
      onOutput(result.stdout.substring(0, half), false);
      onOutput(result.stdout.substring(half), false);
    }
    return result;
  }
}

/// Model that returns prepared responses in order.
class ScriptedLlm implements LlmClient {
  ScriptedLlm(this.responses);

  final List<LlmResponse> responses;
  final List<List<ChatMessage>> requests = [];
  final List<List<Map<String, Object?>>> toolLists = [];

  @override
  LlmConfig get config => const LlmConfig(model: 'scripted');

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required List<Map<String, Object?>> tools,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  }) async {
    requests.add(List.of(messages));
    toolLists.add(tools);
    if (responses.isEmpty) {
      return const LlmResponse(content: 'Hotovo.');
    }
    final response = responses.removeAt(0);
    if (response.thinking.isNotEmpty) {
      onDelta?.call(LlmDelta.thinking(response.thinking));
    }
    if (response.content.isNotEmpty) {
      onDelta?.call(LlmDelta.text(response.content));
    }
    return response;
  }

  @override
  Future<List<String>> listModels() async => ['scripted'];

  @override
  Future<ModelInfo?> modelInfo() async => null;

  int warmUps = 0;

  @override
  Future<void> warmUp() async => warmUps++;
}

LlmResponse callTool(
  String name,
  Map<String, Object?> args, {
  String id = 'c1',
}) => LlmResponse(
  content: '',
  toolCalls: [ToolCall(id: id, name: name, arguments: args)],
);
