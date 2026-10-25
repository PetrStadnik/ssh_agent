import '../util/shell.dart';
import 'connection_profile.dart';
import 'remote_executor.dart';

/// State of the agent on one server: working directory and the user the
/// commands run as. Builds the final command line around a tool script.
class RemoteSession {
  RemoteSession({
    required this.executor,
    this.elevation = ElevationMethod.none,
    this.elevationPassword,
    String? initialDirectory,
  }) : cwd = (initialDirectory == null || initialDirectory.trim().isEmpty)
           ? null
           : initialDirectory.trim();

  final RemoteExecutor executor;
  final ElevationMethod elevation;
  final String? elevationPassword;

  /// Virtual working directory. Each command starts with `cd` into it;
  /// `null` means the home directory of the user.
  String? cwd;

  /// User the commands run as (`null` = login user).
  String? runAs;

  String get loginUser => executor.username;

  /// The user commands effectively run as.
  String get effectiveUser => runAs ?? loginUser;

  bool get canSwitchUser => elevation != ElevationMethod.none;

  /// Environment that makes the output predictable and never interactive.
  static const String _prelude =
      'export LC_ALL=C LANG=C PAGER=cat SYSTEMD_PAGER= SYSTEMD_COLORS=0 '
      'NO_COLOR=1 TERM=dumb\n'
      '(set -o pipefail) 2>/dev/null && set -o pipefail';

  /// The script as executed by `sh`, including the working directory.
  String scriptWithContext(String script) {
    final dir = cwd;
    final cd = dir == null
        ? ''
        : 'cd -- ${shPath(dir, allowGlob: false)} || exit 1\n';
    return '$_prelude\n$cd$script';
  }

  /// Runs the script (passed as `$1`) with bash when the server has it -
  /// mainly for `pipefail`, so that exit codes survive output limiting -
  /// and with POSIX sh otherwise.
  static const String _launcher =
      r'if command -v bash >/dev/null 2>&1; then exec bash -c "$1"; else eval "$1"; fi';

  String _shCommand(String script) =>
      'sh -c ${shQuote(_launcher)} sh ${shQuote(scriptWithContext(script))}';

  /// The exact command line sent over SSH.
  String buildCommand(String script, {String? asUser}) {
    final user = asUser ?? runAs;
    final command = _shCommand(script);
    if (user == null || user == loginUser) return command;
    final quotedUser = shQuote(user);
    switch (elevation) {
      case ElevationMethod.none:
        throw ToolArgumentException(
          'Switching user is disabled for this server profile.',
        );
      case ElevationMethod.sudo:
        final mode = elevationPassword == null ? '-n' : "-S -p ''";
        return 'sudo $mode -u $quotedUser -- $command';
      case ElevationMethod.su:
        // su hands the string to `/bin/sh -c`.
        return 'LC_ALL=C su -s /bin/sh $quotedUser -c ${shQuote(command)}';
    }
  }

  /// Runs a tool script in the current context.
  Future<CommandResult> run(
    String script, {
    String? asUser,
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 512 * 1024,
  }) {
    final user = asUser ?? runAs;
    final command = buildCommand(script, asUser: asUser);
    final elevated = user != null && user != loginUser;
    if (elevated && elevation == ElevationMethod.su) {
      return executor.execute(
        command,
        timeout: timeout,
        maxOutputBytes: maxOutputBytes,
        pty: true,
        promptPassword: elevationPassword,
      );
    }
    return executor.execute(
      command,
      timeout: timeout,
      maxOutputBytes: maxOutputBytes,
      stdinData:
          elevated &&
              elevation == ElevationMethod.sudo &&
              elevationPassword != null
          ? '$elevationPassword\n'
          : null,
    );
  }
}
