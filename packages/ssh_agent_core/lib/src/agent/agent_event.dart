import '../llm/chat_message.dart';
import '../tools/tool.dart';

/// Everything the agent does is reported as events, so that the user always
/// sees which functions are called and what they returned.
sealed class AgentEvent {
  const AgentEvent();
}

/// Opening the SSH connection (only when it is not open yet).
class AgentConnecting extends AgentEvent {
  const AgentConnecting(this.server);

  final String server;
}

class AgentConnected extends AgentEvent {
  const AgentConnected(this.server, this.duration);

  final String server;
  final Duration duration;
}

/// A new model call starts. [retry] = the previous attempt of the same step
/// failed and its partial text should be discarded.
class AgentStepStarted extends AgentEvent {
  const AgentStepStarted(
    this.step, {
    this.retry = false,
    this.approxPromptTokens,
  });

  final int step;
  final bool retry;

  /// Rough size of what the model has to read (messages + tool definitions).
  final int? approxPromptTokens;
}

class AgentThinkingDelta extends AgentEvent {
  const AgentThinkingDelta(this.text);

  final String text;
}

class AgentTextDelta extends AgentEvent {
  const AgentTextDelta(this.text);

  final String text;
}

/// Final content of one model call (text may differ from the streamed one
/// when a tool call written as text was extracted from it).
class AgentAssistantMessage extends AgentEvent {
  const AgentAssistantMessage({
    required this.content,
    required this.thinking,
    required this.toolCalls,
    this.usage,
    this.elapsed,
  });

  final String content;
  final String thinking;
  final List<ToolCall> toolCalls;
  final LlmUsage? usage;

  /// Wall-clock time of the model call.
  final Duration? elapsed;
}

/// A tool is about to run on the server.
class AgentToolCallStarted extends AgentEvent {
  const AgentToolCallStarted({
    required this.callId,
    required this.name,
    required this.arguments,
    required this.server,
    this.script,
    this.fullCommand,
    this.runAs,
    this.cwd,
  });

  final String callId;
  final String name;
  final Map<String, Object?> arguments;
  final String server;

  /// Null when the call was rejected before execution.
  final String? script;
  final String? fullCommand;
  final String? runAs;
  final String? cwd;
}

/// A piece of output of a running tool, as it arrives from the server.
class AgentToolOutput extends AgentEvent {
  const AgentToolOutput(this.callId, this.text, {this.isStderr = false});

  final String callId;
  final String text;
  final bool isStderr;
}

class AgentToolCallFinished extends AgentEvent {
  const AgentToolCallFinished({
    required this.callId,
    required this.result,
    required this.modelText,
    required this.cwdAfter,
    required this.runAsAfter,
  });

  final String callId;
  final ToolResult result;

  /// Exactly what was sent back to the model.
  final String modelText;

  /// Session state after the call (cd / switch_user change it).
  final String? cwdAfter;
  final String runAsAfter;
}

/// Informational message (e.g. step limit reached).
class AgentNotice extends AgentEvent {
  const AgentNotice(this.message);

  final String message;
}

class AgentCompleted extends AgentEvent {
  const AgentCompleted(this.text);

  final String text;
}

class AgentFailed extends AgentEvent {
  const AgentFailed(this.message);

  final String message;
}

class AgentCancelled extends AgentEvent {
  const AgentCancelled();
}
