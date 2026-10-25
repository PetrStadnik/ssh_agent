import '../../util/shell.dart';

export '../../util/shell.dart';
export '../tool.dart';

final RegExp _placeholder = RegExp(r'@([A-Z][A-Z0-9_]*)@');

/// Fills `@NAME@` placeholders of a shell template in a single pass (values
/// are never rescanned). Every value must already be shell-safe (quoted or
/// validated).
String fill(String template, [Map<String, String> vars = const {}]) =>
    template.replaceAllMapped(_placeholder, (m) {
      final value = vars[m[1]];
      if (value == null) {
        throw StateError('Missing template variable ${m[1]}');
      }
      return value;
    });

/// `| awk ...` that keeps at most [n] lines and reports the rest.
String limit(int n) => '| ${limitLines(n)}';

/// Exports [value] as an environment variable for awk filters (`ENVIRON`).
/// Using the environment avoids awk's escape processing of `-v` values.
String exportVar(String name, String? value) =>
    'export $name=${shQuote(value ?? '')}';
