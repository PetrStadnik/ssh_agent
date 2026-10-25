import 'package:ssh_agent/state/app_state.dart';
import 'package:ssh_agent/state/storage.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

class FakeExecutor implements RemoteExecutor {
  FakeExecutor(this.profile);

  final ConnectionProfile profile;
  final List<String> commands = [];
  bool connected = false;

  @override
  String get label => profile.label;

  @override
  String get username => profile.username;

  @override
  String get host => profile.host;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> close() async => connected = false;

  @override
  Future<CommandResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 512 * 1024,
    String? stdinData,
    bool pty = false,
    String? promptPassword,
  }) async {
    commands.add(command);
    return const CommandResult(
      stdout:
          '  File: /etc/passwd\n'
          '  Size: 3465      \tBlocks: 8          IO Block: 4096   regular file\n'
          'Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)\n'
          'Modify: 2026-10-24 22:13:05.565238411 +0200\n'
          'Change: 2026-10-24 22:13:05.565238411 +0200\n',
      stderr: '',
      exitCode: 0,
      duration: Duration(milliseconds: 38),
    );
  }
}

class ScriptedLlm implements LlmClient {
  ScriptedLlm(this.responses);

  final List<LlmResponse> responses;

  @override
  LlmConfig get config => const LlmConfig();

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required List<Map<String, Object?>> tools,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  }) async {
    final r = responses.isEmpty
        ? const LlmResponse(content: 'Hotovo.')
        : responses.removeAt(0);
    if (r.content.isNotEmpty) onDelta?.call(LlmDelta.text(r.content));
    return r;
  }

  @override
  Future<List<String>> listModels() async => ['qwen3.5:9b'];

  @override
  Future<ModelInfo?> modelInfo() async => const ModelInfo(
    capabilities: ['tools', 'thinking'],
    contextLength: 262144,
  );
}

ConnectionProfile sampleProfile({String id = 'p1', String name = 'web-prod'}) =>
    ConnectionProfile(
      id: id,
      name: name,
      host: '203.0.113.10',
      username: 'admin',
      elevation: ElevationMethod.sudo,
      hostKeyFingerprint: 'SHA256:E76a4/Q8tR8dL/VXq9ok24zzvazx8uWl+2fWRTSf2qY',
      hostKeyType: 'ssh-ed25519',
    );

Future<AppState> createState({
  List<ConnectionProfile> profiles = const [],
  List<Conversation> conversations = const [],
  List<LlmResponse>? responses,
  List<FakeExecutor>? executors,
}) async {
  final storage = MemoryAppStorage();
  storage.files['profiles.json'] = {
    'default': profiles.isEmpty ? null : profiles.first.id,
    'profiles': [for (final p in profiles) p.toJson()],
  };
  for (final c in conversations) {
    storage.conversations[c.id] = c;
  }
  final state = AppState(
    storage,
    executorFactory: (profile, secrets, verify) {
      final executor = FakeExecutor(profile);
      executors?.add(executor);
      return executor;
    },
    llmFactory: (_) => ScriptedLlm(responses ?? []),
  );
  await state.load();
  return state;
}
