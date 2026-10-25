import '../remote/remote_executor.dart';
import '../remote/remote_session.dart';
import '../util/shell.dart';

/// Groups of tools; the user can enable/disable whole groups in settings.
enum ToolCategory {
  session('Relace a navigace'),
  files('Soubory a adresáře'),
  users('Uživatelé a oprávnění'),
  logins('Přihlášení'),
  processes('Procesy a prostředky'),
  services('Služby, logy a cron'),
  network('Síť'),
  packages('Balíčky a programy'),
  containers('Kontejnery');

  const ToolCategory(this.label);

  /// Czech label for the UI.
  final String label;
}

enum ParamType { string, integer, boolean }

/// One parameter of a tool, exported as JSON schema for the model.
class ToolParam {
  const ToolParam.string(
    this.name,
    this.description, {
    this.required = false,
    this.defaultValue,
    this.enumValues,
  }) : type = ParamType.string,
       min = null,
       max = null;

  const ToolParam.integer(
    this.name,
    this.description, {
    this.required = false,
    this.defaultValue,
    this.min,
    this.max,
  }) : type = ParamType.integer,
       enumValues = null;

  const ToolParam.boolean(this.name, this.description, {this.defaultValue})
    : type = ParamType.boolean,
      required = false,
      enumValues = null,
      min = null,
      max = null;

  final String name;
  final ParamType type;
  final String description;
  final bool required;
  final Object? defaultValue;
  final List<String>? enumValues;
  final int? min;
  final int? max;

  Map<String, Object?> toJsonSchema() {
    final schema = <String, Object?>{
      'type': switch (type) {
        ParamType.string => 'string',
        ParamType.integer => 'integer',
        ParamType.boolean => 'boolean',
      },
      'description': defaultValue == null
          ? description
          : '$description (default: $defaultValue)',
    };
    if (enumValues != null) schema['enum'] = enumValues;
    if (min != null) schema['minimum'] = min;
    if (max != null) schema['maximum'] = max;
    return schema;
  }
}

/// Builds the shell script of a tool from validated arguments.
typedef ScriptBuilder = String Function(ToolArgs args);

/// Custom execution (e.g. `cd` updates the session after the command).
typedef ToolHandler =
    Future<ToolResult> Function(PreparedToolCall call, RemoteSession session);

/// A predefined, read-only action the agent can call.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.category,
    required this.description,
    required this.summary,
    this.params = const [],
    required this.script,
    this.handler,
    this.timeout = const Duration(seconds: 30),
    this.exitCodeMeaning = const {},
    this.binaryCheck = false,
    this.requiresUserSwitching = false,
    this.runAsFor,
  });

  /// Name used by the model (snake_case, ideally matching the Linux command).
  final String name;
  final ToolCategory category;

  /// English description for the model.
  final String description;

  /// Short Czech description for the UI.
  final String summary;
  final List<ToolParam> params;
  final ScriptBuilder script;
  final ToolHandler? handler;
  final Duration timeout;

  /// Explanation of non-zero exit codes that are not errors (grep 1 = no
  /// match, diff 1 = files differ...).
  final Map<int, String> exitCodeMeaning;

  /// Replace binary output (NUL bytes) with a short notice.
  final bool binaryCheck;

  /// Only offered when the server profile allows switching users.
  final bool requiresUserSwitching;

  /// Runs the script as a different user than the session's current one
  /// (used by `switch_user` to verify the target account).
  final String? Function(ToolArgs args, RemoteSession session)? runAsFor;

  /// Function declaration in the format used by Ollama and OpenAI.
  Map<String, Object?> toFunctionSchema() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {for (final p in params) p.name: p.toJsonSchema()},
        'required': [
          for (final p in params)
            if (p.required) p.name,
        ],
      },
    },
  };

  /// Validates and normalises raw arguments sent by the model.
  ToolArgs parseArguments(Map<String, Object?> raw) {
    final values = <String, Object?>{};
    final warnings = <String>[];
    final known = {for (final p in params) p.name};
    for (final key in raw.keys) {
      if (!known.contains(key)) {
        warnings.add('Unknown parameter "$key" ignored.');
      }
    }
    for (final param in params) {
      var value = raw[param.name];
      if (value is String && value.trim().isEmpty && !param.required) {
        value = null;
      }
      if (value == null) {
        if (param.required) {
          throw ToolArgumentException(
            'Missing required parameter "${param.name}" for tool "$name".',
          );
        }
        values[param.name] = param.defaultValue;
        continue;
      }
      values[param.name] = _coerce(param, value);
    }
    return ToolArgs(this, values, warnings);
  }

  Object? _coerce(ToolParam param, Object value) {
    switch (param.type) {
      case ParamType.string:
        final text = value is String ? value : value.toString();
        rejectControlCharacters(text, param.name);
        if (param.enumValues != null) {
          final match = param.enumValues!.where(
            (e) => e.toLowerCase() == text.trim().toLowerCase(),
          );
          if (match.isEmpty) {
            throw ToolArgumentException(
              'Parameter "${param.name}" must be one of: '
              '${param.enumValues!.join(', ')}.',
            );
          }
          return match.first;
        }
        return text;
      case ParamType.integer:
        int? number;
        if (value is int) {
          number = value;
        } else if (value is num) {
          number = value.round();
        } else if (value is String) {
          number =
              int.tryParse(value.trim()) ??
              double.tryParse(value.trim())?.round();
        }
        if (number == null) {
          throw ToolArgumentException(
            'Parameter "${param.name}" must be an integer.',
          );
        }
        if (param.min != null && number < param.min!) number = param.min!;
        if (param.max != null && number > param.max!) number = param.max!;
        return number;
      case ParamType.boolean:
        if (value is bool) return value;
        if (value is num) return value != 0;
        final text = value.toString().trim().toLowerCase();
        if (const ['true', 'yes', '1', 'ano', 'on'].contains(text)) return true;
        if (const ['false', 'no', '0', 'ne', 'off'].contains(text)) {
          return false;
        }
        throw ToolArgumentException(
          'Parameter "${param.name}" must be true or false.',
        );
    }
  }
}

