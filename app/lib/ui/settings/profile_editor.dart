import 'dart:convert';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_dialog.dart';

const List<int> profileColors = [
  0xFFC96442,
  0xFF3D8A5A,
  0xFF3B6EA8,
  0xFF8E5BB5,
  0xFFB7791F,
  0xFF5F6B73,
];

Future<void> showProfileEditor(
  BuildContext context, {
  ConnectionProfile? existing,
}) => showDialog(
  context: context,
  builder: (_) => ProfileEditor(existing: existing),
);

/// Form for adding / editing an SSH connection.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, this.existing});

  final ConnectionProfile? existing;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final ConnectionProfile _profile =
      widget.existing?.copy() ??
      ConnectionProfile(
        id: AppState.newId(),
        name: '',
        host: '',
        username: 'root',
        color: profileColors[0],
      );

  late final _name = TextEditingController(text: _profile.name);
  late final _host = TextEditingController(text: _profile.host);
  late final _port = TextEditingController(text: '${_profile.port}');
  late final _user = TextEditingController(text: _profile.username);
  late final _keyPath = TextEditingController(
    text: _profile.privateKeyPath ?? '',
  );
  late final _cwd = TextEditingController(
    text: _profile.initialDirectory ?? '',
  );
  late final _notes = TextEditingController(text: _profile.notes);
  final _password = TextEditingController();
  final _keyText = TextEditingController();
  final _passphrase = TextEditingController();
  final _elevationPassword = TextEditingController();

  bool _loadingSecrets = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _loadSecrets();
  }

  Future<void> _loadSecrets() async {
    if (widget.existing != null) {
      final secrets = await context.read<AppState>().secretsFor(_profile.id);
      _password.text = secrets.password ?? '';
      _keyText.text = secrets.privateKey ?? '';
      _passphrase.text = secrets.passphrase ?? '';
      _elevationPassword.text = secrets.elevationPassword ?? '';
    }
    if (mounted) setState(() => _loadingSecrets = false);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _user,
      _keyPath,
      _cwd,
      _notes,
      _password,
      _keyText,
      _passphrase,
      _elevationPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ProfileSecrets _secrets() {
    String? value(TextEditingController c) => c.text.isEmpty ? null : c.text;
    final key = _profile.authMethod == SshAuthMethod.privateKey;
    return ProfileSecrets(
      password: key ? null : value(_password),
      privateKey: key && _keyText.text.trim().isNotEmpty ? _keyText.text : null,
      passphrase: key ? value(_passphrase) : null,
      elevationPassword: _profile.elevation == ElevationMethod.none
          ? null
          : value(_elevationPassword),
    );
  }

  void _apply() {
    _profile
      ..name = _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim()
      ..host = _host.text.trim()
      ..port = int.tryParse(_port.text.trim()) ?? 22
      ..username = _user.text.trim()
      ..privateKeyPath = _keyPath.text.trim().isEmpty
          ? null
          : _keyPath.text.trim()
      ..initialDirectory = _cwd.text.trim().isEmpty ? null : _cwd.text.trim()
      ..notes = _notes.text;
  }

  Future<void> _pickKey() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Vyberte privátní klíč',
    );
    if (file == null) return;
    if (file.path != null) {
      setState(() => _keyPath.text = file.path!);
    } else {
      // Mobile: the picker returns content, not a stable path.
      final bytes = await file.readAsBytes();
      setState(() => _keyText.text = utf8.decode(bytes, allowMalformed: true));
    }
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    _apply();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final info = await context.read<AppState>().testConnection(
        _profile,
        _secrets(),
      );
      _testOk = true;
      _testResult = 'Připojeno: $info';
    } catch (e) {
      _testOk = false;
      _testResult = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _apply();
    await context.read<AppState>().saveProfile(_profile, _secrets());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(narrow ? 8 : 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820),
        child: _loadingSecrets
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.existing == null
                                  ? 'Nový server'
                                  : 'Upravit ${widget.existing!.name}',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                        children: [
                          _row([
                            Expanded(
                              flex: 3,
                              child: FieldRow(
                                label: 'Název',
                                child: TextFormField(
                                  key: const Key('profile-name'),
                                  controller: _name,
                                  decoration: const InputDecoration(
                                    hintText: 'např. web-produkce',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: _colorPicker()),
                          ]),
                          _row([
                            Expanded(
                              flex: 4,
                              child: FieldRow(
                                label: 'Host',
                                child: TextFormField(
                                  key: const Key('profile-host'),
                                  controller: _host,
                                  decoration: const InputDecoration(
                                    hintText: 'IP adresa nebo doména',
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Zadejte adresu serveru'
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: FieldRow(
                                label: 'Port',
                                child: TextFormField(
                                  controller: _port,
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    final p = int.tryParse(v ?? '');
                                    return p == null || p < 1 || p > 65535
                                        ? 'Port 1–65535'
                                        : null;
                                  },
                                ),
                              ),
                            ),
                          ]),
                          FieldRow(
                            label: 'Uživatel',
                            child: TextFormField(
                              key: const Key('profile-user'),
                              controller: _user,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Zadejte uživatele'
                                  : null,
                            ),
                          ),
                          FieldRow(
                            label: 'Přihlášení',
                            child: SegmentedButton<SshAuthMethod>(
                              segments: const [
                                ButtonSegment(
                                  value: SshAuthMethod.privateKey,
                                  icon: Icon(Icons.key_rounded, size: 18),
                                  label: Text('Privátní klíč'),
                                ),
                                ButtonSegment(
                                  value: SshAuthMethod.password,
                                  icon: Icon(Icons.password_rounded, size: 18),
                                  label: Text('Heslo'),
                                ),
                              ],
                              selected: {_profile.authMethod},
                              onSelectionChanged: (s) =>
                                  setState(() => _profile.authMethod = s.first),
                            ),
                          ),
                          if (_profile.authMethod ==
                              SshAuthMethod.privateKey) ...[
                            FieldRow(
                              label: 'Soubor s klíčem',
                              help:
                                  'OpenSSH/PEM klíč, např. C:\\Users\\vy\\.ssh\\id_ed25519. '
                                  'Klíč z PuTTY (.ppk) převeďte v PuTTYgen (Export OpenSSH key).',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _keyPath,
                                      decoration: const InputDecoration(
                                        hintText: '~/.ssh/id_ed25519',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _pickKey,
                                    child: const Text('Vybrat…'),
                                  ),
                                ],
                              ),
                            ),
                            FieldRow(
                              label: '…nebo vložte obsah klíče',
                              help:
                                  'Má přednost před souborem. Uloží se do '
                                  'zabezpečeného úložiště systému.',
                              child: TextFormField(
                                controller: _keyText,
                                minLines: 2,
                                maxLines: 5,
                                style: monoStyle(context, size: 11.5),
                                decoration: const InputDecoration(
                                  hintText:
                                      '-----BEGIN OPENSSH PRIVATE KEY-----',
                                ),
                              ),
                            ),
                            FieldRow(
                              label: 'Heslo ke klíči (passphrase)',
                              child: TextFormField(
                                controller: _passphrase,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: 'jen pokud je klíč zašifrovaný',
                                ),
                              ),
                            ),
                          ] else
                            FieldRow(
                              label: 'Heslo',
                              child: TextFormField(
                                key: const Key('profile-password'),
                                controller: _password,
                                obscureText: true,
                              ),
                            ),
                          FieldRow(
                            label: 'Přepínání uživatele (switch_user / su)',
                            help:
                                'Umožní agentovi spouštět čtecí příkazy jako '
                                'jiný uživatel (např. root pro /var/log/btmp). '
                                'sudo: vaše heslo (nebo NOPASSWD), su: heslo '
                                'cílového uživatele.',
                            child: DropdownButtonFormField<ElevationMethod>(
                              initialValue: _profile.elevation,
                              items: const [
                                DropdownMenuItem(
                                  value: ElevationMethod.none,
                                  child: Text('Vypnuto'),
                                ),
                                DropdownMenuItem(
                                  value: ElevationMethod.sudo,
                                  child: Text('sudo -u <uživatel>'),
                                ),
                                DropdownMenuItem(
                                  value: ElevationMethod.su,
                                  child: Text('su <uživatel>'),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => _profile.elevation =
                                    v ?? ElevationMethod.none,
                              ),
                            ),
                          ),
                          if (_profile.elevation != ElevationMethod.none)
                            FieldRow(
                              label: _profile.elevation == ElevationMethod.sudo
                                  ? 'Heslo pro sudo (prázdné = NOPASSWD)'
                                  : 'Heslo pro su (cílového uživatele, typicky root)',
                              child: TextFormField(
                                controller: _elevationPassword,
                                obscureText: true,
                              ),
                            ),
                          FieldRow(
                            label: 'Výchozí adresář',
                            help:
                                'Kde agent začíná (prázdné = domovský adresář).',
                            child: TextFormField(
                              controller: _cwd,
                              decoration: const InputDecoration(
                                hintText: '/var/www',
                              ),
                            ),
                          ),
                          FieldRow(
                            label: 'Poznámka',
                            child: TextFormField(
                              controller: _notes,
                              maxLines: 2,
                            ),
                          ),
                          if (_profile.hostKeyFingerprint != null)
                            FieldRow(
                              label: 'Důvěryhodný klíč serveru',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      '${_profile.hostKeyType ?? ''} ${_profile.hostKeyFingerprint}',
                                      style: monoStyle(context, size: 12),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _profile.hostKeyFingerprint = null;
                                      _profile.hostKeyType = null;
                                    }),
                                    child: const Text('Zapomenout'),
                                  ),
                                ],
                              ),
                            ),
                          if (_testResult != null)
                            ResultLine(text: _testResult!, ok: _testOk),
                        ],
                      ),
                    ),
                    Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _testing ? null : _test,
                            icon: _testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.wifi_tethering_rounded,
                                    size: 18,
                                  ),
                            label: const Text('Otestovat'),
                          ),
                          FilledButton(
                            key: const Key('profile-save'),
                            onPressed: _save,
                            child: const Text('Uložit'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    if (MediaQuery.sizeOf(context).width < 520) {
      return Column(
        children: [
          for (final w in children)
            if (w is Expanded) w.child else if (w is! SizedBox) w,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _colorPicker() => FieldRow(
    label: 'Barva',
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final color in profileColors)
          InkWell(
            onTap: () => setState(() => _profile.color = color),
            customBorder: const CircleBorder(),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _profile.color == color
                      ? context.colors.text
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
