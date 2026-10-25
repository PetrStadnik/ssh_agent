import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import 'app_settings.dart';
import 'storage.dart';

/// Asked when a server presents a host key that is not trusted yet.
class HostKeyRequest {
  HostKeyRequest({
    required this.profile,
    required this.keyType,
    required this.fingerprint,
    this.knownFingerprint,
  });

  final ConnectionProfile profile;
  final String keyType;
  final String fingerprint;

  /// Previously trusted key - when set, the key CHANGED (possible attack).
  final String? knownFingerprint;

  bool get changed => knownFingerprint != null;
}

typedef HostKeyPrompter = Future<bool> Function(HostKeyRequest request);
typedef CommandApprover =
    Future<bool> Function(PreparedToolCall call, ConnectionProfile profile);
typedef ExecutorFactory =
    RemoteExecutor Function(
      ConnectionProfile profile,
      ProfileSecrets secrets,
      HostKeyVerifier verifyHostKey,
    );

/// Application state: settings, server profiles, conversations and running
/// agents. UI widgets listen to it through `provider`.
class AppState extends ChangeNotifier {
  AppState(
    this.storage, {
    ExecutorFactory? executorFactory,
    LlmClient Function(LlmConfig config)? llmFactory,
  }) : _executorFactory = executorFactory ?? _defaultExecutor,
       _llmFactory = llmFactory ?? createLlmClient;

  final AppStorage storage;
  final ExecutorFactory _executorFactory;
  final LlmClient Function(LlmConfig config) _llmFactory;

  AppSettings settings = AppSettings();
  final List<ConnectionProfile> profiles = [];
  final List<Conversation> conversations = [];
  bool loaded = false;

  /// Conversation shown in the chat view (null = new chat).
  String? activeConversationId;

  /// Server used for new chats.
  String? defaultProfileId;

  /// Set by the UI to show dialogs.
  HostKeyPrompter? hostKeyPrompter;
  CommandApprover? commandApprover;

  final Map<String, RemoteExecutor> _executors = {};
  final Map<String, RemoteSession> _sessions = {};
  final Map<String, CancelToken> _running = {};
  final Map<String, Timer> _saveTimers = {};
  Timer? _notifyTimer;

