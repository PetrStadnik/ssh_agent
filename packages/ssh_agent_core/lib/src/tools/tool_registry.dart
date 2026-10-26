import '../remote/remote_executor.dart';
import '../remote/remote_session.dart';
import '../util/shell.dart';
import 'catalog/file_tools.dart';
import 'catalog/session_tools.dart';
import 'catalog/system_tools.dart';
import 'catalog/user_tools.dart';
import 'tool.dart';

/// All predefined tools. Every one of them is read-only.
final List<ToolDefinition> allTools = List.unmodifiable([
  ...sessionTools,
  ...fileTools,
  ...userTools,
  ...loginTools,
  ...processTools,
  ...serviceTools,
  ...networkTools,
  ...packageTools,
  ...containerTools,
]);

class UnknownToolException implements Exception {
  UnknownToolException(this.name, this.available);

  final String name;
  final List<String> available;

  @override
  String toString() =>
      'Unknown tool "$name". Available tools: ${available.join(', ')}.';
}

/// Which tools are offered to the model and how they are executed.
class ToolRegistry {
  ToolRegistry({
    List<ToolDefinition>? tools,
    Set<ToolCategory>? enabledCategories,
    this.disabledTools = const {},
  }) : tools = tools ?? allTools,
       enabledCategories = enabledCategories ?? ToolCategory.values.toSet();

  final List<ToolDefinition> tools;
  final Set<ToolCategory> enabledCategories;
  final Set<String> disabledTools;

  /// Tools offered for the given session.
  List<ToolDefinition> available(RemoteSession? session) => [
    for (final tool in tools)
      if (enabledCategories.contains(tool.category) &&
          !disabledTools.contains(tool.name) &&
          (!tool.requiresUserSwitching || (session?.canSwitchUser ?? false)))
        tool,
  ];

  /// Function declarations for the model.
  List<Map<String, Object?>> schemas(RemoteSession? session) => [
    for (final tool in available(session)) tool.toFunctionSchema(),
  ];

  ToolDefinition? find(String name) {
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  /// Validates a call coming from the model. Throws [UnknownToolException]
  /// or [ToolArgumentException] with a message meant for the model.
  PreparedToolCall prepare(
    String id,
    String name,
    Map<String, Object?> rawArgs,
    RemoteSession session,
  ) {
    final offered = available(session);
    final tool = offered.where((t) => t.name == name).firstOrNull;
    if (tool == null) {
      throw UnknownToolException(name, [for (final t in offered) t.name]);
    }
    final args = tool.parseArguments(rawArgs);
    final script = tool.script(args);
    final runAs = tool.runAsFor?.call(args, session) ?? session.effectiveUser;
    return PreparedToolCall(
      id: id,
      tool: tool,
      args: args,
      script: script,
      fullCommand: session.buildCommand(
        script,
        asUser: runAs == session.loginUser ? null : runAs,
      ),
      runAs: runAs,
      cwd: session.cwd,
    );
  }

  /// Runs a prepared call. Never throws - errors become a [ToolResult].
  /// [onOutput] receives the command output live while it runs.
  Future<ToolResult> execute(
    PreparedToolCall call,
    RemoteSession session, {
    int maxOutputBytes = 512 * 1024,
    OutputListener? onOutput,
  }) async {
    final ToolResult result;
    try {
      final handler = call.tool.handler;
      if (handler != null) {
        result = await handler(call, session, onOutput);
      } else {
        final r = await session.run(
          call.script,
          asUser: call.runAs == session.effectiveUser ? null : call.runAs,
          timeout: call.tool.timeout,
          maxOutputBytes: maxOutputBytes,
          onOutput: onOutput,
        );
        result = ToolResult.fromCommand(r);
      }
    } on ToolArgumentException catch (e) {
      return ToolResult.failure(e.message);
    } on RemoteConnectionException catch (e) {
      return ToolResult.failure('SSH: ${e.message}');
    } catch (e) {
      return ToolResult.failure('Unexpected error: $e');
    }
    _annotate(call, result);
    return result;
  }

  void _annotate(PreparedToolCall call, ToolResult result) {
    if (call.tool.binaryCheck && result.stdout.contains('\u0000')) {
      result.stdout =
          '[Binary content (${result.stdout.length} bytes) is not '
          'shown. Use binary_peek or file_type.]';
    }
    final notes = <String>[
      if (result.note != null) result.note!,
      if (result.exitCode != null &&
          call.tool.exitCodeMeaning.containsKey(result.exitCode))
        call.tool.exitCodeMeaning[result.exitCode]!,
      if (result.timedOut)
        'The command was stopped after ${call.tool.timeout.inSeconds} s; '
            'narrow the search (more specific path or filters).',
      if (result.truncated)
        'The output was too large and was cut; use more specific filters.',
      if (result.stderr.contains('a password is required') ||
          result.stderr.contains('no password was provided') ||
          result.stderr.contains('incorrect password'))
        'sudo needs a (correct) password - it can be set in the server '
            'profile (user switching password).',
      if (result.stderr.contains('Authentication failure') &&
          call.fullCommand.contains(' su '))
        'su authentication failed - check the user switching password in '
            'the server profile.',
      ...call.args.warnings,
    ];
    result.note = notes.isEmpty ? null : notes.join(' ');
  }

  /// Text returned to the model for a tool result.
  static String formatForModel(ToolResult result, {int maxChars = 12000}) {
    final out = StringBuffer();
    if (result.error != null) {
      out.writeln('[error] ${result.error}');
      return out.toString().trim();
    }
    final exit = result.exitCode;
    out.writeln(exit == null ? '[exit code unknown]' : '[exit code $exit]');
    if (result.note != null) out.writeln('[note] ${result.note}');
    final stdout = result.stdout.trimRight();
    final stderr = result.stderr.trimRight();
    if (stdout.isEmpty && stderr.isEmpty) {
      out.writeln('(no output)');
    }
    if (stdout.isNotEmpty) {
      final budget = stderr.isEmpty ? maxChars : (maxChars * 0.8).round();
      out.writeln(truncateMiddle(stdout, budget));
    }
    if (stderr.isNotEmpty) {
      out.writeln('[stderr]');
      out.writeln(
        truncateMiddle(stderr, (maxChars * 0.2).round().clamp(400, 4000)),
      );
    }
    return out.toString().trimRight();
  }
}

/// Keeps the beginning and the end of a long text.
String truncateMiddle(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  final head = (maxChars * 0.7).round();
  final tail = maxChars - head;
  final omitted = text.substring(head, text.length - tail);
  final omittedLines = '\n'.allMatches(omitted).length;
  return '${text.substring(0, head)}\n'
      '[... ${omitted.length} characters ($omittedLines lines) omitted ...]\n'
      '${text.substring(text.length - tail)}';
}
