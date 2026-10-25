/// POSIX shell helpers.
///
/// Every value that comes from the language model is passed through one of
/// these functions. Nothing the model sends is ever concatenated into a command
/// unquoted, so it cannot inject `;`, `|`, `$(...)`, redirections or extra
/// options into the command that is executed on the server.
library;

/// Thrown when a tool argument is invalid. The message is returned to the
/// model so that it can correct the call.
class ToolArgumentException implements Exception {
  ToolArgumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Quotes [value] as a single POSIX shell word: `it's` -> `'it'\''s'`.
String shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Rejects NUL and line breaks, which are never legitimate in the arguments
/// accepted by the tools (paths, patterns, user names...).
void rejectControlCharacters(String value, String parameter) {
  for (final unit in value.codeUnits) {
    if (unit == 0 || unit == 10 || unit == 13) {
      throw ToolArgumentException(
        'Parameter "$parameter" must not contain NUL or line break characters.',
      );
    }
  }
}

final RegExp _tildePrefix = RegExp(r'^~([a-z_][a-z0-9_.-]{0,31})?(?=/|$)');

/// Quotes a path for the shell.
///
/// * `~`, `~/x` and `~user/x` are expanded by the remote shell (the tilde
///   prefix is the only part left unquoted and it is strictly validated);
/// * `*` and `?` are kept as glob wildcards when [allowGlob] is true, every
///   other character is quoted;
/// * a path starting with `-` is prefixed with `./` so that it can never be
///   interpreted as a command line option.
String shPath(String path, {String parameter = 'path', bool allowGlob = true}) {
  rejectControlCharacters(path, parameter);
  if (path.trim().isEmpty) {
    throw ToolArgumentException('Parameter "$parameter" must not be empty.');
  }
  var prefix = '';
  var rest = path;
  final match = _tildePrefix.firstMatch(path);
  if (match != null) {
    final user = match.group(1);
    prefix = user == null ? r'"$HOME"' : '~$user';
    rest = path.substring(match.end);
    if (rest.startsWith('/')) {
      // The slash must stay unquoted, otherwise `~user` is not expanded.
      prefix += '/';
      rest = rest.substring(1);
    }
  } else if (path.startsWith('-')) {
    rest = './$path';
  }
  if (rest.isEmpty) return prefix;
  return prefix + (allowGlob ? _quoteKeepingGlobs(rest) : shQuote(rest));
}

/// Returns true when [path] contains `*` or `?` wildcards.
bool hasGlob(String path) => path.contains('*') || path.contains('?');

String _quoteKeepingGlobs(String value) {
  final out = StringBuffer();
  final literal = StringBuffer();
  void flush() {
    if (literal.isNotEmpty) {
      out.write(shQuote(literal.toString()));
      literal.clear();
    }
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '*' || char == '?') {
      flush();
      out.write(char);
    } else {
      literal.write(char);
    }
  }
  flush();
  return out.toString();
}

/// An `awk` filter that prints at most [maxLines] lines and then reports how
/// many lines were left out. Used instead of `head` so that the model knows
/// the output was cut.
String limitLines(int maxLines) =>
    "awk -v m=$maxLines 'NR<=m{print} END{if(NR>m) printf "
    '"... [%d more lines not shown]\\n", NR-m}\'';

/// Validates a value against [pattern] and returns it quoted.
String shIdentifier(String value, RegExp pattern, String parameter,
    {required String hint}) {
  rejectControlCharacters(value, parameter);
  if (!pattern.hasMatch(value)) {
    throw ToolArgumentException('Invalid value for "$parameter": $hint');
  }
  return shQuote(value);
}

/// Linux user or group name (also allows `user@domain` used by SSSD/AD).
final RegExp userNamePattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.@-]{0,63}\$?$');

/// systemd unit / service name.
final RegExp unitNamePattern = RegExp(r'^[A-Za-z0-9@._:\\-]{1,128}$');

/// Docker / Podman container or image reference.
final RegExp containerNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_./:@-]{0,199}$');

/// Executable name for `which`.
final RegExp commandNamePattern = RegExp(r'^[A-Za-z0-9._+-]{1,100}$');

/// Date expression accepted by `journalctl --since` and `last --since`.
final RegExp timeExpressionPattern = RegExp(r'^[0-9A-Za-z :.+-]{1,40}$');
