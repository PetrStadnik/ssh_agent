// Generates docs/NASTROJE.md from the tool definitions:
//   dart run tool/gen_tools_doc.dart > ../../docs/NASTROJE.md
import 'dart:convert';

import 'package:ssh_agent_core/ssh_agent_core.dart';

void main() {
  final out = StringBuffer()
    ..writeln('# Katalog nástrojů agenta')
    ..writeln()
    ..writeln(
      '> Soubor je generovaný z kódu (`packages/ssh_agent_core/tool/gen_tools_doc.dart`), '
      'needitujte ho ručně.',
    )
    ..writeln()
    ..writeln(
      'Agent smí volat **jen** tyto předdefinované funkce (${allTools.length}). '
      'Všechny pouze čtou – žádná nevytváří, nemění ani nemaže soubory, '
      'nemění oprávnění, nespouští/nezastavuje služby ani neukončuje procesy. '
      'Každý argument od modelu je validován a v příkazu je vždy v uvozovkách '
      '(viz [BEZPECNOST.md](BEZPECNOST.md)). Popisy pro model jsou anglicky, '
      'protože lokální modely angličtině v definicích nástrojů rozumí nejspolehlivěji.',
    )
    ..writeln()
    ..writeln(
      'Velikost všech definic posílaných modelu: '
      '~${(jsonEncode([for (final t in allTools) t.toFunctionSchema()]).length / 1000).toStringAsFixed(1)} tis. znaků '
      '(≈ ${(jsonEncode([for (final t in allTools) t.toFunctionSchema()]).length / 3.6 / 1000).toStringAsFixed(1)} tis. tokenů). '
      'Skupiny lze v nastavení vypnout.',
    )
    ..writeln();

  for (final category in ToolCategory.values) {
    final tools = allTools.where((t) => t.category == category).toList();
    out
      ..writeln('## ${category.label}')
      ..writeln()
      ..writeln('| Funkce | Co dělá | Parametry |')
      ..writeln('|---|---|---|');
    for (final t in tools) {
      final params = t.params.isEmpty
          ? '–'
          : t.params
                .map((p) {
                  final type = switch (p.type) {
                    ParamType.string =>
                      p.enumValues == null ? 'text' : p.enumValues!.join('\\|'),
                    ParamType.integer => 'číslo',
                    ParamType.boolean => 'ano/ne',
                  };
                  final req = p.required ? ' **povinný**' : '';
                  final def = p.defaultValue == null
                      ? ''
                      : ', výchozí `${p.defaultValue}`';
                  return '`${p.name}` ($type$def)$req';
                })
                .join('<br>');
      out.writeln(
        '| `${t.name}` | ${t.summary}${t.requiresUserSwitching ? ' *(jen když profil povoluje přepínání uživatele)*' : ''} | $params |',
      );
    }
    out.writeln();
  }

  out
    ..writeln('## Příklad: co se skutečně spustí')
    ..writeln()
    ..writeln(
      'Volání `grep(pattern: "Failed password", path: "/var/log/auth.log", mode: "fixed")` '
      'se na serveru provede jako:',
    )
    ..writeln()
    ..writeln('```sh');
  final session = RemoteSession(executor: _DocExecutor());
  final registry = ToolRegistry();
  final call = registry.prepare('x', 'grep', {
    'pattern': 'Failed password',
    'path': '/var/log/auth.log',
    'mode': 'fixed',
  }, session);
  out
    ..writeln(call.script)
    ..writeln('```')
    ..writeln()
    ..writeln(
      'Přesný řetězec odeslaný přes SSH (obálka nastaví prostředí, pracovní '
      'adresář a použije bash kvůli `pipefail`, jinak POSIX `sh`):',
    )
    ..writeln()
    ..writeln('```sh')
    ..writeln(call.fullCommand)
    ..writeln('```')
    ..writeln()
    ..writeln(
      'Obojí vidíte v aplikaci u každého volání (karta funkce → ikona „rozbalit“).',
    );
  print(out.toString().trimRight());
}

class _DocExecutor implements RemoteExecutor {
  @override
  String get label => 'server';
  @override
  String get username => 'admin';
  @override
  String get host => 'server';
  @override
  bool get isConnected => false;
  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {}
  @override
  Future<CommandResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 0,
    String? stdinData,
    bool pty = false,
    String? promptPassword,
    OutputListener? onOutput,
  }) => throw UnimplementedError();
}
