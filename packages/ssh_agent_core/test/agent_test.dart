import 'dart:convert';

import 'package:ssh_agent_core/ssh_agent_core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeExecutor executor;
  late RemoteSession session;

  setUp(() {
    executor = FakeExecutor(
      respond: (command) {
        if (command.contains('stat --')) {
          return const CommandResult(
            stdout: '  File: /etc/passwd\nModify: 2026-10-01 12:00:00 +0200\n',
            stderr: '',
            exitCode: 0,
            duration: Duration(milliseconds: 12),
          );
        }
        if (command.contains('/var/log') && command.contains('&& pwd')) {
          return const CommandResult(
            stdout: '/var/log\n',
            stderr: '',
            exitCode: 0,
            duration: Duration.zero,
          );
        }
        return const CommandResult(
          stdout: 'out\n',
          stderr: '',
          exitCode: 0,
          duration: Duration.zero,
        );
      },
    );
    session = RemoteSession(executor: executor);
  });

  Agent agent(ScriptedLlm llm, {ToolApprover? approver, int maxSteps = 20}) =>
      Agent(
        llm: llm,
        tools: ToolRegistry(),
        session: session,
        serverName: 'web-1',
        approver: approver,
        config: AgentConfig(maxSteps: maxSteps),
        clock: () => DateTime(2026, 10, 25, 12),
      );

  test('calls a tool, feeds the result back and answers', () async {
    final llm = ScriptedLlm([
      callTool('stat', {'path': '/etc/passwd'}),
      const LlmResponse(content: 'Soubor byl změněn 1. 10. 2026 ve 12:00.'),
    ]);
    final events = await agent(
      llm,
    ).run(history: const [], userMessage: 'Kdy?').toList();

    final started = events.whereType<AgentToolCallStarted>().single;
    expect(started.name, 'stat');
    expect(started.script, contains("stat -- '/etc/passwd'"));
    expect(started.fullCommand, startsWith('sh -c '));
    expect(started.server, 'web-1');
    expect(started.runAs, 'agent');

    final finished = events.whereType<AgentToolCallFinished>().single;
    expect(finished.result.stdout, contains('Modify: 2026-10-01'));
    expect(events.last, isA<AgentCompleted>());
    expect((events.last as AgentCompleted).text, contains('1. 10. 2026'));

    // Second request contains the tool result for the model.
    final second = llm.requests[1];
    expect(second.first.role, ChatRole.system);
    expect(second.first.content, contains('web-1'));
    expect(second.first.content, contains('read-only'));
    final toolMessage = second.last;
    expect(toolMessage.role, ChatRole.tool);
    expect(toolMessage.toolName, 'stat');
    expect(toolMessage.toolCallId, 'c1');
    expect(toolMessage.content, contains('[exit code 0]'));
    expect(executor.commands.single, contains('stat --'));
  });

  test('cd changes later commands and is visible in events', () async {
    final llm = ScriptedLlm([
      callTool('cd', {'path': '/var/log'}),
      callTool('ls', {}, id: 'c2'),
      const LlmResponse(content: 'Hotovo'),
    ]);
    final events = await agent(
      llm,
    ).run(history: const [], userMessage: 'ls logu').toList();
    final finished = events.whereType<AgentToolCallFinished>().toList();
    expect(finished.first.cwdAfter, '/var/log');
    final lsStart = events.whereType<AgentToolCallStarted>().last;
    expect(lsStart.cwd, '/var/log');
    expect(executor.commands.last, contains('/var/log'));
  });

  test('invalid calls are answered with an error and do not run', () async {
    final llm = ScriptedLlm([
      callTool('rm', {'path': '/'}),
      callTool('stat', {}, id: 'c2'),
      LlmResponse(
        content: '',
        toolCalls: [
          ToolCall(
            id: 'c3',
            name: 'ls',
            arguments: const {},
            argumentsError: 'bad json',
          ),
        ],
      ),
      const LlmResponse(content: 'Nemohu.'),
    ]);
    final events = await agent(
      llm,
    ).run(history: const [], userMessage: 'smaž /').toList();
    final results = events.whereType<AgentToolCallFinished>().toList();
    expect(results, hasLength(3));
    expect(results[0].modelText, contains('Unknown tool "rm"'));
    expect(results[1].modelText, contains('Missing required parameter'));
    expect(results[2].modelText, contains('bad json'));
    expect(executor.commands, isEmpty);
  });

  test('the same call is not executed more than twice', () async {
    final llm = ScriptedLlm([
      for (var i = 0; i < 4; i++) callTool('pwd', {}, id: 'p$i'),
      const LlmResponse(content: 'Jsem v /home/agent.'),
    ]);
    final events = await agent(
      llm,
    ).run(history: const [], userMessage: 'kde jsem').toList();
    expect(executor.commands, hasLength(2));
    final last = events.whereType<AgentToolCallFinished>().last;
    expect(last.modelText, contains('already made twice'));
  });

  test('tool call written as text is executed', () async {
    final llm = ScriptedLlm([
      const LlmResponse(
        content:
            'Podívám se.<tool_call>{"name": "stat", "arguments": {"path": "/etc/passwd"}}</tool_call>',
      ),
      const LlmResponse(content: 'Hotovo.'),
    ]);
    final events = await agent(
      llm,
    ).run(history: const [], userMessage: 'stat').toList();
    final message = events.whereType<AgentAssistantMessage>().first;
    expect(message.content, 'Podívám se.');
    expect(message.toolCalls.single.name, 'stat');
    expect(executor.commands.single, contains('stat --'));
  });

  test('user can decline a command', () async {
    final llm = ScriptedLlm([
      callTool('ps', {}),
      const LlmResponse(content: 'Nelze bez povolení.'),
    ]);
    final events = await agent(
      llm,
      approver: (_) async => false,
    ).run(history: const [], userMessage: 'procesy').toList();
    expect(executor.commands, isEmpty);
    expect(
      events.whereType<AgentToolCallFinished>().single.modelText,
      contains('declined'),
    );
  });

  test('step limit forces a final answer without tools', () async {
    final llm = ScriptedLlm([
      callTool('pwd', {}, id: 'a'),
      callTool('whoami', {}, id: 'b'),
      const LlmResponse(content: 'Shrnutí.'),
    ]);
    final events = await agent(
      llm,
      maxSteps: 2,
    ).run(history: const [], userMessage: 'x').toList();
    expect(events.whereType<AgentNotice>(), isNotEmpty);
    expect(llm.toolLists.last, isEmpty);
    expect((events.last as AgentCompleted).text, 'Shrnutí.');
  });

  test('cancellation stops the run', () async {
    final cancel = CancelToken()..cancel();
    final events = await agent(
      ScriptedLlm([callTool('pwd', {})]),
    ).run(history: const [], userMessage: 'x', cancel: cancel).toList();
    expect(events.single, isA<AgentCancelled>());
  });

  test('reports connecting, step timing and live tool output', () async {
    executor.connected = false;
    final llm = ScriptedLlm([
      callTool('stat', {'path': '/etc/passwd'}),
      const LlmResponse(
        content: 'Hotovo.',
        usage: LlmUsage(
          promptTokens: 900,
          completionTokens: 20,
          loadDuration: Duration(seconds: 4),
          promptDuration: Duration(seconds: 2),
        ),
      ),
    ]);
    final turn = AgentTurn();
    final phases = <AgentPhase>[];
    final events = <AgentEvent>[];
    await for (final e in agent(
      llm,
    ).run(history: const [], userMessage: 'Kdy?')) {
      events.add(e);
      turn.apply(e);
      phases.add(turn.phase);
    }

    expect(events.first, isA<AgentConnecting>());
    expect(events[1], isA<AgentConnected>());
    expect(turn.connectMs, isNotNull);

    final step = events.whereType<AgentStepStarted>().first;
    expect(step.approxPromptTokens, greaterThan(1000));

    // Output arrives before the tool finishes.
    final outputIndex = events.indexWhere((e) => e is AgentToolOutput);
    final finishedIndex = events.indexWhere((e) => e is AgentToolCallFinished);
    expect(outputIndex, greaterThan(0));
    expect(outputIndex, lessThan(finishedIndex));
    expect(
      events.whereType<AgentToolOutput>().map((e) => e.text).join(),
      contains('Modify: 2026-10-01'),
    );
    expect(turn.toolCalls.single.liveStdout, contains('Modify'));
    expect(turn.toolCalls.single.liveLines, 2);

    expect(
      phases,
      containsAllInOrder([
        AgentPhase.connecting,
        AgentPhase.waitingForModel,
        AgentPhase.runningTool,
        AgentPhase.processing,
        AgentPhase.waitingForModel,
        AgentPhase.idle,
      ]),
    );

    expect(turn.steps.first.modelMs, isNotNull);
    expect(turn.steps.last.loadMs, 4000);
    expect(turn.steps.last.promptEvalMs, 2000);
    expect(turn.steps.last.promptTokens, 900);

    // Timing survives saving.
    final restored = AgentTurn.fromJson(
      jsonDecode(jsonEncode(turn.toJson())) as Map<String, Object?>,
    );
    expect(restored.steps.last.loadMs, 4000);
    expect(restored.connectMs, turn.connectMs);
    expect(restored.phase, AgentPhase.idle);
  });

  test('a failing SSH connection ends the run with a clear error', () async {
    final failing = _FailingExecutor();
    final events = await Agent(
      llm: ScriptedLlm([]),
      tools: ToolRegistry(),
      session: RemoteSession(executor: failing),
      serverName: 'web-1',
    ).run(history: const [], userMessage: 'x').toList();
    expect(events.first, isA<AgentConnecting>());
    expect(
      (events.last as AgentFailed).message,
      'SSH: Nelze se připojit k example.org:22',
    );
  });

  group('Conversation', () {
    test('records events and rebuilds a valid history', () async {
      final llm = ScriptedLlm([
        LlmResponse(
          content: 'Ověřím.',
          thinking: 'plan',
          toolCalls: [
            ToolCall(
              id: 'c1',
              name: 'stat',
              arguments: const {'path': '/etc/passwd'},
            ),
          ],
        ),
        const LlmResponse(content: 'Změněno 1. 10.'),
      ]);
      final conversation = Conversation(id: '1');
      conversation.turns.add(UserTurn('Kdy?'));
      final turn = AgentTurn();
      conversation.turns.add(turn);
      await for (final e in agent(
        llm,
      ).run(history: const [], userMessage: 'Kdy?')) {
        turn.apply(e);
      }
      expect(turn.status, AgentTurnStatus.done);
      expect(turn.steps, hasLength(2));
      expect(turn.steps.first.thinking, 'plan');
      final invocation = turn.toolCalls.single;
      expect(invocation.status, ToolStatus.done);
      expect(invocation.stdout, contains('Modify'));
      expect(turn.answer, 'Změněno 1. 10.');

      // JSON round trip.
      final restored = Conversation.fromJson(
        jsonDecode(jsonEncode(conversation.toJson())) as Map<String, Object?>,
      );
      final history = restored.toHistory();
      expect(history.map((m) => m.role), [
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.tool,
        ChatRole.assistant,
      ]);
      expect(history[1].toolCalls.single.name, 'stat');
      expect(history[2].toolCallId, 'c1');
      expect(history[3].content, 'Změněno 1. 10.');
    });

    test('long histories shorten old tool output first', () {
      final conversation = Conversation(id: '2');
      for (var i = 0; i < 6; i++) {
        conversation.turns.add(UserTurn('otázka $i'));
        conversation.turns.add(
          AgentTurn(
            status: AgentTurnStatus.done,
            steps: [
              AgentStepRecord(
                tools: [
                  ToolInvocation(
                    id: 't$i',
                    name: 'cat',
                    arguments: const {'path': '/x'},
                    server: 's',
                    status: ToolStatus.done,
                    modelText: 'x' * 5000,
                  ),
                ],
              ),
              AgentStepRecord(text: 'odpověď $i'),
            ],
          ),
        );
      }
      final history = conversation.toHistory(maxChars: 12000);
      expect(history.first.role, ChatRole.user);
      final total = history.fold<int>(0, (s, m) => s + m.content.length);
      expect(total, lessThan(14000));
      expect(history.last.content, 'odpověď 5');
      // The newest tool output is intact.
      expect(
        history.where((m) => m.role == ChatRole.tool).last.content.length,
        5000,
      );
    });

    test('a turn interrupted mid-tool keeps the history valid', () {
      final turn = AgentTurn();
      turn.apply(const AgentStepStarted(0));
      turn.apply(
        const AgentToolCallStarted(
          callId: 'c',
          name: 'find',
          arguments: {},
          server: 's',
        ),
      );
      turn.apply(const AgentCancelled());
      final messages = turn.toMessages();
      expect(messages.map((m) => m.role), [
        ChatRole.assistant,
        ChatRole.tool,
        ChatRole.assistant,
      ]);
      expect(turn.toolCalls.single.status, ToolStatus.failed);
    });
  });
}

class _FailingExecutor extends FakeExecutor {
  _FailingExecutor() {
    connected = false;
  }

  @override
  Future<void> connect() async =>
      throw RemoteConnectionException('Nelze se připojit k example.org:22');
}
