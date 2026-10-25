import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

/// Persistence of settings, server profiles, conversations and secrets.
abstract class AppStorage {
  Future<Map<String, Object?>?> readJson(String name);
  Future<void> writeJson(String name, Object json);

  Future<List<Conversation>> loadConversations();
  Future<void> saveConversation(Conversation conversation);
  Future<void> deleteConversation(String id);

  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String? value);

  /// Where the data lives (shown in settings).
  String get location;

  /// False when secrets cannot be stored permanently.
  bool get secureStorageAvailable => true;

  Future<ProfileSecrets> readProfileSecrets(String profileId) async =>
      ProfileSecrets.fromMap({
        for (final field in _secretFields)
          field: await readSecret('profile.$profileId.$field'),
      });

  Future<void> writeProfileSecrets(
    String profileId,
    ProfileSecrets secrets,
  ) async {
    final map = secrets.toMap();
    for (final field in _secretFields) {
      await writeSecret('profile.$profileId.$field', map[field]);
    }
  }

  Future<void> deleteProfileSecrets(String profileId) async {
    for (final field in _secretFields) {
      await writeSecret('profile.$profileId.$field', null);
    }
  }

  static const _secretFields = [
    'password',
    'privateKey',
    'passphrase',
    'elevationPassword',
  ];
}

/// JSON files in the application support directory + OS key store
/// (Windows Credential Manager / DPAPI, Android Keystore, iOS/macOS
/// Keychain, libsecret on Linux) for secrets.
class FileAppStorage extends AppStorage {
  FileAppStorage._(this._dir, this._secure);

  final Directory _dir;
  final FlutterSecureStorage _secure;

  static Future<FileAppStorage> open() async {
    final dir = await getApplicationSupportDirectory();
    await Directory('${dir.path}/conversations').create(recursive: true);
    return FileAppStorage._(dir, const FlutterSecureStorage());
  }

  @override
  String get location => _dir.path;

  File _file(String name) => File('${_dir.path}/$name');

  @override
  Future<Map<String, Object?>?> readJson(String name) async {
    final file = _file(name);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeJson(String name, Object json) async {
    final file = _file(name);
    await file.parent.create(recursive: true);
    // Write to a temporary file first so that a crash never leaves a
    // half-written file behind.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert(json),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  @override
  Future<List<Conversation>> loadConversations() async {
    final dir = Directory('${_dir.path}/conversations');
    final result = <Conversation>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entry.readAsString());
        if (json is Map) {
          result.add(Conversation.fromJson(Map<String, Object?>.from(json)));
        }
      } catch (_) {
        // Skip damaged files.
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> saveConversation(Conversation conversation) =>
      writeJson('conversations/${conversation.id}.json', conversation.toJson());

  @override
  Future<void> deleteConversation(String id) async {
    final file = _file('conversations/$id.json');
    if (await file.exists()) await file.delete();
  }

  /// Used when the OS key store is not available (e.g. Linux without a
  /// keyring daemon): secrets then live only until the app is closed.
  final Map<String, String> _volatile = {};

  @override
  bool get secureStorageAvailable => _secureOk;
  bool _secureOk = true;

  @override
  Future<String?> readSecret(String key) async {
    if (_volatile.containsKey(key)) return _volatile[key];
    try {
      return await _secure.read(key: key);
    } catch (_) {
      _secureOk = false;
      return null;
    }
  }

  @override
  Future<void> writeSecret(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        _volatile.remove(key);
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {
      _secureOk = false;
      if (value == null || value.isEmpty) {
        _volatile.remove(key);
      } else {
        _volatile[key] = value;
      }
    }
  }
}

/// In-memory storage for tests and for platforms without a file system.
class MemoryAppStorage extends AppStorage {
  final Map<String, Object> files = {};
  final Map<String, Conversation> conversations = {};
  final Map<String, String> secrets = {};

  @override
  String get location => '(paměť)';

  @override
  Future<Map<String, Object?>?> readJson(String name) async {
    final value = files[name];
    return value == null
        ? null
        : Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<void> writeJson(String name, Object json) async => files[name] = json;

  @override
  Future<List<Conversation>> loadConversations() async =>
      conversations.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> saveConversation(Conversation conversation) async =>
      conversations[conversation.id] = conversation;

  @override
  Future<void> deleteConversation(String id) async => conversations.remove(id);

  @override
  Future<String?> readSecret(String key) async => secrets[key];

  @override
  Future<void> writeSecret(String key, String? value) async {
    if (value == null || value.isEmpty) {
      secrets.remove(key);
    } else {
      secrets[key] = value;
    }
  }
}
