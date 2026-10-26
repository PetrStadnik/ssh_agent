/// Receives output of a running command as it arrives (already decoded).
typedef OutputListener = void Function(String text, bool isStderr);

/// Abstraction of "a place where a command can be executed".
///
/// The real implementation is [SshExecutor]; tests use fakes. Keeping the
/// interface tiny makes it easy to add other transports later (e.g. a jump
/// host or a server-side helper used by a mobile client).
abstract class RemoteExecutor {
  /// Human readable name of the target, e.g. `prod-web (root@10.0.0.5)`.
  String get label;

  /// User name used to log in.
  String get username;

  /// Host name or IP address.
  String get host;

  /// Runs [command] and collects its output.
  ///
  /// * [timeout] - the channel is closed when the command runs longer.
  /// * [maxOutputBytes] - stdout and stderr are each cut at this size.
  /// * [stdinData] - written to stdin, then stdin is closed. Stdin is always
  ///   closed so that no command can ever wait for input.
  /// * [pty] - allocate a pseudo terminal (needed by `su`).
  /// * [promptPassword] - when a `Password:` prompt appears on a pty, this
  ///   password is typed once.
  /// * [onOutput] - called with every piece of output while the command
  ///   runs, so that the user can watch it live.
  Future<CommandResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 512 * 1024,
    String? stdinData,
    bool pty = false,
    String? promptPassword,
    OutputListener? onOutput,
  });

  /// Checks/establishes the connection.
  Future<void> connect();

  /// Whether a connection is currently open.
  bool get isConnected;

  /// Closes the connection.
  Future<void> close();
}

/// Result of a single remote command.
class CommandResult {
  const CommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    this.timedOut = false,
    this.truncated = false,
  });

  final String stdout;
  final String stderr;

  /// Null when the server did not report it (killed, timed out...).
  final int? exitCode;
  final Duration duration;
  final bool timedOut;

  /// True when the output was larger than the limit and was cut.
  final bool truncated;

  bool get success => exitCode == 0 && !timedOut;
}

/// Error while connecting / talking to the server (not a failing command).
class RemoteConnectionException implements Exception {
  RemoteConnectionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
