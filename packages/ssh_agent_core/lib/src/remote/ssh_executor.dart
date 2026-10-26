import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'connection_profile.dart';
import 'remote_executor.dart';

/// Decides whether a host key is trusted. [fingerprint] has the OpenSSH
/// format `SHA256:<base64>` (same as `ssh-keygen -lf`).
typedef HostKeyVerifier =
    FutureOr<bool> Function(String keyType, String fingerprint);

/// [RemoteExecutor] implemented with the pure Dart `dartssh2` library, so it
/// runs unchanged on Windows, Linux, macOS, Android and iOS.
///
/// One TCP/SSH connection is kept open per profile and every command runs in
/// its own `exec` channel.
class SshExecutor implements RemoteExecutor {
  SshExecutor({
    required this.profile,
    required this.secrets,
    required this.verifyHostKey,
    this.connectTimeout = const Duration(seconds: 15),
  });

  final ConnectionProfile profile;
  final ProfileSecrets secrets;
  final HostKeyVerifier verifyHostKey;
  final Duration connectTimeout;

  SSHClient? _client;
  Future<SSHClient>? _connecting;

  @override
  String get label => profile.label;

  @override
  String get username => profile.username;

  @override
  String get host => profile.host;

  @override
  bool get isConnected => _client != null && !_client!.isClosed;

  @override
  Future<void> connect() => _ensureClient();

  Future<SSHClient> _ensureClient() {
    final client = _client;
    if (client != null && !client.isClosed) return Future.value(client);
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<List<SSHKeyPair>> _loadIdentities() async {
    if (profile.authMethod != SshAuthMethod.privateKey) return const [];
    var pem = secrets.privateKey;
    final keyPath = profile.privateKeyPath;
    if ((pem == null || pem.trim().isEmpty) &&
        keyPath != null &&
        keyPath.isNotEmpty) {
      final file = File(expandLocalHome(keyPath));
      if (!await file.exists()) {
        throw RemoteConnectionException(
          'Soubor s privátním klíčem neexistuje: ${file.path}',
        );
      }
      pem = await file.readAsString();
    }
    if (pem == null || pem.trim().isEmpty) {
      throw RemoteConnectionException(
        'Profil nemá nastavený privátní klíč (vložte ho nebo zadejte cestu k souboru).',
      );
    }
    if (pem.contains('PuTTY-User-Key-File')) {
      throw RemoteConnectionException(
        'Klíč je ve formátu PuTTY (.ppk). Převeďte ho v PuTTYgen přes '
        'Conversions → Export OpenSSH key.',
      );
    }
    try {
      if (SSHKeyPair.isEncryptedPem(pem) &&
          (secrets.passphrase == null || secrets.passphrase!.isEmpty)) {
        throw RemoteConnectionException(
          'Privátní klíč je zašifrovaný - zadejte heslo ke klíči (passphrase).',
        );
      }
      return SSHKeyPair.fromPem(pem, secrets.passphrase);
    } on RemoteConnectionException {
      rethrow;
    } catch (e) {
      throw RemoteConnectionException(
        'Privátní klíč nelze načíst: $e',
        cause: e,
      );
    }
  }

  Future<SSHClient> _open() async {
    final identities = await _loadIdentities();
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: connectTimeout,
      );
    } catch (e) {
      throw RemoteConnectionException(
        'Nelze se připojit k ${profile.host}:${profile.port} ($e)',
        cause: e,
      );
    }

