import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'composer.dart';
import 'messages.dart';
import 'settings/settings_dialog.dart';
import 'widgets.dart';

const double _contentWidth = 780;

/// The main area: header, messages and the composer.
class ChatView extends StatefulWidget {
  const ChatView({super.key, this.onOpenSidebar});

  /// Shows the sidebar / drawer (null when it is already visible).
  final VoidCallback? onOpenSidebar;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conversation = state.activeConversation;
    final empty = conversation == null || conversation.isEmpty;

    return Column(
      children: [
        _Header(
          title: empty ? '' : conversation.title,
          onOpenSidebar: widget.onOpenSidebar,
        ),
        Expanded(
          child: empty
              ? _Welcome(input: _input)
              : _MessageList(
                  key: ValueKey(conversation.id),
                  conversation: conversation,
                ),
        ),
        if (!empty)
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Column(
                    children: [
                      Composer(controller: _input),
                      const _Disclaimer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onOpenSidebar});

  final String title;
  final VoidCallback? onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (onOpenSidebar != null)
                SoftIconButton(
                  key: const Key('open-sidebar'),
                  icon: Icons.menu_rounded,
                  tooltip: 'Panel',
                  onPressed: onOpenSidebar,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.text,
                  ),
                ),
              ),
              SoftIconButton(
                icon: Icons.edit_square,
                tooltip: 'Nový chat',
                onPressed: () => context.read<AppState>().newConversation(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      'Agent na serveru jen čte – nic nemění. Důležité závěry si ověřte.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11.5, color: context.colors.textTertiary),
    ),
  );
}

class _MessageList extends StatelessWidget {
  const _MessageList({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    final turns = conversation.turns.reversed.toList();
    // Reversed list: the newest message sits at the bottom and streaming
    // text grows upwards without manual scrolling.
    return Scrollbar(
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        itemCount: turns.length,
        itemBuilder: (context, index) {
          final turn = turns[index];
          final child = switch (turn) {
            UserTurn() => UserBubble(text: turn.text),
            AgentTurn() => AgentTurnView(
              turn: turn,
              expandToolOutput: settings.expandToolOutput,
              serif: settings.serifAnswers,
            ),
          };
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

const _suggestions = [
  'Kdy se naposledy změnil soubor /etc/passwd?',
  'Kdo se přihlásil přes SSH za posledních 7 dní?',
  'Jaká oprávnění má uživatel www-data?',
  'Kde přesně ukládá nginx logy a konfiguraci?',
  'Které služby naslouchají na síti a pod jakým uživatelem?',
  'Byly tu neúspěšné pokusy o přihlášení?',
];

/// New chat screen: greeting, centered composer and suggestions.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.input});

  final TextEditingController input;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Dobrou noc';
    if (hour < 10) return 'Dobré ráno';
    if (hour < 12) return 'Dobré dopoledne';
    if (hour < 18) return 'Dobré odpoledne';
    return 'Dobrý večer';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final profile = state.profileFor(null);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SparkIcon(size: 34),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            _greeting(),
                            style: TextStyle(
                              fontFamily: serifFamily,
                              fontFamilyFallback: serifFonts,
                              fontSize: 38,
                              fontWeight: FontWeight.w400,
                              color: c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile == null
                          ? 'Přidejte SSH server a ptejte se na cokoli o něm.'
                          : 'Na co se chcete zeptat serveru ${profile.name}?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: c.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    if (profile == null)
                      _AddServerCard()
                    else ...[
                      Composer(controller: input),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _suggestions)
                            ActionChip(
                              label: Text(s),
                              labelStyle: TextStyle(
                                fontSize: 13,
                                color: c.textSecondary,
                              ),
                              backgroundColor: c.background,
                              side: BorderSide(color: c.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onPressed: () {
                                input.text = s;
                                input.selection = TextSelection.collapsed(
                                  offset: s.length,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddServerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Icon(Icons.dns_outlined, size: 32, color: c.accent),
          const SizedBox(height: 10),
          Text(
            'Zatím nemáte žádný server',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Přidejte SSH připojení (adresa, uživatel, klíč nebo heslo). '
            'Agent bude na serveru spouštět pouze čtecí příkazy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('add-first-server'),
            onPressed: () => showSettingsDialog(
              context,
              initialPage: SettingsPage.servers,
              addServer: true,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Přidat server'),
          ),
        ],
      ),
    );
  }
}
