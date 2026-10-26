import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_agent/app.dart';
import 'package:ssh_agent/ui/settings/settings_dialog.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import 'fakes.dart';

void main() {
  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('without servers the app asks to add one', (tester) async {
    await setSize(tester, const Size(1280, 800));
    final state = await createState();
    await tester.pumpWidget(SshAgentApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Zatím nemáte žádný server'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-first-server')));
    await tester.pumpAndSettle();
    expect(find.text('Nový server'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-name')), 'test');
    await tester.enterText(find.byKey(const Key('profile-host')), '10.0.0.5');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(state.profiles.single.host, '10.0.0.5');
    expect(state.profiles.single.name, 'test');
  });

  testWidgets('a question runs the agent and shows the tool call and answer', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 900));
    final executors = <FakeExecutor>[];
    final state = await createState(
      profiles: [sampleProfile()],
      executors: executors,
      responses: [
        const LlmResponse(
          content: '',
          toolCalls: [
            ToolCall(
              id: 'c1',
              name: 'stat',
              arguments: {'path': '/etc/passwd'},
            ),
          ],
        ),
        const LlmResponse(
          content:
              'Soubor `/etc/passwd` byl naposledy změněn **24. 10. 2026 ve 22:13**.',
        ),
      ],
    );
    await tester.pumpWidget(SshAgentApp(state: state));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('composer-input')),
      'Kdy se změnil /etc/passwd?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // The user's message, the called function with its command and output,
    // and the final answer are all visible.
    expect(find.text('Kdy se změnil /etc/passwd?'), findsWidgets);
    expect(find.text('stat'), findsOneWidget);
    expect(find.textContaining("stat -- '/etc/passwd'"), findsOneWidget);
    expect(find.textContaining('Modify: 2026-10-24'), findsOneWidget);
    expect(find.textContaining('exit 0'), findsOneWidget);
    expect(find.textContaining('byl naposledy změněn'), findsOneWidget);
    expect(executors.single.commands.single, contains('stat --'));

    final conversation = state.conversations.single;
    expect(conversation.title, 'Kdy se změnil /etc/passwd?');
  });

  testWidgets('progress and server output are shown while a tool runs', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 900));
    final hold = Completer<void>();
    final llms = <ScriptedLlm>[];
    final state = await createState(
      profiles: [sampleProfile()],
      hold: hold,
      llms: llms,
      responses: [
        const LlmResponse(
          content: '',
          toolCalls: [
            ToolCall(
              id: 'c1',
              name: 'stat',
              arguments: {'path': '/etc/passwd'},
            ),
          ],
        ),
        const LlmResponse(content: 'Hotovo, soubor existuje.'),
      ],
    );
    // The model is loaded in the background as soon as the app starts.
    expect(llms.first.warmUps, 1);

    await tester.pumpWidget(SshAgentApp(state: state));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer-input')),
      'Existuje /etc/passwd?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-button')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The command is still running: the connection, the model step, the
    // current activity and the output received so far are visible.
    expect(find.textContaining('Připojeno k serveru web-prod'), findsOneWidget);
    expect(find.textContaining('Krok 1'), findsOneWidget);
    final status = tester.widget<Text>(find.byKey(const Key('live-status')));
    expect(status.data, contains('Na serveru běží stat'));
    expect(find.byKey(const Key('live-output')), findsOneWidget);
    expect(find.textContaining('Běží na serveru'), findsOneWidget);
    expect(find.textContaining('File: /etc/passwd'), findsOneWidget);
    expect(find.textContaining('Modify: 2026-10-24'), findsNothing);

    hold.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('live-status')), findsNothing);
    expect(find.byKey(const Key('live-output')), findsNothing);
    expect(find.textContaining('Modify: 2026-10-24'), findsOneWidget);
    expect(find.textContaining('Hotovo, soubor existuje.'), findsOneWidget);
  });

  testWidgets('phone layout uses a drawer with servers and chats', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final state = await createState(
      profiles: [
        sampleProfile(),
        sampleProfile(id: 'p2', name: 'db-1'),
      ],
    );
    await tester.pumpWidget(SshAgentApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Servery'), findsNothing);
    await tester.tap(find.byKey(const Key('open-sidebar')));
    await tester.pumpAndSettle();
    expect(find.text('Servery'), findsOneWidget);
    expect(find.text('db-1'), findsOneWidget);

    await tester.tap(find.text('db-1'));
    await tester.pumpAndSettle();
    expect(state.defaultProfileId, 'p2');
  });

  testWidgets('settings pages open', (tester) async {
    await setSize(tester, const Size(1280, 900));
    final state = await createState(profiles: [sampleProfile()]);
    await tester.pumpWidget(SshAgentApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Servery (SSH připojení)'), findsOneWidget);
    expect(find.text('web-prod'), findsWidgets);

    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    expect(find.text('Lokální model'), findsOneWidget);

    await tester.tap(find.text('Agent a nástroje'));
    await tester.pumpAndSettle();
    expect(find.text('Potvrzovat každý příkaz'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Dostupné funkce'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsSection),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('Dostupné funkce'), findsOneWidget);

    await tester.tap(find.text('Vzhled a data'));
    await tester.pumpAndSettle();
    expect(find.text('Motiv'), findsOneWidget);
  });
}