    String? rejectedKey;
    final password = secrets.password;
    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: password == null ? null : () => password,
      onUserInfoRequest: password == null
          ? null
          : (request) => [for (final _ in request.prompts) password],
      onVerifyHostKey: (type, fingerprintBytes) async {
        final fingerprint = utf8.decode(fingerprintBytes);
        final ok = await verifyHostKey(type, fingerprint);
        if (!ok) rejectedKey = '$type $fingerprint';
        return ok;
      },
      keepAliveInterval: const Duration(seconds: 20),
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 30),
      ident: 'SSHAgent_1.0',
    );

    try {
      await client.authenticated;
    } on SSHAuthFailError catch (e) {
      client.close();
      throw RemoteConnectionException(
        'Přihlášení jako ${profile.username} selhalo (${e.message}). '
        'Zkontrolujte jméno, heslo nebo klíč.',
        cause: e,
      );
    } catch (e) {
      client.close();
      if (rejectedKey != null) {
        throw RemoteConnectionException(
          'Klíč serveru nebyl potvrzen ($rejectedKey). Připojení bylo '
          'přerušeno.',
          cause: e,
        );
      }
      throw RemoteConnectionException('SSH spojení selhalo: $e', cause: e);
    }
    _client = client;
    return client;
  }

  static final RegExp _passwordPrompt = RegExp(
    r'(?:[Pp]assword|[Hh]eslo|[Pp]asswort|[Cc]ontrase)[^\n]*:\s*$',
  );

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
    final stopwatch = Stopwatch()..start();
    SSHSession session;
    try {
      session = await _openSession(command, pty);
    } on RemoteConnectionException {
      rethrow;
    } catch (_) {
      // The connection may have died silently (sleep, network change...).
      // Reconnect once and try again.
      _client?.close();
      _client = null;
      try {
        session = await _openSession(command, pty);
      } on RemoteConnectionException {
        rethrow;
      } catch (e) {
        throw RemoteConnectionException('Příkaz nelze spustit: $e', cause: e);
      }
    }

    final stdout = _LimitedBuffer(maxOutputBytes);
    final stderr = _LimitedBuffer(maxOutputBytes);
    var timedOut = false;
    var passwordSent = false;

    /// Stops the remote command: closing the channel alone waits for the
    /// process, so it is killed first (OpenSSH 7.9+ honours signals).
    void abort() {
      try {
        session.kill(SSHSignal.KILL);
      } catch (_) {}
      session.close();
    }

    void stopIfFull() {
      if (stdout.full && stderr.full) abort();
    }

    // Live output: decoded incrementally (multi-byte characters may be split
    // between packets) and only up to the output limit.
    final liveOut = onOutput == null
        ? null
        : _LiveDecoder((text) => onOutput(_liveText(text), false));
    final liveErr = onOutput == null
        ? null
        : _LiveDecoder((text) => onOutput(_liveText(text), true));

    final outDone = Completer<void>();
    final errDone = Completer<void>();
    session.stdout.listen(
      (data) {
        if (!stdout.full) liveOut?.add(data);
        stdout.add(data);
        if (pty &&
            !passwordSent &&
            _passwordPrompt.hasMatch(stdout.tailText(200))) {
          passwordSent = true;
          if (promptPassword == null) {
            // Nothing to type - fail fast instead of waiting for the timeout.
            stderr.add(
              Uint8List.fromList(
                utf8.encode(
                  'A password is required but none is configured in the server profile.\n',
                ),
              ),
            );
            abort();
          } else {
            session.write(Uint8List.fromList(utf8.encode('$promptPassword\n')));
          }
        }
        if (stdout.full) abort();
      },
      onDone: () => outDone.complete(),
      onError: (_) => outDone.isCompleted ? null : outDone.complete(),
    );
    session.stderr.listen(
      (data) {
        if (!stderr.full) liveErr?.add(data);
        stderr.add(data);
        stopIfFull();
      },
      onDone: () => errDone.complete(),
      onError: (_) => errDone.isCompleted ? null : errDone.complete(),
    );

    if (!pty) {
      if (stdinData != null) {
        session.write(Uint8List.fromList(utf8.encode(stdinData)));
      }
      // Always send EOF so that nothing can block waiting for input.
      unawaited(session.stdin.close().catchError((_) {}));
    }

    final timer = Timer(timeout, () {
      timedOut = true;
      abort();
    });

    try {
      await Future.wait([
        outDone.future,
        errDone.future,
        session.done,
      ]).timeout(timeout + const Duration(seconds: 10));
    } on TimeoutException {
      timedOut = true;
      session.close();
    } catch (_) {
      // Channel closed with an error - whatever was collected is returned.
    } finally {
      timer.cancel();
      liveOut?.close();
      liveErr?.close();
    }
    final exitCode = await session.waitForExit(
      timeout: const Duration(milliseconds: 500),
    );
    stopwatch.stop();

    var outText = stdout.text;
    var errText = stderr.text;
    if (pty) {
      outText = _cleanPtyOutput(outText, removePrompt: passwordSent);
    }
    return CommandResult(
      stdout: stripAnsi(outText),
      stderr: stripAnsi(errText),
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      timedOut: timedOut,
      truncated: stdout.truncated || stderr.truncated,
    );
  }

  static String _liveText(String text) => stripAnsi(text).replaceAll('\r', '');

  Future<SSHSession> _openSession(String command, bool pty) async {
    final client = await _ensureClient();
    return client.execute(
      command,
      pty: pty
          ? const SSHPtyConfig(type: 'dumb', width: 400, height: 50)
          : null,
    );
  }

  static String _cleanPtyOutput(String text, {required bool removePrompt}) {
    var result = text.replaceAll('\r\n', '\n').replaceAll('\r', '');
    if (removePrompt) {
      final match = RegExp(r'^[^\n]*:[ \t]*\n?').firstMatch(result);
      if (match != null &&
          _passwordPrompt.hasMatch('${match.group(0)!.trimRight()} ')) {
        result = result.substring(match.end);
      }
    }
    return result;
  }

  @override
  Future<void> close() async {
    final client = _client;
    _client = null;
    if (client != null) {
      client.close();
      try {
        await client.done.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }
}

/// Expands a leading `~` in a path on the local computer (Windows
/// `%USERPROFILE%`, otherwise `$HOME`).
String expandLocalHome(String path) {
  if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return home + path.substring(1);
  }
  return path;
}

final RegExp _ansi = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

/// Removes terminal colour/control escape sequences.
String stripAnsi(String text) =>
    text.contains('\x1B') ? text.replaceAll(_ansi, '') : text;

class _LimitedBuffer {
  _LimitedBuffer(this.limit);

  final int limit;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  bool truncated = false;

  bool get full => _bytes.length >= limit;

  void add(Uint8List data) {
    final room = limit - _bytes.length;
    if (room <= 0) {
      truncated = true;
      return;
    }
    if (data.length > room) {
      _bytes.add(Uint8List.sublistView(data, 0, room));
      truncated = true;
    } else {
      _bytes.add(data);
    }
  }

  String tailText(int bytes) {
    final all = _bytes.toBytes();
    final start = all.length > bytes ? all.length - bytes : 0;
    return utf8.decode(Uint8List.sublistView(all, start), allowMalformed: true);
  }

  String get text => utf8.decode(_bytes.toBytes(), allowMalformed: true);
}

/// Incremental UTF-8 decoder feeding a callback.
class _LiveDecoder {
  _LiveDecoder(void Function(String text) onText)
    : _sink = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(_CallbackSink(onText));

  final ByteConversionSink _sink;

  void add(Uint8List data) => _sink.add(data);

  void close() => _sink.close();
}

class _CallbackSink implements Sink<String> {
  _CallbackSink(this.onText);

  final void Function(String text) onText;

  @override
  void add(String data) {
    if (data.isNotEmpty) onText(data);
  }

  @override
  void close() {}
}
