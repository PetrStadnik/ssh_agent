import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_dialog.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final c = context.colors;
    return SettingsSection(
      title: 'Vzhled a data',
      children: [
        FieldRow(
          label: 'Motiv',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined, size: 18),
                label: Text('Podle systému'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 18),
                label: Text('Světlý'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 18),
                label: Text('Tmavý'),
              ),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) =>
                state.updateSettings((s) => s.themeMode = v.first),
          ),
        ),
        SettingsCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Patkové písmo odpovědí'),
            subtitle: const Text(
              'Odpovědi agenta sázet patkovým písmem (jako Claude).',
            ),
            value: s.serifAnswers,
            onChanged: (v) => state.updateSettings((s) => s.serifAnswers = v),
          ),
        ),
        const SizedBox(height: 10),
        FieldRow(
          label: 'Kde jsou uložená data',
          help:
              'Nastavení, servery (bez hesel) a konverzace jsou v JSON '
              'souborech. Hesla, klíče a API klíč jsou v zabezpečeném úložišti '
              'systému (Windows: šifrováno, klíč ve Správci pověření; Android '
              'Keystore; iOS Keychain).',
          child: SelectableText(
            state.storage.location,
            style: monoStyle(context, size: 12.5, color: c.textSecondary),
          ),
        ),
        FieldRow(
          label: 'O aplikaci',
          child: Text(
            'SSH Agent 0.1 – read-only AI agent pro Linuxové servery s lokálním '
            'modelem. Rozhraní inspirované aplikací Claude. Zdrojový kód a '
            'dokumentace: složka docs/ v repozitáři.',
            style: TextStyle(color: c.textSecondary, height: 1.45),
          ),
        ),
      ],
    );
  }
}
