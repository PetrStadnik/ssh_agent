import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_dialog.dart';

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  late final _instructions = TextEditingController(
    text: context.read<AppState>().settings.extraInstructions,
  );
  final Set<ToolCategory> _open = {};

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final c = context.colors;
    return SettingsSection(
      title: 'Agent a nástroje',
      description:
          'Agent smí volat jen předdefinované funkce níže. Všechny pouze čtou – '
          'žádná nemění soubory, oprávnění, služby ani procesy. Argumenty od '
          'modelu se vždy bezpečně escapují.',
      children: [
        SettingsCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Potvrzovat každý příkaz'),
                subtitle: const Text(
                  'Před spuštěním na serveru se zobrazí přesný příkaz ke schválení.',
                ),
                value: s.confirmCommands,
                onChanged: (v) =>
                    state.updateSettings((s) => s.confirmCommands = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rozbalovat výstupy příkazů'),
                subtitle: const Text(
                  'Karty volaných funkcí v chatu ukazují výstup hned, ne až po kliknutí.',
                ),
                value: s.expandToolOutput,
                onChanged: (v) =>
                    state.updateSettings((s) => s.expandToolOutput = v),
              ),
            ],
          ),
        ),
        FieldRow(
          label: 'Maximální počet kroků na jednu odpověď: ${s.maxSteps}',
          child: Slider(
            min: 5,
            max: 50,
            divisions: 9,
            value: s.maxSteps.toDouble().clamp(5, 50),
            label: '${s.maxSteps}',
            onChanged: (v) =>
                state.updateSettings((s) => s.maxSteps = v.round()),
          ),
        ),
        FieldRow(
          label: 'Délka výstupu předaná modelu',
          help:
              'Delší výstupy se uprostřed zkrátí (začátek a konec zůstane). '
              'Vy v chatu vždy vidíte celý výstup.',
          child: DropdownButtonFormField<int>(
            initialValue:
                [4000, 8000, 12000, 20000, 40000].contains(s.maxToolOutputChars)
                ? s.maxToolOutputChars
                : 12000,
            items: const [
              DropdownMenuItem(
                value: 4000,
                child: Text('4 000 znaků (malé modely)'),
              ),
              DropdownMenuItem(value: 8000, child: Text('8 000 znaků')),
              DropdownMenuItem(
                value: 12000,
                child: Text('12 000 znaků (doporučeno)'),
              ),
              DropdownMenuItem(value: 20000, child: Text('20 000 znaků')),
              DropdownMenuItem(
                value: 40000,
                child: Text('40 000 znaků (velký kontext)'),
              ),
            ],
            onChanged: (v) =>
                state.updateSettings((s) => s.maxToolOutputChars = v ?? 12000),
          ),
        ),
        FieldRow(
          label: 'Jazyk odpovědí',
          child: DropdownButtonFormField<String>(
            initialValue: s.answerLanguage,
            items: const [
              DropdownMenuItem(value: 'Czech', child: Text('Čeština')),
              DropdownMenuItem(value: 'Slovak', child: Text('Slovenština')),
              DropdownMenuItem(value: 'English', child: Text('Angličtina')),
              DropdownMenuItem(value: 'German', child: Text('Němčina')),
            ],
            onChanged: (v) =>
                state.updateSettings((s) => s.answerLanguage = v ?? 'Czech'),
          ),
        ),
        FieldRow(
          label: 'Vlastní pokyny pro agenta',
          help:
              'Např. „Logy aplikace jsou v /srv/app/logs“ nebo „Odpovídej stručně“.',
          child: TextField(
            controller: _instructions,
            minLines: 2,
            maxLines: 5,
            onTapOutside: (_) => state.updateSettings(
              (s) => s.extraInstructions = _instructions.text,
            ),
            onChanged: (_) {},
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Dostupné funkce (${allTools.length})',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vypnutím skupiny ji agent neuvidí – pomůže to menším modelům '
          '(méně definic = kratší prompt).',
          style: TextStyle(fontSize: 12.5, color: c.textTertiary),
        ),
        const SizedBox(height: 10),
        for (final category in ToolCategory.values)
          _CategoryTile(
            category: category,
            enabled: s.enabledCategories.contains(category),
            open: _open.contains(category),
            onToggleOpen: () => setState(
              () => _open.contains(category)
                  ? _open.remove(category)
                  : _open.add(category),
            ),
            onChanged: (v) => state.updateSettings(
              (s) => v
                  ? s.enabledCategories.add(category)
                  : s.enabledCategories.remove(category),
            ),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.enabled,
    required this.open,
    required this.onToggleOpen,
    required this.onChanged,
  });

  final ToolCategory category;
  final bool enabled;
  final bool open;
  final VoidCallback onToggleOpen;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tools = allTools.where((t) => t.category == category).toList();
    return SettingsCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onToggleOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          open
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 20,
                          color: c.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          category.label,
                          style: TextStyle(fontSize: 14, color: c.text),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tools.length}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Switch(value: enabled, onChanged: onChanged),
            ],
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tool in tools)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              tool.name,
                              style: monoStyle(
                                context,
                                size: 12.5,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              tool.summary,
                              style: TextStyle(
                                fontSize: 13,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
