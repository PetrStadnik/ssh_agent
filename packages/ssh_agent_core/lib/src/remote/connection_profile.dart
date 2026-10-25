/// How the agent may run commands as another user.
enum ElevationMethod {
  /// Commands always run as the login user; `switch_user` is disabled.
  none,

  /// `sudo -u <user>` (password, if needed, is sent on stdin with `sudo -S`).
  sudo,

  /// `su -s /bin/sh <user> -c ...` on a pseudo terminal, the password is typed
  /// when `Password:` is shown.
  su,
}

enum SshAuthMethod { password, privateKey }

/// A saved SSH connection. Contains no secrets - those live in
/// [ProfileSecrets] and are stored in the OS key store by the app.
class ConnectionProfile {
  ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = SshAuthMethod.privateKey,
    this.privateKeyPath,
    this.hostKeyType,
    this.hostKeyFingerprint,
    this.elevation = ElevationMethod.none,
    this.initialDirectory,
    this.notes = '',
    this.color = 0xFFC96442,
  });

  final String id;
  String name;
  String host;
  int port;
  String username;
  SshAuthMethod authMethod;

  /// Optional path of a private key file on this computer. The key content
  /// pasted in the UI is stored in [ProfileSecrets.privateKey] instead.
  String? privateKeyPath;

  /// Trusted host key (`SHA256:...`), set on first connect (TOFU).
  String? hostKeyType;
  String? hostKeyFingerprint;

  ElevationMethod elevation;

  /// Working directory the agent starts in (default: home directory).
  String? initialDirectory;
  String notes;

  /// ARGB colour used for the badge in the UI.
  int color;

  String get address => port == 22 ? '$username@$host' : '$username@$host:$port';

  String get label => '$name ($address)';

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'privateKeyPath': privateKeyPath,
        'hostKeyType': hostKeyType,
        'hostKeyFingerprint': hostKeyFingerprint,
        'elevation': elevation.name,
        'initialDirectory': initialDirectory,
        'notes': notes,
        'color': color,
      };

  factory ConnectionProfile.fromJson(Map<String, Object?> json) =>
      ConnectionProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 22,
        username: json['username'] as String? ?? '',
        authMethod: SshAuthMethod.values.firstWhere(
          (m) => m.name == json['authMethod'],
          orElse: () => SshAuthMethod.privateKey,
        ),
        privateKeyPath: json['privateKeyPath'] as String?,
        hostKeyType: json['hostKeyType'] as String?,
        hostKeyFingerprint: json['hostKeyFingerprint'] as String?,
        elevation: ElevationMethod.values.firstWhere(
          (m) => m.name == json['elevation'],
          orElse: () => ElevationMethod.none,
        ),
        initialDirectory: json['initialDirectory'] as String?,
        notes: json['notes'] as String? ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0xFFC96442,
      );

  ConnectionProfile copy() => ConnectionProfile.fromJson(toJson());
}

/// Secrets of a profile. Never sent to the language model.
class ProfileSecrets {
  const ProfileSecrets({
    this.password,
    this.privateKey,
    this.passphrase,
    this.elevationPassword,
  });

  /// SSH password (password authentication).
  final String? password;

  /// Private key in OpenSSH / PEM format.
  final String? privateKey;

  /// Passphrase of an encrypted private key.
  final String? passphrase;

  /// Password for sudo (own password) or su (target user's password).
  final String? elevationPassword;

  Map<String, String> toMap() => {
        'password': ?password,
        'privateKey': ?privateKey,
        'passphrase': ?passphrase,
        'elevationPassword': ?elevationPassword,
      };

  factory ProfileSecrets.fromMap(Map<String, String?> map) => ProfileSecrets(
        password: _nonEmpty(map['password']),
        privateKey: _nonEmpty(map['privateKey']),
        passphrase: _nonEmpty(map['passphrase']),
        elevationPassword: _nonEmpty(map['elevationPassword']),
      );

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