/// Validated arguments of one call with helpers that return shell-safe text.
class ToolArgs {
  ToolArgs(this.tool, this.values, this.warnings);

  final ToolDefinition tool;
  final Map<String, Object?> values;
  final List<String> warnings;

  bool has(String name) => values[name] != null;

  String str(String name) {
    final value = values[name];
    if (value == null) {
      throw ToolArgumentException('Missing parameter "$name".');
    }
    return value as String;
  }

  String? strOrNull(String name) => values[name] as String?;

  int integer(String name) => values[name] as int;

  int? intOrNull(String name) => values[name] as int?;

  bool flag(String name) => (values[name] as bool?) ?? false;

  /// Quoted path (with `~` expansion and `*`/`?` globs).
  String path(String name, {bool allowGlob = true}) =>
      shPath(str(name), parameter: name, allowGlob: allowGlob);

  /// Any string as a single quoted shell word.
  String quoted(String name) => shQuote(str(name));

  /// Value validated by [pattern] and quoted.
  String ident(String name, RegExp pattern, String hint) =>
      shIdentifier(str(name), pattern, name, hint: hint);
}

/// A tool call ready to run: validated arguments + the script.
class PreparedToolCall {
  PreparedToolCall({
    required this.id,
    required this.tool,
    required this.args,
    required this.script,
    required this.fullCommand,
    required this.runAs,
    required this.cwd,
  });

  final String id;
  final ToolDefinition tool;
  final ToolArgs args;

  /// The tool script (shown to the user).
  final String script;

  /// The exact command line sent over SSH (wrapper included).
  final String fullCommand;

  /// User the command runs as.
  final String runAs;

  /// Working directory (null = home directory).
  final String? cwd;
}

/// Outcome of a tool call, shown in the UI and summarised for the model.
class ToolResult {
  ToolResult({
    required this.stdout,
    this.stderr = '',
    this.exitCode,
    this.duration = Duration.zero,
    this.timedOut = false,
    this.truncated = false,
    this.error,
    this.note,
  });

  factory ToolResult.fromCommand(CommandResult result, {String? note}) =>
      ToolResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        duration: result.duration,
        timedOut: result.timedOut,
        truncated: result.truncated,
        note: note,
      );

  factory ToolResult.failure(String error) =>
      ToolResult(stdout: '', error: error);

  String stdout;
  String stderr;
  int? exitCode;
  Duration duration;
  bool timedOut;
  bool truncated;

  /// Error that prevented running the command (bad arguments, no connection).
  String? error;

  /// Extra information for the model and the user (e.g. "cwd is now /etc").
  String? note;

  bool get isError => error != null || timedOut || (exitCode ?? 0) != 0;
}
