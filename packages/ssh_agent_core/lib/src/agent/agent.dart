import 'dart:async';
import 'dart:convert';

import '../llm/chat_message.dart';
import '../llm/llm_client.dart';
import '../llm/text_tool_calls.dart';
import '../remote/remote_session.dart';
import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import '../util/shell.dart';
import 'agent_event.dart';
import 'system_prompt.dart';

/// Asked before each command when the user wants to approve commands.
typedef ToolApprover = Future<bool> Function(PreparedToolCall call);

class AgentConfig {
  const AgentConfig({
    this.maxSteps = 20,
    this.maxToolOutputChars = 12000,
    this.parseTextToolCalls = true,
    this.maxModelRetries = 2,
    this.answerLanguage = 'Czech',
    this.extraInstructions = '',
  });

  /// Maximum number of model calls in one answer.
  final int maxSteps;

  /// Tool output longer than this is shortened (middle cut) for the model.
  final int maxToolOutputChars;

  /// Accept tool calls written as text by weaker models.
  final bool parseTextToolCalls;

  /// Retries of a failed model call (server error, malformed tool call).
  final int maxModelRetries;
  final String answerLanguage;
  final String extraInstructions;
}

/// The agent loop: model -> tool calls -> results -> model ... -> answer.
class Agent {
  Agent({
    required this.llm,
    required this.tools,
    required this.session,
    required this.serverName,
    this.config = const AgentConfig(),
    this.approver,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LlmClient llm;
  final ToolRegistry tools;
  final RemoteSession session;
  final String serverName;
  final AgentConfig config;
  final ToolApprover? approver;
  final DateTime Function() _clock;

  /// Answers [userMessage] given the earlier conversation [history]
  /// (without system prompt). The stream ends after [AgentCompleted],
  /// [AgentFailed] or [AgentCancelled].
  Stream<AgentEvent> run({
    required List<ChatMessage> history,
    required String userMessage,
    CancelToken? cancel,
  }) {
    final controller = StreamController<AgentEvent>();
    final token = cancel ?? CancelToken();
    Future<void>(() async {
      try {
        await _loop(history, userMessage, token, controller.add);
      } on CancelledException {
        controller.add(const AgentCancelled());
      } on LlmException catch (e) {
        controller.add(AgentFailed(e.message));
      } catch (e) {
        controller.add(AgentFailed('Neočekávaná chyba: $e'));
      } finally {
        await controller.close();
      }
    });
    return controller.stream;
  }

  Future<void> _loop(
    List<ChatMessage> history,
    String userMessage,
    CancelToken cancel,
    void Function(AgentEvent) emit,
  ) async {
    final messages = <ChatMessage>[
      ChatMessage.system(
        buildSystemPrompt(
          session: session,
          serverName: serverName,
          now: _clock(),
          answerLanguage: config.answerLanguage,
          extraInstructions: config.extraInstructions,
        ),
      ),
      ...history,
      ChatMessage.user(userMessage),
    ];
    final schemas = tools.schemas(session);
    final toolNames = {for (final t in tools.available(session)) t.name};
    final callCounts = <String, int>{};

    for (var step = 0; step < config.maxSteps; step++) {
      cancel.throwIfCancelled();
      final response = await _callModel(messages, schemas, step, cancel, emit);
      var content = response.content;
      var calls = response.toolCalls;
      if (calls.isEmpty && config.parseTextToolCalls) {
        final extracted = extractTextToolCalls(
          content,
          toolNames,
          idPrefix: 'text_${step}_call',
        );
        if (extracted.calls.isNotEmpty) {
          calls = extracted.calls;
          content = extracted.remainingText;
        }
      }
      emit(
        AgentAssistantMessage(
          content: content,
          thinking: response.thinking,
          toolCalls: calls,
          usage: response.usage,
        ),
      );
      messages.add(
        ChatMessage.assistant(
          content,
          thinking: response.thinking,
          toolCalls: calls,
        ),
      );
      if (calls.isEmpty) {
        if (content.trim().isEmpty) {
          // Some models stop silently; ask once more for a real answer.
          messages.add(
            const ChatMessage.user(
              'Please answer my question now based on the tool results.',
            ),
          );
          continue;
        }
        emit(AgentCompleted(content));
        return;
      }
      for (final call in calls) {
        cancel.throwIfCancelled();
        final modelText = await _runTool(call, callCounts, emit);
        messages.add(
          ChatMessage.tool(modelText, toolCallId: call.id, toolName: call.name),
        );
      }
    }

    emit(
      AgentNotice(
        'Dosažen limit ${config.maxSteps} kroků - agent '
        'odpovídá z toho, co zatím zjistil.',
      ),
    );
    messages.add(
      const ChatMessage.user(
        'You reached the maximum number of steps. Do not call any more tools. '
        'Answer now with what you found and say what remains unverified.',
      ),
    );
    final response = await _callModel(
      messages,
      const [],
      config.maxSteps,
      cancel,
      emit,
    );
    emit(
      AgentAssistantMessage(
        content: response.content,
        thinking: response.thinking,
        toolCalls: const [],
        usage: response.usage,
      ),
    );
    emit(AgentCompleted(response.content));
  }

  Future<LlmResponse> _callModel(
    List<ChatMessage> messages,
    List<Map<String, Object?>> schemas,
    int step,
    CancelToken cancel,
    void Function(AgentEvent) emit,
  ) async {
    for (var attempt = 0; ; attempt++) {
      emit(AgentStepStarted(step, retry: attempt > 0));
      try {
        final request = attempt < 2
            ? messages
            : [
                ...messages,
                const ChatMessage.user(
                  'Your previous reply could not be processed (probably a '
                  'malformed tool call). Call the tool again using the '
                  'function-calling interface with a valid JSON object of '
                  'arguments, or answer in plain text.',
                ),
              ];
        return await llm.chat(
          messages: request,
          tools: schemas,
          cancel: cancel,
          onDelta: (delta) => emit(
            delta.isThinking
                ? AgentThinkingDelta(delta.text)
                : AgentTextDelta(delta.text),
          ),
        );
      } on LlmException catch (e) {
        if (!e.retryable || attempt >= config.maxModelRetries) rethrow;
        emit(AgentNotice('Model vrátil chybu, zkouším znovu: ${e.message}'));
      }
    }
  }

  Future<String> _runTool(
    ToolCall call,
    Map<String, int> callCounts,
    void Function(AgentEvent) emit,
  ) async {
    final server = serverName;
    void reject(String message) {
      final result = ToolResult.failure(message);
      emit(
        AgentToolCallStarted(
          callId: call.id,
          name: call.name,
          arguments: call.arguments,
          server: server,
          runAs: session.effectiveUser,
          cwd: session.cwd,
        ),
      );
      emit(
        AgentToolCallFinished(
          callId: call.id,
          result: result,
          modelText: ToolRegistry.formatForModel(result),
          cwdAfter: session.cwd,
          runAsAfter: session.effectiveUser,
        ),
      );
    }

    if (call.argumentsError != null) {
      reject(call.argumentsError!);
      return '[error] ${call.argumentsError}';
    }

    final PreparedToolCall prepared;
    try {
      prepared = tools.prepare(call.id, call.name, call.arguments, session);
    } on UnknownToolException catch (e) {
      reject(e.toString());
      return '[error] $e';
    } on ToolArgumentException catch (e) {
      reject(e.message);
      return '[error] ${e.message}';
    }

    final key =
        '${call.name} ${jsonEncode(prepared.args.values)} '
        '${session.cwd} ${session.effectiveUser}';
    final count = callCounts[key] = (callCounts[key] ?? 0) + 1;
    if (count > 2) {
      const message =
          'This exact call was already made twice. Use the '
          'earlier result or try a different approach.';
      reject(message);
      return '[error] $message';
    }

    emit(
      AgentToolCallStarted(
        callId: call.id,
        name: call.name,
        arguments: prepared.args.values,
        server: server,
        script: prepared.script,
        fullCommand: prepared.fullCommand,
        runAs: prepared.runAs,
        cwd: prepared.cwd,
      ),
    );

    ToolResult result;
    if (approver != null && !await approver!(prepared)) {
      result = ToolResult.failure('The user declined to run this command.');
    } else {
      result = await tools.execute(prepared, session);
    }
    final modelText = ToolRegistry.formatForModel(
      result,
      maxChars: config.maxToolOutputChars,
    );
    emit(
      AgentToolCallFinished(
        callId: call.id,
        result: result,
        modelText: modelText,
        cwdAfter: session.cwd,
        runAsAfter: session.effectiveUser,
      ),
    );
    return modelText;
  }
}
