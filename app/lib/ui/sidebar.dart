import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'settings/settings_dialog.dart';
import 'widgets.dart';

/// Left panel: new chat, servers for quick switching, recent chats,
/// settings. On narrow screens it is shown as a drawer.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, this.onClose, this.onNavigate});

  /// Collapses the sidebar (desktop) - null when not collapsible.
  final VoidCallback? onClose;

  /// Called after picking a chat (closes the drawer on mobile).
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final current = state.profileFor(state.activeConversation);

    return Container(
      color: c.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
              child: Row(
                children: [
                  const SparkIcon(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SSH Agent',
                      style: TextStyle(
                        fontFamily: serifFamily,
                        fontFamilyFallback: serifFonts,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    SoftIconButton(
                      icon: Icons.view_sidebar_outlined,
                      tooltip: 'Skrýt panel',
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _NavItem(
                key: const Key('new-chat'),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                label: 'Nový chat',
                bold: true,
                onTap: () {
                  state.newConversation();
                  onNavigate?.call();
                },
              ),
            ),
            SectionLabel(
              'Servery',
              trailing: SoftIconButton(
                icon: Icons.add_rounded,
                size: 16,
                tooltip: 'Přidat server',
                onPressed: () => showSettingsDialog(
                  context,
                  initialPage: SettingsPage.servers,
                  addServer: true,
                ),
              ),
            ),
            if (state.profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  'Zatím žádný server. Přidejte SSH připojení tlačítkem +.',
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
              ),
            for (final profile in state.profiles)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _NavItem(
                  leading: ServerDot(
                    color: Color(profile.color),
                    connected: state.isConnected(profile.id),
                  ),
                  label: profile.name,
                  subtitle: profile.address,
                  selected: current?.id == profile.id,
                  onTap: state.isRunning(state.activeConversationId)
                      ? null
                      : () => state.selectProfile(profile.id),
                ),
              ),
            const SectionLabel('Nedávné'),
            Expanded(
              child: state.conversations.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Žádné konverzace.',
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: state.conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = state.conversations[index];
                        return _ConversationItem(
                          conversation: conversation,
                          selected:
                              conversation.id == state.activeConversationId,
                          running: state.isRunning(conversation.id),
                          server: state
                              .profileById(conversation.profileId)
                              ?.name,
                          onTap: () {
                            state.selectConversation(conversation.id);
                            onNavigate?.call();
                          },
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.all(8),
              child: _NavItem(
                key: const Key('open-settings'),
                leading: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: c.textSecondary,
                ),
                label: 'Nastavení',
                subtitle: state.settings.llm.model,
                onTap: () => showSettingsDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.leading,
    required this.label,
    this.subtitle,
    this.onTap,
    this.selected = false,
    this.bold = false,
  });

  final Widget leading;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: c.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              SizedBox(width: 24, child: Center(child: leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                        color: c.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: c.textTertiary),
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
}

class _ConversationItem extends StatefulWidget {
  const _ConversationItem({
    required this.conversation,
    required this.selected,
    required this.running,
    required this.server,
    required this.onTap,
  });

  final Conversation conversation;
  final bool selected;
  final bool running;
  final String? server;
  final VoidCallback onTap;

  @override
  State<_ConversationItem> createState() => _ConversationItemState();
}

class _ConversationItemState extends State<_ConversationItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.read<AppState>();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.selected ? c.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: c.hover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: c.text),
                      ),
                      if (widget.server != null)
                        Text(
                          widget.server!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 11, color: c.textTertiary),
                        ),
                    ],
                  ),
                ),
                if (widget.running)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                  )
                else if (_hover || widget.selected)
                  PopupMenuButton<String>(
                    tooltip: 'Možnosti',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: c.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) async {
                      if (value == 'rename') {
                        final title = await showRenameDialog(
                          context,
                          widget.conversation.title,
                        );
                        if (title != null) {
                          await state.renameConversation(
                            widget.conversation.id,
                            title,
                          );
                        }
                      } else if (value == 'delete') {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Smazat konverzaci?',
                          message:
                              '„${widget.conversation.title}“ bude trvale odstraněna.',
                          confirm: 'Smazat',
                          destructive: true,
                        );
                        if (ok) {
                          await state.deleteConversation(
                            widget.conversation.id,
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Přejmenovat'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Smazat')),
                    ],
                  )
                else
                  const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
