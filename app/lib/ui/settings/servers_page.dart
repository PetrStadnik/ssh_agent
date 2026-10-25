import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../dialogs.dart';
import '../widgets.dart';
import 'profile_editor.dart';
import 'settings_dialog.dart';

class ServersPage extends StatefulWidget {
  const ServersPage({super.key, this.openEditor = false});

  /// Open the "add server" form right away.
  final bool openEditor;

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  @override
  void initState() {
    super.initState();
    if (widget.openEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showProfileEditor(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    return SettingsSection(
      title: 'Servery (SSH připojení)',
      description:
          'Uložená připojení, mezi kterými se v chatu přepíná jedním kliknutím. '
          'Hesla a klíče jsou uložené v zabezpečeném úložišti systému. '
          'Doporučení: pro agenta vytvořte na serveru samostatného uživatele '
          's právy jen pro čtení (viz docs/BEZPECNOST.md).',
      trailing: FilledButton.icon(
        key: const Key('add-server'),
        onPressed: () => showProfileEditor(context),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Přidat server'),
      ),
      children: [
        if (!state.storage.secureStorageAvailable)
          SettingsCard(
            child: Text(
              'Zabezpečené úložiště systému není dostupné – hesla a klíče se '
              'uloží jen do zavření aplikace (na Linuxu nainstalujte a spusťte '
              'gnome-keyring nebo jiný Secret Service).',
              style: TextStyle(color: c.warning),
            ),
          ),
        if (state.profiles.isEmpty)
          SettingsCard(
            child: Text(
              'Zatím žádný server.',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        for (final profile in state.profiles)
          SettingsCard(
            child: Row(
              children: [
                ServerDot(
                  color: Color(profile.color),
                  connected: state.isConnected(profile.id),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          profile.address,
                          profile.authMethod == SshAuthMethod.privateKey
                              ? 'klíč'
                              : 'heslo',
                          if (profile.elevation != ElevationMethod.none)
                            'přepínání uživatele: ${profile.elevation.name}',
                          if (state.isConnected(profile.id)) 'připojeno',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                      if (profile.hostKeyFingerprint != null)
                        Text(
                          profile.hostKeyFingerprint!,
                          style: monoStyle(
                            context,
                            size: 11,
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (state.isConnected(profile.id))
                  SoftIconButton(
                    icon: Icons.link_off_rounded,
                    tooltip: 'Odpojit',
                    onPressed: () => state.disconnect(profile.id),
                  ),
                SoftIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Upravit',
                  onPressed: () =>
                      showProfileEditor(context, existing: profile),
                ),
                SoftIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Smazat',
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Smazat server ${profile.name}?',
                      message:
                          'Smaže se uložené připojení včetně hesel a klíčů. '
                          'Konverzace zůstanou.',
                      confirm: 'Smazat',
                      destructive: true,
                    );
                    if (ok) await state.deleteProfile(profile.id);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