  static RemoteExecutor _defaultExecutor(
    ConnectionProfile profile,
    ProfileSecrets secrets,
    HostKeyVerifier verify,
  ) => SshExecutor(profile: profile, secrets: secrets, verifyHostKey: verify);

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    final settingsJson = await storage.readJson('settings.json');
    final apiKey = await storage.readSecret('llm.apiKey');
    settings = settingsJson == null
        ? AppSettings(llm: LlmConfig(apiKey: apiKey))
        : AppSettings.fromJson(settingsJson, apiKey: apiKey);
    final profilesJson = await storage.readJson('profiles.json');
    profiles
      ..clear()
      ..addAll([
        for (final p in (profilesJson?['profiles'] as List?) ?? const [])
          if (p is Map)
            ConnectionProfile.fromJson(Map<String, Object?>.from(p)),
      ]);
    defaultProfileId = profilesJson?['default'] as String?;
    conversations
      ..clear()
      ..addAll(await storage.loadConversations());
    loaded = true;
    notifyListeners();
  }

  Future<void> _saveProfiles() => storage.writeJson('profiles.json', {
    'default': defaultProfileId,
    'profiles': [for (final p in profiles) p.toJson()],
  });

  Future<void> _saveSettings() =>
      storage.writeJson('settings.json', settings.toJson());

  // ----------------------------------------------------------- conversations

  Conversation? get activeConversation =>
      conversations.where((c) => c.id == activeConversationId).firstOrNull;

  bool isRunning(String? conversationId) =>
      conversationId != null && _running.containsKey(conversationId);

  ConnectionProfile? profileById(String? id) =>
      profiles.where((p) => p.id == id).firstOrNull;

  /// Server of [conversation] (or of the new chat).
  ConnectionProfile? profileFor(Conversation? conversation) =>
      profileById(conversation?.profileId) ??
      profileById(defaultProfileId) ??
      profiles.firstOrNull;

  /// Agent state (working directory, user) on the server of a chat.
  RemoteSession? sessionFor(Conversation? conversation) {
    final profile = profileFor(conversation);
    if (conversation == null || profile == null) return null;
    return _sessions['${conversation.id}|${profile.id}'];
  }

  bool isConnected(String profileId) =>
      _executors[profileId]?.isConnected ?? false;

  void newConversation() {
    activeConversationId = null;
    notifyListeners();
  }

  void selectConversation(String id) {
    activeConversationId = id;
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    stop(id);
    _saveTimers.remove(id)?.cancel();
    conversations.removeWhere((c) => c.id == id);
    _sessions.removeWhere((key, _) => key.startsWith('$id|'));
    if (activeConversationId == id) activeConversationId = null;
    notifyListeners();
    await storage.deleteConversation(id);
  }

  Future<void> renameConversation(String id, String title) async {
    final conversation = conversations.where((c) => c.id == id).firstOrNull;
    if (conversation == null || title.trim().isEmpty) return;
    conversation.title = title.trim();
    notifyListeners();
    await storage.saveConversation(conversation);
  }

  /// Switches the server of the active chat (or of new chats).
  Future<void> selectProfile(String profileId) async {
    defaultProfileId = profileId;
    final conversation = activeConversation;
    if (conversation != null) {
      conversation.profileId = profileId;
      unawaited(storage.saveConversation(conversation));
    }
    notifyListeners();
    await _saveProfiles();
  }

  void stop(String? conversationId) {
    if (conversationId == null) return;
    _running[conversationId]?.cancel();
  }

  /// Sends a question to the agent in the active chat.
  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    final profile = profileFor(activeConversation);
    if (profile == null) return;
    var conversation = activeConversation;
    if (conversation == null) {
      conversation = Conversation(id: newId(), profileId: profile.id);
      conversations.insert(0, conversation);
      activeConversationId = conversation.id;
    }
    if (isRunning(conversation.id)) return;
    conversation.profileId = profile.id;

    final history = conversation.toHistory(maxChars: settings.historyChars);
    conversation.turns.add(UserTurn(text));
    if (conversation.turns.whereType<UserTurn>().length == 1) {
      conversation.title = _titleFrom(text);
    }
    final turn = AgentTurn(model: settings.llm.model, server: profile.name);
    conversation.turns.add(turn);
    conversation.updatedAt = DateTime.now();
    conversations
      ..remove(conversation)
      ..insert(0, conversation);
    final cancel = CancelToken();
    _running[conversation.id] = cancel;
    notifyListeners();

    try {
      final session = await _sessionFor(conversation, profile);
      cancel.throwIfCancelled();
      final agent = Agent(
        llm: _llmFactory(settings.llm),
        tools: ToolRegistry(enabledCategories: settings.enabledCategories),
        session: session,
        serverName: profile.name,
        config: AgentConfig(
          maxSteps: settings.maxSteps,
          maxToolOutputChars: settings.maxToolOutputChars,
          answerLanguage: settings.answerLanguage,
          extraInstructions: settings.extraInstructions,
        ),
        approver: settings.confirmCommands
            ? (call) =>
                  commandApprover?.call(call, profile) ?? Future.value(true)
            : null,
      );
      await for (final event in agent.run(
        history: history,
        userMessage: text,
        cancel: cancel,
      )) {
        turn.apply(event);
        _scheduleNotify();
        if (event is AgentToolCallFinished) _saveSoon(conversation);
      }
    } on RemoteConnectionException catch (e) {
      turn.apply(AgentFailed('SSH: ${e.message}'));
    } on CancelledException {
      turn.apply(const AgentCancelled());
    } catch (e) {
      turn.apply(AgentFailed('$e'));
    } finally {
      if (turn.isRunning) turn.apply(const AgentFailed('Přerušeno.'));
      _running.remove(conversation.id);
      conversation.updatedAt = DateTime.now();
      _saveTimers.remove(conversation.id)?.cancel();
      // The chat may have been deleted while the agent was running.
      if (conversations.contains(conversation)) {
        await storage.saveConversation(conversation);
      }
      _notifyTimer?.cancel();
      notifyListeners();
    }
  }

  Future<RemoteSession> _sessionFor(
    Conversation conversation,
    ConnectionProfile profile,
  ) async {
    final key = '${conversation.id}|${profile.id}';
    final executor = _executors[profile.id] ??= _executorFactory(
      profile,
      await storage.readProfileSecrets(profile.id),
      (type, fingerprint) => verifyHostKey(profile, type, fingerprint),
    );
    await executor.connect();
    final existing = _sessions[key];
    if (existing != null && identical(existing.executor, executor)) {
      return existing;
    }
    final secrets = await storage.readProfileSecrets(profile.id);
    return _sessions[key] = RemoteSession(
      executor: executor,
      elevation: profile.elevation,
      elevationPassword: secrets.elevationPassword,
      initialDirectory: profile.initialDirectory,
    );
  }

  /// Trust-on-first-use host key check. [persist] = store the accepted key
  /// in the saved profile.
  Future<bool> verifyHostKey(
    ConnectionProfile profile,
    String type,
    String fingerprint, {
    bool persist = true,
  }) async {
    if (profile.hostKeyFingerprint == fingerprint) return true;
    final prompter = hostKeyPrompter;
    if (prompter == null) return false;
    final accepted = await prompter(
      HostKeyRequest(
        profile: profile,
        keyType: type,
        fingerprint: fingerprint,
        knownFingerprint: profile.hostKeyFingerprint,
      ),
    );
    if (accepted) {
      profile
        ..hostKeyFingerprint = fingerprint
        ..hostKeyType = type;
      if (persist && profiles.contains(profile)) await _saveProfiles();
      notifyListeners();
    }
    return accepted;
  }

  void _scheduleNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 40), notifyListeners);
  }

  void _saveSoon(Conversation conversation) {
    _saveTimers[conversation.id]?.cancel();
    _saveTimers[conversation.id] = Timer(const Duration(milliseconds: 800), () {
      if (conversations.contains(conversation)) {
        storage.saveConversation(conversation);
      }
    });
  }

  // ---------------------------------------------------------------- profiles

  Future<ProfileSecrets> secretsFor(String profileId) =>
      storage.readProfileSecrets(profileId);

  Future<void> saveProfile(
    ConnectionProfile profile,
    ProfileSecrets secrets,
  ) async {
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    defaultProfileId ??= profile.id;
    await storage.writeProfileSecrets(profile.id, secrets);
    await disconnect(profile.id);
    notifyListeners();
    await _saveProfiles();
  }

  Future<void> deleteProfile(String profileId) async {
    await disconnect(profileId);
    profiles.removeWhere((p) => p.id == profileId);
    if (defaultProfileId == profileId) {
      defaultProfileId = profiles.firstOrNull?.id;
    }
    await storage.deleteProfileSecrets(profileId);
    notifyListeners();
    await _saveProfiles();
  }

  Future<void> disconnect(String profileId) async {
    final executor = _executors.remove(profileId);
    _sessions.removeWhere((key, _) => key.endsWith('|$profileId'));
    await executor?.close();
    notifyListeners();
  }

  /// Connects with a (possibly unsaved) profile and returns basic facts
  /// about the server. Throws [RemoteConnectionException] on failure.
  Future<String> testConnection(
    ConnectionProfile profile,
    ProfileSecrets secrets,
  ) async {
    final executor = _executorFactory(
      profile,
      secrets,
      (type, fp) => verifyHostKey(profile, type, fp, persist: false),
    );
    try {
      final result = await executor.execute(
        r'printf "%s@%s, %s\n" "$(whoami)" "$(hostname)" "$(uname -sr)"; '
        r'grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2',
        timeout: const Duration(seconds: 20),
      );
      return [
        result.stdout.trim(),
        result.stderr.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
    } finally {
      await executor.close();
    }
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings(
    void Function(AppSettings settings) change,
  ) async {
    change(settings);
    notifyListeners();
    await _saveSettings();
    await storage.writeSecret('llm.apiKey', settings.llm.apiKey);
  }

  LlmClient llmClient([LlmConfig? config]) =>
      _llmFactory(config ?? settings.llm);

  @override
  void dispose() {
    for (final token in _running.values) {
      token.cancel();
    }
    for (final executor in _executors.values) {
      executor.close();
    }
    _notifyTimer?.cancel();
    super.dispose();
  }

  static String _titleFrom(String text) {
    final line = text.split('\n').first.trim();
    return line.length <= 60 ? line : '${line.substring(0, 57)}...';
  }

  static final Random _random = Random();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 32).toRadixString(36)}';
}
