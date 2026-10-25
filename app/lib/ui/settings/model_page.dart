import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_dialog.dart';

/// Recommended models (see docs/LOKALNI_MODEL.md for the analysis).
const _recommended = [
  ('qwen3.5:9b', '≈6,6 GB · GPU 8 GB+ · doporučeno'),
  ('qwen3.5:4b', '≈3,4 GB · slabší PC / jen CPU'),
  ('gemma4:e4b', '≈7 GB · alternativa'),
  ('gemma4:26b', '≈17 GB · GPU 16–24 GB'),
  ('gemma4:31b', '≈20 GB · GPU 24 GB'),
  ('gpt-oss:20b', '≈14 GB · GPU 16 GB, slabší čeština'),
];

class ModelPage extends StatefulWidget {
  const ModelPage({super.key});

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage> {
  late final AppState _state = context.read<AppState>();
  late LlmConfig _config = _state.settings.llm;
  late final _url = TextEditingController(text: _config.baseUrl);
  late final _model = TextEditingController(text: _config.model);
  late final _apiKey = TextEditingController(text: _config.apiKey ?? '');
  List<String> _models = [];
  String? _status;
  bool _ok = false;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  LlmConfig _current() => _config.copyWith(
    baseUrl: _url.text.trim(),
    model: _model.text.trim(),
    apiKey: _apiKey.text.trim(),
  );

  Future<void> _save() async {
    _config = _current();
    await _state.updateSettings((s) => s.llm = _config);
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final client = _state.llmClient(_current());
    try {
      final models = await client.listModels();
      final name = _model.text.trim();
      final found =
          models.contains(name) ||
          models.contains('$name:latest') ||
          models.any((m) => m.endsWith('/$name'));
      final info = await client.modelInfo();
      final parts = <String>[
        'Server odpovídá, dostupných modelů: ${models.length}.',
        if (!found && models.isNotEmpty)
          'Model „$name“ na serveru není – stáhněte ho: ollama pull $name',
        if (info != null) ...[
          info.supportsTools
              ? 'Model podporuje nástroje (tools) ✓'
              : 'Model NEPODPORUJE nástroje – agent nebude fungovat spolehlivě!',
          if (info.supportsThinking) 'Podporuje přemýšlení (thinking).',
          if (info.contextLength != null)
            'Maximální kontext modelu: ${info.contextLength} tokenů.',
        ],
      ];
      setState(() {
        _models = models;
        _ok = (found || models.isEmpty) && (info?.supportsTools ?? true);
        _status = parts.join('\n');
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _preset(String url, LlmProvider provider) {
    setState(() {
      _url.text = url;
      _config = _config.copyWith(provider: provider);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mobile = Platform.isAndroid || Platform.isIOS;
    return SettingsSection(
      title: 'Lokální model',
      description:
          'Agent používá jazykový model běžící u vás – žádná data neodcházejí do '
          'cloudu. Doporučeno: Ollama + qwen3.5:9b. Návod k instalaci najdete '
          'v docs/LOKALNI_MODEL.md.',
      children: [
        FieldRow(
          label: 'Server modelu',
          child: SegmentedButton<LlmProvider>(
            segments: const [
              ButtonSegment(value: LlmProvider.ollama, label: Text('Ollama')),
              ButtonSegment(
                value: LlmProvider.openAiCompatible,
                label: Text('OpenAI-kompatibilní'),
              ),
            ],
            selected: {_config.provider},
            onSelectionChanged: (s) {
              setState(() => _config = _config.copyWith(provider: s.first));
              _save();
            },
          ),
        ),
        FieldRow(
          label: 'Adresa serveru',
          help: mobile
              ? 'Na telefonu zadejte IP adresu počítače, na kterém běží Ollama '
                    '(OLLAMA_HOST=0.0.0.0), např. http://192.168.1.20:11434.'
              : 'Ollama: http://127.0.0.1:11434 · LM Studio: http://127.0.0.1:1234/v1 · '
                    'llama.cpp: http://127.0.0.1:8080/v1',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
                onSubmitted: (_) => _save(),
                onTapOutside: (_) => _save(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('Ollama', 'http://127.0.0.1:11434', LlmProvider.ollama),
                  _chip(
                    'LM Studio',
                    'http://127.0.0.1:1234/v1',
                    LlmProvider.openAiCompatible,
                  ),
                  _chip(
                    'llama.cpp',
                    'http://127.0.0.1:8080/v1',
                    LlmProvider.openAiCompatible,
                  ),
                  _chip(
                    'Android emulátor (Ollama v PC)',
                    'http://10.0.2.2:11434',
                    LlmProvider.ollama,
                  ),
                ],
              ),
            ],
          ),
        ),
        FieldRow(
          label: 'Model',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('model-name'),
                  controller: _model,
                  onSubmitted: (_) => _save(),
                  onTapOutside: (_) => _save(),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Vybrat model',
                onSelected: (m) {
                  setState(() => _model.text = m);
                  _save();
                },
                itemBuilder: (_) => [
                  if (_models.isNotEmpty) ...[
                    const PopupMenuItem(
                      enabled: false,
                      child: Text('Na serveru'),
                    ),
                    for (final m in _models)
                      PopupMenuItem(value: m, child: Text(m)),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Doporučené'),
                  ),
                  for (final (name, note) in _recommended)
                    PopupMenuItem(
                      value: name,
                      child: Text(
                        '$name   $note',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.expand_more_rounded),
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _save();
                        await _check();
                      },
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Ověřit'),
              ),
            ],
          ),
        ),
        if (_status != null) ResultLine(text: _status!, ok: _ok),
        const SizedBox(height: 12),
        FieldRow(
          label: 'Kontextové okno: ${_config.contextLength ~/ 1024}k tokenů',
          help:
              'Výstupy příkazů jsou dlouhé – doporučeno 32k. Větší okno '
              'potřebuje více (V)RAM. U OpenAI-kompatibilních serverů se '
              'nastavuje přímo v serveru (LM Studio, llama-server -c).',
          child: Slider(
            min: 8,
            max: 128,
            divisions: 15,
            value: (_config.contextLength / 1024).clamp(8, 128).toDouble(),
            label: '${_config.contextLength ~/ 1024}k',
            onChanged: (v) => setState(
              () => _config = _config.copyWith(
                contextLength: (v.round() ~/ 8) * 8 * 1024,
              ),
            ),
            onChangeEnd: (_) => _save(),
          ),
        ),
        FieldRow(
          label: 'Teplota: ${_config.temperature.toStringAsFixed(1)}',
          help: 'Nízká teplota = přesnější a předvídatelnější volání nástrojů.',
          child: Slider(
            min: 0,
            max: 1,
            divisions: 10,
            value: _config.temperature,
            onChanged: (v) =>
                setState(() => _config = _config.copyWith(temperature: v)),
            onChangeEnd: (_) => _save(),
          ),
        ),
        FieldRow(
          label: 'Přemýšlení (thinking)',
          help:
              'Modely jako Qwen3.5 umí před odpovědí „přemýšlet“ – přesnější, '
              'ale pomalejší. U gpt-oss použijte úroveň nízké/střední/vysoké.',
          child: DropdownButtonFormField<ThinkingMode>(
            initialValue: _config.thinking,
            items: [
              for (final mode in ThinkingMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (v) {
              setState(() => _config = _config.copyWith(thinking: v));
              _save();
            },
          ),
        ),
        if (_config.provider == LlmProvider.openAiCompatible)
          FieldRow(
            label: 'API klíč (volitelné)',
            child: TextField(
              controller: _apiKey,
              obscureText: true,
              onSubmitted: (_) => _save(),
              onTapOutside: (_) => _save(),
            ),
          ),
        Text(
          'Tip: model musí podporovat volání funkcí (tools). V Ollamě to '
          'ověříte příkazem `ollama show <model>` (řádek Capabilities: tools).',
          style: TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.4),
        ),
      ],
    );
  }

  Widget _chip(String label, String url, LlmProvider provider) => ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
    onPressed: () => _preset(url, provider),
  );
}
