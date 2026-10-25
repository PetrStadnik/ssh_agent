import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chat_message.dart';
import 'llm_config.dart';
import 'ollama_client.dart';
import 'openai_client.dart';

/// Cooperative cancellation of a running request / agent run.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Registers [listener]; returns a function that unregisters it.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}

class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => 'Zrušeno uživatelem.';
}

/// Error reported by the model server (or the connection to it).
class LlmException implements Exception {
  LlmException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;

  /// Transient problems (server error, malformed tool call) worth a retry.
  final bool retryable;

  @override
  String toString() => message;
}

/// Capabilities reported by the server for a model.
class ModelInfo {
  const ModelInfo({this.capabilities = const [], this.contextLength});

  final List<String> capabilities;
  final int? contextLength;

  bool get supportsTools => capabilities.contains('tools');
  bool get supportsThinking => capabilities.contains('thinking');
}

/// A chat model with function calling.
abstract class LlmClient {
  LlmConfig get config;

  /// Sends [messages] with function declarations [tools] and returns the
  /// complete answer. Text and reasoning are streamed through [onDelta].
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required List<Map<String, Object?>> tools,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  });

  /// Names of the models available on the server.
  Future<List<String>> listModels();

  /// Capabilities of the configured model (null if the server cannot tell).
  Future<ModelInfo?> modelInfo();
}

LlmClient createLlmClient(LlmConfig config) => switch (config.provider) {
      LlmProvider.ollama => OllamaClient(config),
      LlmProvider.openAiCompatible => OpenAiCompatibleClient(config),
    };

/// Small HTTP helper shared by the clients (dart:io works on every
/// platform the app targets).
class HttpJson {
  HttpJson({this.headers = const {}});

  final Map<String, String> headers;

  /// POSTs JSON and yields the response body line by line.
  Stream<String> postLines(
    Uri uri,
    Map<String, Object?> body, {
    CancelToken? cancel,
    Duration idleTimeout = const Duration(minutes: 5),
  }) async* {
    cancel?.throwIfCancelled();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    void Function()? unregister;
    try {
      final HttpClientRequest request;
      try {
        request = await client.postUrl(uri);
      } on SocketException catch (e) {
        throw LlmException(_connectionHint(uri, e), retryable: false);
      }
      unregister = cancel?.onCancel(() {
        request.abort(const CancelledException());
        client.close(force: true);
      });
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      final bytes = utf8.encode(jsonEncode(body));
      // Explicit length - some servers do not accept chunked request bodies.
      request.contentLength = bytes.length;
      request.add(bytes);
      final HttpClientResponse response;
      try {
        response = await request.close();
      } on SocketException catch (e) {
        throw LlmException(_connectionHint(uri, e));
      } on HttpException catch (e) {
        if (cancel?.isCancelled ?? false) throw const CancelledException();
        throw LlmException('Spojení se serverem modelu selhalo: $e',
            retryable: true);
      }
      if (response.statusCode >= 400) {
        final text = await utf8.decodeStream(response);
        throw LlmException(
          errorMessage(text, response.statusCode),
          statusCode: response.statusCode,
          retryable: response.statusCode >= 500,
        );
      }
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(idleTimeout, onTimeout: (sink) {
        sink.addError(LlmException(
            'Server modelu neodpověděl ${idleTimeout.inSeconds} s.',
            retryable: true));
        sink.close();
      });
      try {
        // `await for` (not `yield*`) so that stream errors land in the
        // catch blocks below.
        await for (final line in lines) {
          yield line;
        }
      } on HttpException catch (e) {
        if (cancel?.isCancelled ?? false) throw const CancelledException();
        throw LlmException('Spojení se serverem modelu bylo přerušeno: $e',
            retryable: true);
      }
      if (cancel?.isCancelled ?? false) throw const CancelledException();
    } on Object catch (e) {
      if (cancel?.isCancelled ?? false) throw const CancelledException();
      if (e is LlmException) rethrow;
      if (e is CancelledException) rethrow;
      throw LlmException('Chyba komunikace se serverem modelu: $e');
    } finally {
      unregister?.call();
      client.close(force: true);
    }
  }

  Future<Object?> getJson(Uri uri) => _send('GET', uri, null);

  Future<Object?> postJson(Uri uri, Map<String, Object?> body) =>
      _send('POST', uri, body);

  Future<Object?> _send(String method, Uri uri, Object? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, uri);
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        final bytes = utf8.encode(jsonEncode(body));
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decodeStream(response);
      if (response.statusCode >= 400) {
        throw LlmException(errorMessage(text, response.statusCode),
            statusCode: response.statusCode);
      }
      return text.isEmpty ? null : jsonDecode(text);
    } on SocketException catch (e) {
      throw LlmException(_connectionHint(uri, e));
    } on TimeoutException {
      throw LlmException('Server modelu na $uri neodpovídá.');
    } on FormatException catch (e) {
      throw LlmException('Neplatná odpověď serveru modelu: $e');
    } finally {
      client.close(force: true);
    }
  }

  static String _connectionHint(Uri uri, Object error) =>
      'Nelze se spojit se serverem modelu na ${uri.scheme}://${uri.host}:${uri.port}. '
      'Běží Ollama / LM Studio a je adresa v nastavení správně? ($error)';

  /// Extracts a readable message from an error response.
  static String errorMessage(String body, int status) {
    var message = body.trim();
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final error = json['error'];
        if (error is String) message = error;
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        }
      }
    } on FormatException {
      // Not JSON - use the raw body.
    }
    if (message.length > 500) message = '${message.substring(0, 500)}...';
    if (status == 404 && message.contains('not found')) {
      message += ' - stáhněte model příkazem `ollama pull <model>` nebo '
          'zkontrolujte název modelu v nastavení.';
    }
    if (message.contains('does not support tools')) {
      message += ' - zvolte model s podporou nástrojů (tools), např. '
          'qwen3.5:9b.';
    }
    return 'Server modelu vrátil chybu $status: $message';
  }
}
