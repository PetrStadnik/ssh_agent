import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ssh_agent_core/ssh_agent_core.dart';
import 'package:test/test.dart';

/// Minimal HTTP server that records requests and replies with [handler].
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final List<Map<String, Object?>> bodies = [];
  final List<String> paths = [];
  late Future<void> Function(HttpRequest request, Map<String, Object?> body)
  handler;

  static Future<FakeServer> start() async {
    final server = FakeServer._(await HttpServer.bind('127.0.0.1', 0));
    server._server.listen((request) async {
      final text = await utf8.decodeStream(request);
      final body = text.isEmpty
          ? <String, Object?>{}
          : Map<String, Object?>.from(jsonDecode(text) as Map);
      request.response.bufferOutput = false;
      server.bodies.add(body);
      server.paths.add(request.uri.path);
      await server.handler(request, body);
      await request.response.close();
    });
    return server;
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);
}

extension on HttpResponse {
  void writeUtf8(String text) => add(utf8.encode(text));
}

const messages = [
  ChatMessage.system('sys'),
  ChatMessage.user('Kdy se změnil /etc/passwd?'),
  ChatMessage.assistant(
    '',
    toolCalls: [
      ToolCall(id: 'call_0', name: 'stat', arguments: {'path': '/etc/passwd'}),
    ],
  ),
  ChatMessage.tool(
    '[exit code 0]\nModify: 2026-10-01',
    toolCallId: 'call_0',
    toolName: 'stat',
  ),
];

final tools = [allTools.firstWhere((t) => t.name == 'stat').toFunctionSchema()];

