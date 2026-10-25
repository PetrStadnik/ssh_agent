// Renders screenshots of the main screens with real fonts.
//
//   SCREENSHOT_DIR=/tmp/shots flutter test test/screenshots
//
// Skipped when SCREENSHOT_DIR is not set (fonts are taken from the Flutter
// SDK and common Linux font packages).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_agent/app.dart';
import 'package:ssh_agent/state/app_state.dart';
import 'package:ssh_agent/ui/settings/settings_dialog.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../fakes.dart';

final String? outDir = Platform.environment['SCREENSHOT_DIR'];

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final path in files) {
    final file = File(path);
    if (file.existsSync()) {
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await loader.load();
}

Future<void> loadFonts() async {
  final sdk =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  await loadFont('Roboto', [
    '$sdk/Roboto-Regular.ttf',
    '$sdk/Roboto-Medium.ttf',
    '$sdk/Roboto-Bold.ttf',
    '$sdk/Roboto-Italic.ttf',
  ]);
  await loadFont('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
  const serif = [
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf',
  ];
  await loadFont('serif', serif);
  await loadFont('monospace', [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
  ]);
}

Conversation sampleConversation() {
  final turn = AgentTurn(
    status: AgentTurnStatus.done,
    model: 'qwen3.5:9b',
    server: 'web-prod',
    promptTokens: 9120,
    completionTokens: 412,
    steps: [
      AgentStepRecord(
        thinking:
            'Uživatel chce vědět, kdy se změnil /etc/passwd. Použiji stat '
            'a pak historii přihlášení z doby změny.',
        tools: [
          ToolInvocation(
            id: '1',
            name: 'stat',
            arguments: const {'path': '/etc/passwd'},
            server: 'web-prod',
            runAs: 'admin',
            script:
                "stat -- '/etc/passwd' || exit 1\n"
                "printf 'Resolved path: '; readlink -f -- '/etc/passwd' || echo '?'\ntrue",
            status: ToolStatus.done,
            exitCode: 0,
            durationMs: 41,
            stdout:
                '  File: /etc/passwd\n'
                '  Size: 3465      \tBlocks: 8          IO Block: 4096   regular file\n'
                'Device: 254,0\tInode: 425991      Links: 1\n'
                'Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)\n'
                'Access: 2026-10-25 08:02:11.577292996 +0100\n'
                'Modify: 2026-10-24 22:13:05.565238411 +0100\n'
                'Change: 2026-10-24 22:13:05.565238411 +0100\n'
                ' Birth: 2025-03-02 10:41:17.562921253 +0100\n'
                'Resolved path: /etc/passwd',
          ),
        ],
      ),
      AgentStepRecord(
        tools: [
          ToolInvocation(
            id: '2',
            name: 'last',
            arguments: const {'since': '2026-10-24 21:00', 'limit': 20},
            server: 'web-prod',
            runAs: 'admin',
            script:
                "command -v last >/dev/null 2>&1 || { echo 'The last command is not available on this server.' >&2; exit 127; }\n"
                "if last -F -w -i -n 1 >/dev/null 2>&1; then\n"
                "  last -F -w -i -n 20 --since '2026-10-24 21:00'\nelse\n  last -n 20\nfi",
            status: ToolStatus.done,
            exitCode: 0,
            durationMs: 63,
            stdout:
                'jnovak   pts/0        185.12.44.7      Fri Oct 24 22:05:41 2026 - Fri Oct 24 22:31:02 2026  (00:25)\n'
                'admin    pts/1        10.8.0.2         Fri Oct 24 21:12:09 2026 - Fri Oct 24 21:40:55 2026  (00:28)\n'
                '\nwtmp begins Mon Sep  1 00:00:02 2026',
          ),
        ],
      ),
      AgentStepRecord(
        text:
            'Soubor **`/etc/passwd`** byl naposledy změněn **24. 10. 2026 ve '
            '22:13:05** (časové pásmo serveru UTC+1).\n\n'
            'V té době byl přihlášený jen jeden uživatel:\n\n'
            '- **jnovak** z IP `185.12.44.7`, relace 22:05–22:31\n\n'
            'Změna tedy s velkou pravděpodobností proběhla během jeho relace. '
            'Pro potvrzení můžu prohledat `journal` (např. `useradd`, `usermod`, '
            '`passwd`) v tomto časovém okně.',
      ),
    ],
  );
  return Conversation(
    id: 'demo',
    title: 'Kdy se změnil /etc/passwd?',
    profileId: 'p1',
    turns: [
      UserTurn(
        'Kdy se naposledy změnil /etc/passwd a kdo byl v té době přihlášený?',
      ),
      turn,
    ],
  );
}

Future<void> shoot(
  WidgetTester tester,
  String name,
  Size size,
  Widget app, {
  Future<void> Function()? before,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: app));
  await tester.pumpAndSettle();
  if (before != null) {
    await before();
    await tester.pumpAndSettle();
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.5));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('$outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  tester.view.reset();
}

void main() {
  setUpAll(() async {
    if (outDir != null) await loadFonts();
  });

  Future<AppState> state({
    ThemeMode mode = ThemeMode.light,
    bool chat = true,
  }) async {
    final s = await createState(
      profiles: [
        sampleProfile(),
        sampleProfile(id: 'p2', name: 'db-backup')..color = 0xFF3B6EA8,
      ],
      conversations: chat
          ? [
              sampleConversation(),
              Conversation(
                id: 'b',
                title: 'Oprávnění uživatele www-data',
                profileId: 'p1',
              ),
              Conversation(
                id: 'c',
                title: 'Kde jsou logy nginx?',
                profileId: 'p2',
              ),
            ]
          : const [],
    );
    s.settings.themeMode = mode;
    if (chat) s.selectConversation('demo');
    return s;
  }

  testWidgets('screenshots', (tester) async {
    await shoot(
      tester,
      '1_chat_light',
      const Size(1360, 860),
      SshAgentApp(state: await state()),
    );
    await shoot(
      tester,
      '2_chat_dark',
      const Size(1360, 860),
      SshAgentApp(state: await state(mode: ThemeMode.dark)),
    );
    await shoot(
      tester,
      '3_welcome',
      const Size(1360, 860),
      SshAgentApp(state: await state(chat: false)),
    );
    await shoot(
      tester,
      '4_phone',
      const Size(400, 860),
      SshAgentApp(state: await state()),
    );
    final settingsState = await state();
    await shoot(
      tester,
      '5_settings_model',
      const Size(1360, 860),
      SshAgentApp(state: settingsState),
      before: () async {
        showSettingsDialog(
          tester.element(find.byType(Scaffold).first),
          initialPage: SettingsPage.model,
        );
      },
    );
    final editorState = await state();
    await shoot(
      tester,
      '6_server_editor',
      const Size(1360, 900),
      SshAgentApp(state: editorState),
      before: () async {
        showSettingsDialog(
          tester.element(find.byType(Scaffold).first),
          initialPage: SettingsPage.servers,
          addServer: true,
        );
      },
    );
  }, skip: outDir == null);
}
