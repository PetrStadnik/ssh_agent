import 'dart:convert';

import 'chat_message.dart';
import 'llm_client.dart';
import 'llm_config.dart';

/// Client of OpenAI compatible servers (`POST /v1/chat/completions` with
/// server-sent events): LM Studio, llama.cpp `llama-server`, vLLM, LocalAI,
/// Jan, and Ollama's `/v1` endpoint.
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient(this.config)
    : _http = HttpJson(
        headers: {
          if (config.apiKey != null && config.apiKey!.isNotEmpty)
            'Authorization': 'Bearer ${config.apiKey}',
        },
      );

  @override
  final LlmConfig config;
  final HttpJson _http;
  int _callCounter = 0;

  Uri _uri(String path) {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/v1')) base = '$base/v1';
    return Uri.parse('$base$path');
  }

  Map<String, Object?> buildRequest(
    List<ChatMessage> messages,
    List<Map<String, Object?>> tools,
  ) => {
    'model': config.model,
    'messages': [for (final m in messages) encodeMessage(m)],
    if (tools.isNotEmpty) 'tools': tools,
    if (tools.isNotEmpty) 'tool_choice': 'auto',
    'stream': true,
    'temperature': config.temperature,
    if (config.thinking.reasoningEffort != null)
      'reasoning_effort': config.thinking.reasoningEffort,
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
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': jsonEncode(c.arguments),
                  },
                },
            ],
        };
      case ChatRole.tool:
        return {
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          if (m.toolName != null) 'name': m.toolName,
          'content': m.content,
        };
    }
  }

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required List<Map<String, Object?>> tools,
    void Function(LlmDelta delta)? onDelta,
    CancelToken? cancel,
  }) async {
    final content = StringBuffer();
    final thinking = StringBuffer();
    final partial = <int, _PartialCall>{};
    LlmUsage? usage;
    String? finishReason;
    final stopwatch = Stopwatch()..start();

    final lines = _http.postLines(
      _uri('/chat/completions'),
      buildRequest(messages, tools),
      cancel: cancel,
      idleTimeout: config.idleTimeout,
    );
    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') break;
      final Object? json;
      try {
        json = jsonDecode(data);
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      final error = json['error'];
      if (error != null) {
        final message = error is Map ? error['message'] ?? error : error;
        throw LlmException('Server modelu: $message', retryable: true);
      }
      final u = json['usage'];
      if (u is Map) {
        usage = LlmUsage(
          promptTokens: (u['prompt_tokens'] as num?)?.toInt(),
          completionTokens: (u['completion_tokens'] as num?)?.toInt(),
        );
      }
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices.first;
      if (choice is! Map) continue;
      finishReason = choice['finish_reason'] as String? ?? finishReason;
      final delta = choice['delta'] ?? choice['message'];
      if (delta is! Map) continue;
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        thinking.write(reasoning);
        onDelta?.call(LlmDelta.thinking(reasoning));
      }
      final c = delta['content'];
      if (c is String && c.isNotEmpty) {
        content.write(c);
        onDelta?.call(LlmDelta.text(c));
      }
      final toolCalls = delta['tool_calls'];
      if (toolCalls is List) {
        for (var i = 0; i < toolCalls.length; i++) {
          final raw = toolCalls[i];
          if (raw is! Map) continue;
          final index = (raw['index'] as num?)?.toInt() ?? i;
          final call = partial.putIfAbsent(index, _PartialCall.new);
          if (raw['id'] is String) call.id = raw['id'] as String;
          final function = raw['function'];
          if (function is Map) {
            if (function['name'] is String) {
              call.name.write(function['name']);
            }
            final args = function['arguments'];
            if (args is String) call.arguments.write(args);
            if (args is Map) call.arguments.write(jsonEncode(args));
          }
        }
      }
    }
    stopwatch.stop();
    if (usage != null) {
      usage = LlmUsage(
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        duration: stopwatch.elapsed,
      );
    }
    final keys = partial.keys.toList()..sort();
    return LlmResponse(
      content: content.toString(),
      thinking: thinking.toString(),
      toolCalls: [
        for (final k in keys)
          if (partial[k]!.name.isNotEmpty)
            partial[k]!.build(() => 'call_${++_callCounter}'),
      ],
      usage: usage,
      finishReason: finishReason,
    );
  }

  @override
  Future<List<String>> listModels() async {
    final json = await _http.getJson(_uri('/models'));
    if (json is! Map || json['data'] is! List) return const [];
    return [
      for (final m in json['data'] as List)
        if (m is Map && m['id'] is String) m['id'] as String,
    ]..sort();
  }

  @override
  Future<ModelInfo?> modelInfo() async => null;

  @override
  Future<void> warmUp() async {}
}

class _PartialCall {
  String? id;
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();

  ToolCall build(String Function() newId) {
    final text = arguments.toString().trim();
    final callId = (id == null || id!.isEmpty) ? newId() : id!;
    if (text.isEmpty) {
      return ToolCall(id: callId, name: name.toString(), arguments: const {});
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return ToolCall(
          id: callId,
          name: name.toString(),
          arguments: Map<String, Object?>.from(decoded),
        );
      }
    } on FormatException {
      // handled below
    }
    return ToolCall(
      id: callId,
      name: name.toString(),
      arguments: const {},
      argumentsError: 'Arguments are not valid JSON: $text',
    );
  }
}
