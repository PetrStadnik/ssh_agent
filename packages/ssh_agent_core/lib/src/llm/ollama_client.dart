import 'dart:convert';

import 'chat_message.dart';
import 'llm_client.dart';
import 'llm_config.dart';

/// Client of the Ollama native API (`POST /api/chat`, streaming NDJSON).
class OllamaClient implements LlmClient {
  OllamaClient(this.config) : _http = HttpJson();

  @override
  final LlmConfig config;
  final HttpJson _http;
  int _callCounter = 0;

  /// Set when the model rejected the `think` field; not sent again.
  bool _thinkUnsupported = false;

  Uri _uri(String path) {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1')) base = base.substring(0, base.length - 3);
    if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
    return Uri.parse('$base$path');
  }

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required List<Map<String, Object?>> tools,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  }) async {
    final think = _thinkUnsupported ? null : config.thinking.ollamaValue;
    try {
      return await _chat(messages, tools, think, onDelta, cancel);
    } on LlmException catch (e) {
      if (think != null && e.message.contains('does not support thinking')) {
        _thinkUnsupported = true;
        return _chat(messages, tools, null, onDelta, cancel);
      }
      rethrow;
    }
  }

  Map<String, Object?> buildRequest(
    List<ChatMessage> messages,
    List<Map<String, Object?>> tools,
    Object? think,
  ) => {
    'model': config.model,
    'messages': [for (final m in messages) encodeMessage(m)],
    if (tools.isNotEmpty) 'tools': tools,
    'stream': true,
    'think': ?think,
    'keep_alive': config.keepAlive,
    'options': {
      'num_ctx': config.contextLength,
      'temperature': config.temperature,
    },
  };

  static Map<String, Object?> encodeMessage(ChatMessage m) {
    switch (m.role) {
      case ChatRole.system:
      case ChatRole.user:
        return {'role': m.role.name, 'content': m.content};
      case ChatRole.assistant:
        return {
          'role': 'assistant',
          'content': m.content,
          if (m.thinking.isNotEmpty) 'thinking': m.thinking,
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'function': {'name': c.name, 'arguments': c.arguments},
                },
            ],
        };
      case ChatRole.tool:
        return {
          'role': 'tool',
          'content': m.content,
          if (m.toolName != null) 'tool_name': m.toolName,
          if (m.toolCallId != null) 'tool_call_id': m.toolCallId,
        };
    }
  }

  Future<LlmResponse> _chat(
    List<ChatMessage> messages,
    List<Map<String, Object?>> tools,
    Object? think,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  ) async {
    final content = StringBuffer();
    final thinking = StringBuffer();
    final calls = <ToolCall>[];
    LlmUsage? usage;
    String? finishReason;

    final lines = _http.postLines(
      _uri('/api/chat'),
      buildRequest(messages, tools, think),
      cancel: cancel,
      idleTimeout: config.idleTimeout,
    );
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      final error = json['error'];
      if (error != null) {
        throw LlmException(
          'Ollama: $error',
          retryable: _isToolParseError('$error'),
        );
      }
      final message = json['message'];
      if (message is Map) {
        final t = message['thinking'];
        if (t is String && t.isNotEmpty) {
          thinking.write(t);
          onDelta?.call(LlmDelta.thinking(t));
        }
        final c = message['content'];
        if (c is String && c.isNotEmpty) {
          content.write(c);
          onDelta?.call(LlmDelta.text(c));
        }
        final toolCalls = message['tool_calls'];
        if (toolCalls is List) {
          for (final raw in toolCalls) {
            final call = _parseToolCall(raw);
            if (call != null) calls.add(call);
          }
        }
      }
      if (json['done'] == true) {
        finishReason = json['done_reason'] as String?;
        Duration? nanos(Object? value) =>
            value is num ? Duration(microseconds: value ~/ 1000) : null;
        usage = LlmUsage(
          promptTokens: (json['prompt_eval_count'] as num?)?.toInt(),
          completionTokens: (json['eval_count'] as num?)?.toInt(),
          duration: nanos(json['eval_duration']),
          loadDuration: nanos(json['load_duration']),
          promptDuration: nanos(json['prompt_eval_duration']),
        );
      }
    }
    return LlmResponse(
      content: content.toString(),
      thinking: thinking.toString(),
      toolCalls: calls,
      usage: usage,
      finishReason: finishReason,
    );
  }

  ToolCall? _parseToolCall(Object? raw) {
    if (raw is! Map) return null;
    final function = raw['function'];
    if (function is! Map) return null;
    final name = function['name'];
    if (name is! String || name.isEmpty) return null;
    final id = raw['id'] is String && (raw['id'] as String).isNotEmpty
        ? raw['id'] as String
        : 'call_${++_callCounter}';
    final args = function['arguments'];
    if (args is Map) {
      return ToolCall(
        id: id,
        name: name,
        arguments: Map<String, Object?>.from(args),
      );
    }
    if (args is String) {
      try {
        final decoded = args.trim().isEmpty
            ? <String, Object?>{}
            : jsonDecode(args);
        if (decoded is Map) {
          return ToolCall(
            id: id,
            name: name,
            arguments: Map<String, Object?>.from(decoded),
          );
        }
      } on FormatException {
        // fall through
      }
      return ToolCall(
        id: id,
        name: name,
        arguments: const {},
        argumentsError: 'Arguments are not a JSON object: $args',
      );
    }
    return ToolCall(id: id, name: name, arguments: const {});
  }

  /// Ollama reports a tool call it could not parse as an error (HTTP 500 or
  /// an error line); retrying usually produces a valid call.
  static bool _isToolParseError(String message) =>
      message.contains('tool') ||
      message.contains('closed by') ||
      message.contains('parse') ||
      message.contains('unexpected');

  /// An empty chat request makes Ollama load the model (with the same
  /// context size, so the first real request does not reload it).
  @override
  Future<void> warmUp() async {
    try {
      await _http.postJson(_uri('/api/chat'), {
        'model': config.model,
        'messages': const <Object>[],
        'stream': false,
        'keep_alive': config.keepAlive,
        'options': {'num_ctx': config.contextLength},
      });
    } catch (_) {
      // Best effort only.
    }
  }

  @override
  Future<List<String>> listModels() async {
    final json = await _http.getJson(_uri('/api/tags'));
    if (json is! Map || json['models'] is! List) return const [];
    return [
      for (final m in json['models'] as List)
        if (m is Map && m['name'] is String) m['name'] as String,
    ]..sort();
  }

  @override
  Future<ModelInfo?> modelInfo() async {
    final json = await _http.postJson(_uri('/api/show'), {
      'model': config.model,
    });
    if (json is! Map) return null;
    int? context;
    final info = json['model_info'];
    if (info is Map) {
      for (final entry in info.entries) {
        if ('${entry.key}'.endsWith('.context_length') && entry.value is num) {
          context = (entry.value as num).toInt();
        }
      }
    }
    return ModelInfo(
      capabilities: [
        for (final c in (json['capabilities'] as List?) ?? const [])
          if (c is String) c,
      ],
      contextLength: context,
    );
  }
}
