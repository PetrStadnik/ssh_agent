import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'settings/settings_dialog.dart';
import 'widgets.dart';

/// The rounded input box with server / model selection and send button.
class Composer extends StatefulWidget {
  const Composer({super.key, this.controller, this.autofocus = true});

  final TextEditingController? controller;
  final bool autofocus;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(AppState state) {
    final text = _controller.text.trim();
    if (text.isEmpty || state.isRunning(state.activeConversationId)) return;
    if (state.profileFor(state.activeConversation) == null) {
      showSettingsDialog(context, initialPage: SettingsPage.servers);
      return;
    }
    _controller.clear();
    state.send(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final conversation = state.activeConversation;
    final running = state.isRunning(conversation?.id);
    final profile = state.profileFor(conversation);
    final session = state.sessionFor(conversation);
    final canSend = _controller.text.trim().isNotEmpty && !running;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  _send(state),
              const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                  _send(state),
            },
            child: TextField(
              key: const Key('composer-input'),
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              minLines: 1,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 15.5, height: 1.45, color: c.text),
              decoration: InputDecoration(
                hintText: profile == null
                    ? 'Nejdřív přidejte server v nastavení…'
                    : 'Zeptejte se na cokoli o serveru ${profile.name}…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ServerSelector(enabled: !running),
                      if (session != null &&
                          session.runAs != null &&
                          session.runAs != session.loginUser)
                        ComposerChip(
                          icon: Icons.person_outline,
                          label: 'jako ${session.runAs}',
                          tooltip: 'Agent přepnul uživatele (switch_user)',
                        ),
                      if (session?.cwd != null)
                        ComposerChip(
                          icon: Icons.folder_outlined,
                          label: session!.cwd!,
                          tooltip: 'Pracovní adresář agenta',
                        ),
                      ComposerChip(
                        icon: Icons.memory_rounded,
                        label: state.settings.llm.model,
                        tooltip: 'Lokální model – změna v nastavení',
                        onTap: () => showSettingsDialog(
                          context,
                          initialPage: SettingsPage.model,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              running
                  ? _RoundButton(
                      key: const Key('stop-button'),
                      icon: Icons.stop_rounded,
                      tooltip: 'Zastavit',
                      background: c.text,
                      onPressed: () => state.stop(conversation?.id),
                    )
                  : _RoundButton(
                      key: const Key('send-button'),
                      icon: Icons.arrow_upward_rounded,
                      tooltip: 'Odeslat (Enter)',
                      background: canSend
                          ? c.accent
                          : c.accent.withValues(alpha: 0.35),
                      onPressed: canSend ? () => _send(state) : null,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 20,
            color:
                Theme.of(context).brightness == Brightness.dark &&
                    background == context.colors.text
                ? context.colors.background
                : Colors.white,
          ),
        ),
      ),
    ),
  );
}

/// Dropdown with the saved servers - switching is one click.
class ServerSelector extends StatelessWidget {
  const ServerSelector({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final current = state.profileFor(state.activeConversation);
    final c = context.colors;
    if (current == null) {
      return ComposerChip(
        icon: Icons.add_rounded,
        label: 'Přidat server',
        onTap: () =>
            showSettingsDialog(context, initialPage: SettingsPage.servers),
      );
    }
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Přepnout server',
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      onSelected: (value) {
        if (value == '__add') {
          showSettingsDialog(context, initialPage: SettingsPage.servers);
        } else {
          state.selectProfile(value);
        }
      },
      itemBuilder: (context) => [
        for (final p in state.profiles)
          PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                ServerDot(
                  color: Color(p.color),
                  connected: state.isConnected(p.id),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(fontSize: 14, color: c.text),
                      ),
                      Text(
                        p.address,
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (p.id == current.id)
                  Icon(Icons.check_rounded, size: 18, color: c.accent),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__add',
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 18),
              SizedBox(width: 10),
              Text('Spravovat servery…'),
            ],
          ),
        ),
      ],
      child: IgnorePointer(
        child: ComposerChip(
          icon: Icons.dns_outlined,
          leading: ServerDot(
            color: Color(current.color),
            connected: state.isConnected(current.id),
          ),
          label: current.name,
          tooltip:
              '${current.address}${current.elevation != ElevationMethod.none ? ' · ${current.elevation.name}' : ''}',
          onTap: enabled ? () {} : null,
        ),
      ),
    );
  }
}
