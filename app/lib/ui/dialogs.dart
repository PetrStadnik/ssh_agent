import 'package:flutter/material.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../state/app_state.dart';
import '../theme.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'OK',
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: c.danger)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> showRenameDialog(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Přejmenovat konverzaci'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Uložit'),
        ),
      ],
    ),
  );
}

/// Trust-on-first-use dialog for SSH host keys.
Future<bool> showHostKeyDialog(
  BuildContext context,
  HostKeyRequest request,
) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(
        request.changed ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
        color: request.changed ? c.danger : c.accent,
        size: 32,
      ),
      title: Text(
        request.changed
            ? 'POZOR: klíč serveru se změnil!'
            : 'Ověřte klíč serveru',
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.changed
                  ? 'Server ${request.profile.host} se prokazuje jiným klíčem, '
                        'než jaký jste dříve potvrdili. Může jít o přeinstalovaný '
                        'server, ale také o útok (man-in-the-middle). Pokračujte '
                        'jen pokud víte, proč se klíč změnil.'
                  : 'K serveru ${request.profile.host} se připojujete poprvé. '
                        'Porovnejte otisk klíče s hodnotou na serveru '
                        '(příkaz: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub).',
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 14),
            if (request.changed) ...[
              Text('Původní otisk:', style: TextStyle(color: c.textSecondary)),
              SelectableText(
                request.knownFingerprint!,
                style: monoStyle(context, color: c.textSecondary),
              ),
              const SizedBox(height: 8),
              Text('Nový otisk:', style: TextStyle(color: c.textSecondary)),
            ],
            SelectableText(
              '${request.keyType}\n${request.fingerprint}',
              style: monoStyle(context, size: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Odmítnout'),
        ),
        FilledButton(
          style: request.changed
              ? FilledButton.styleFrom(backgroundColor: c.danger)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(request.changed ? 'Přesto důvěřovat' : 'Důvěřovat'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shown before each command when "confirm commands" is on.
Future<bool> showApprovalDialog(
  BuildContext context,
  PreparedToolCall call,
  ConnectionProfile profile,
) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Spustit ${call.tool.name}?'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${call.tool.summary}\nServer: ${profile.name} · uživatel: '
              '${call.runAs} · adresář: ${call.cwd ?? '~'}',
              style: TextStyle(color: c.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.code,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  call.script,
                  style: monoStyle(context, size: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nespouštět'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Spustit'),
        ),
      ],
    ),
  );
  return result ?? false;
}
