enum ChatRole { system, user, assistant, tool }

/// A function call requested by the model.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.argumentsError,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  /// Set when the model sent arguments that are not a valid JSON object.
  final String? argumentsError;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    if (argumentsError != null) 'argumentsError': argumentsError,
  };

  factory ToolCall.fromJson(Map<String, Object?> json) => ToolCall(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    arguments: Map<String, Object?>.from(
      (json['arguments'] as Map?) ?? const <String, Object?>{},
    ),
    argumentsError: json['argumentsError'] as String?,
  );
}

/// One message of the conversation sent to the model.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.thinking = '',
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  const ChatMessage.system(String content)
    : this(role: ChatRole.system, content: content);

  const ChatMessage.user(String content)
    : this(role: ChatRole.user, content: content);

  const ChatMessage.assistant(
    String content, {
    String thinking = '',
    List<ToolCall> toolCalls = const [],
  }) : this(
         role: ChatRole.assistant,
         content: content,
         thinking: thinking,
         toolCalls: toolCalls,
       );

  const ChatMessage.tool(
    String content, {
    required String toolCallId,
    required String toolName,
  }) : this(
         role: ChatRole.tool,
         content: content,
         toolCallId: toolCallId,
         toolName: toolName,
       );

  final ChatRole role;
  final String content;

  /// Reasoning of a thinking model (assistant messages only).
  final String thinking;
  final List<ToolCall> toolCalls;

  /// For [ChatRole.tool]: which call this is the result of.
  final String? toolCallId;
  final String? toolName;

  ChatMessage copyWith({String? content}) => ChatMessage(
    role: role,
    content: content ?? this.content,
    thinking: thinking,
    toolCalls: toolCalls,
    toolCallId: toolCallId,
    toolName: toolName,
  );
}

/// Token statistics reported by the server.
class LlmUsage {
  const LlmUsage({
    this.promptTokens,
    this.completionTokens,
    this.duration,
    this.loadDuration,
    this.promptDuration,
  });

  final int? promptTokens;
  final int? completionTokens;

  /// Time spent generating the answer.
  final Duration? duration;

  /// Time spent loading the model into memory (first request, Ollama).
  final Duration? loadDuration;

  /// Time spent reading the prompt (Ollama `prompt_eval_duration`).
  final Duration? promptDuration;

  /// Generation speed when the server reports it.
  double? get tokensPerSecond {
    final d = duration;
    final c = completionTokens;
    if (d == null || c == null || d.inMicroseconds == 0) return null;
    return c / (d.inMicroseconds / 1e6);
  }
}

/// Complete answer of one model call.
class LlmResponse {
  const LlmResponse({
    required this.content,
    this.thinking = '',
    this.toolCalls = const [],
    this.usage,
    this.finishReason,
  });

  final String content;
  final String thinking;
  final List<ToolCall> toolCalls;
  final LlmUsage? usage;
  final String? finishReason;
}

/// Streaming piece of an answer.
class LlmDelta {
  const LlmDelta.text(this.text) : isThinking = false;

  const LlmDelta.thinking(this.text) : isThinking = true;

  final String text;
  final bool isThinking;
}