void main() {
  late FakeServer server;
  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  group('Ollama', () {
    test(
      'streams text and thinking, parses tool calls, sends options',
      () async {
        server.handler = (request, body) async {
          request.response.headers.contentType = ContentType(
            'application',
            'x-ndjson',
          );
          for (final chunk in [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'thinking': 'Musím ',
              },
            },
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'thinking': 'zjistit.',
              },
            },
            {
              'message': {'role': 'assistant', 'content': 'Zjišťuji'},
            },
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'function': {
                      'name': 'ls',
                      'arguments': {'path': '/etc', 'all': true},
                    },
                  },
                ],
              },
            },
            {
              'done': true,
              'done_reason': 'stop',
              'prompt_eval_count': 120,
              'eval_count': 30,
              'eval_duration': 1500000000,
              'load_duration': 3200000000,
              'prompt_eval_duration': 800000000,
            },
          ]) {
            request.response.writeUtf8('${jsonEncode(chunk)}\n');
            await request.response.flush();
          }
        };
        final client = OllamaClient(
          LlmConfig(
            baseUrl: '${server.url}/',
            model: 'qwen3.5:9b',
            contextLength: 16384,
            thinking: ThinkingMode.on,
          ),
        );
        final deltas = <LlmDelta>[];
        final response = await client.chat(
          messages: messages,
          tools: tools,
          onDelta: deltas.add,
        );

        expect(response.thinking, 'Musím zjistit.');
        expect(response.content, 'Zjišťuji');
        expect(response.toolCalls.single.name, 'ls');
        expect(response.toolCalls.single.arguments, {
          'path': '/etc',
          'all': true,
        });
        expect(response.usage!.promptTokens, 120);
        expect(response.usage!.tokensPerSecond, closeTo(20, 0.01));
        expect(
          response.usage!.loadDuration,
          const Duration(milliseconds: 3200),
        );
        expect(
          response.usage!.promptDuration,
          const Duration(milliseconds: 800),
        );
        expect(deltas.where((d) => d.isThinking).length, 2);

        expect(server.paths.single, '/api/chat');
        final body = server.bodies.single;
        expect(body['model'], 'qwen3.5:9b');
        expect(body['stream'], true);
        expect(body['think'], true);
        expect((body['options'] as Map)['num_ctx'], 16384);
        expect((body['tools'] as List).single, isA<Map>());
        final sent = body['messages'] as List;
        expect(sent[2]['tool_calls'][0]['function']['arguments'], {
          'path': '/etc/passwd',
        });
        expect(sent[3], {
          'role': 'tool',
          'content': '[exit code 0]\nModify: 2026-10-01',
          'tool_name': 'stat',
          'tool_call_id': 'call_0',
        });
      },
    );

    test('retries without think when the model does not support it', () async {
      server.handler = (request, body) async {
        if (body.containsKey('think')) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({'error': '"llama3" does not support thinking'}),
          );
          return;
        }
        request.response.writeUtf8(
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'OK'},
            'done': true,
          })}\n',
        );
      };
      final client = OllamaClient(
        LlmConfig(baseUrl: server.url, thinking: ThinkingMode.high),
      );
      final response = await client.chat(messages: messages, tools: tools);
      expect(response.content, 'OK');
      expect(server.bodies.length, 2);
      expect(server.bodies.first['think'], 'high');
    });

    test('errors are readable and 5xx is retryable', () async {
      server.handler = (request, body) async {
        request.response.statusCode = 500;
        request.response.writeUtf8(
          jsonEncode({
            'error':
                'failed to parse tool call: element <function> closed by </parameter>',
          }),
        );
      };
      final client = OllamaClient(LlmConfig(baseUrl: server.url));
      await expectLater(
        client.chat(messages: messages, tools: tools),
        throwsA(
          isA<LlmException>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.message, 'message', contains('500')),
        ),
      );
    });

    test('lists models and reads capabilities', () async {
      server.handler = (request, body) async {
        if (request.uri.path == '/api/tags') {
          request.response.writeUtf8(
            jsonEncode({
              'models': [
                {'name': 'qwen3.5:9b'},
                {'name': 'gemma4:e4b'},
              ],
            }),
          );
        } else {
          request.response.writeUtf8(
            jsonEncode({
              'capabilities': ['completion', 'tools', 'thinking'],
              'model_info': {'qwen35.context_length': 262144},
            }),
          );
        }
      };
      final client = OllamaClient(LlmConfig(baseUrl: server.url));
      expect(await client.listModels(), ['gemma4:e4b', 'qwen3.5:9b']);
      final info = await client.modelInfo();
      expect(info!.supportsTools, isTrue);
      expect(info.contextLength, 262144);
    });

    test('warm up loads the model with the configured context', () async {
      server.handler = (request, body) async {
        request.response.writeUtf8(
          jsonEncode({
            'model': 'qwen3.5:9b',
            'done': true,
            'done_reason': 'load',
          }),
        );
      };
      final client = OllamaClient(
        LlmConfig(
          baseUrl: server.url,
          model: 'qwen3.5:9b',
          contextLength: 16384,
        ),
      );
      await client.warmUp();
      final body = server.bodies.single;
      expect(server.paths.single, '/api/chat');
      expect(body['messages'], isEmpty);
      expect(body['stream'], false);
      expect((body['options'] as Map)['num_ctx'], 16384);
    });

    test('warm up never throws', () async {
      final client = OllamaClient(
        const LlmConfig(baseUrl: 'http://127.0.0.1:1'),
      );
      await client.warmUp();
    });

    test('connection refused gives a hint', () async {
      final client = OllamaClient(
        const LlmConfig(baseUrl: 'http://127.0.0.1:1'),
      );
      await expectLater(
        client.chat(messages: messages, tools: tools),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            contains('Běží Ollama'),
          ),
        ),
      );
    });

    test('cancel aborts a running request', () async {
      final release = Completer<void>();
      server.handler = (request, body) async {
        request.response.writeUtf8(
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'Začínám'},
          })}\n',
        );
        await request.response.flush();
        await release.future;
      };
      final client = OllamaClient(LlmConfig(baseUrl: server.url));
      final cancel = CancelToken();
      final future = client.chat(
        messages: messages,
        tools: tools,
        cancel: cancel,
        onDelta: (_) => cancel.cancel(),
      );
      await expectLater(future, throwsA(isA<CancelledException>()));
      release.complete();
    });
  });

  group('OpenAI compatible', () {
    test('assembles streamed tool call arguments and reasoning', () async {
      server.handler = (request, body) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        final chunks = [
          {
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant', 'reasoning_content': 'Hmm'},
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Podívám se.'},
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_A',
                      'type': 'function',
                      'function': {
                        'name': 'grep',
                        'arguments': '{"pattern": "ro',
                      },
                    },
                  ],
                },
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': 'ot", "path": "/etc/passwd"}'},
                    },
                  ],
                },
              },
            ],
          },
          {
            'choices': [
              {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'},
            ],
          },
          {
            'choices': [],
            'usage': {'prompt_tokens': 50, 'completion_tokens': 12},
          },
        ];
        for (final c in chunks) {
          request.response.writeUtf8('data: ${jsonEncode(c)}\n\n');
          await request.response.flush();
        }
        request.response.writeUtf8('data: [DONE]\n\n');
      };
      final client = OpenAiCompatibleClient(
        LlmConfig(
          provider: LlmProvider.openAiCompatible,
          baseUrl: server.url,
          model: 'local-model',
          apiKey: 'secret',
          thinking: ThinkingMode.low,
        ),
      );
      final response = await client.chat(messages: messages, tools: tools);

      expect(response.thinking, 'Hmm');
      expect(response.content, 'Podívám se.');
      expect(response.finishReason, 'tool_calls');
      final call = response.toolCalls.single;
      expect(call.id, 'call_A');
      expect(call.arguments, {'pattern': 'root', 'path': '/etc/passwd'});
      expect(response.usage!.completionTokens, 12);

      expect(server.paths.single, '/v1/chat/completions');
      final body = server.bodies.single;
      expect(body['reasoning_effort'], 'low');
      final sent = body['messages'] as List;
      expect(
        sent[2]['tool_calls'][0]['function']['arguments'],
        '{"path":"/etc/passwd"}',
      );
      expect(sent[3]['tool_call_id'], 'call_0');
    });

    test('invalid JSON arguments are reported, not thrown', () async {
      server.handler = (request, body) async {
        request.response.writeUtf8(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'name': 'cat', 'arguments': '{"path": '},
                    },
                  ],
                },
              },
            ],
          })}\n\ndata: [DONE]\n\n',
        );
      };
      final client = OpenAiCompatibleClient(
        LlmConfig(
          provider: LlmProvider.openAiCompatible,
          baseUrl: '${server.url}/v1',
        ),
      );
      final response = await client.chat(messages: messages, tools: tools);
      expect(response.toolCalls.single.argumentsError, isNotNull);
      expect(server.paths.single, '/v1/chat/completions');
    });
  });

  group('tool calls written as text', () {
    const names = {'stat', 'ls', 'grep'};

    test('Hermes/Qwen <tool_call> tags', () {
      final r = extractTextToolCalls(
        'Zkontroluji to.\n<tool_call>\n{"name": "stat", "arguments": {"path": "/etc/passwd"}}\n</tool_call>',
        names,
      );
      expect(r.calls.single.name, 'stat');
      expect(r.calls.single.arguments['path'], '/etc/passwd');
      expect(r.remainingText, 'Zkontroluji to.');
    });

    test('JSON in a code block', () {
      final r = extractTextToolCalls(
        '```json\n{"name": "ls", "parameters": {"path": "/var/log"}}\n```',
        names,
      );
      expect(r.calls.single.name, 'ls');
      expect(r.remainingText, isEmpty);
    });

    test('Mistral [TOOL_CALLS] list', () {
      final r = extractTextToolCalls(
        '[TOOL_CALLS][{"name": "grep", "arguments": {"pattern": "x"}}, {"name": "ls", "arguments": {}}]',
        names,
      );
      expect(r.calls.map((c) => c.name), ['grep', 'ls']);
    });

    test('ordinary JSON in an answer is left alone', () {
      const answer = 'Konfigurace obsahuje {"name": "web", "port": 80}.';
      final r = extractTextToolCalls(answer, names);
      expect(r.calls, isEmpty);
      expect(r.remainingText, answer);
    });
  });
}
