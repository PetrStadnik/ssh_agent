import 'package:flutter/material.dart';

import '../../theme.dart';
import 'agent_page.dart';
import 'appearance_page.dart';
import 'model_page.dart';
import 'servers_page.dart';

enum SettingsPage {
  servers('Servery', Icons.dns_outlined),
  model('Model', Icons.memory_rounded),
  agent('Agent a nástroje', Icons.handyman_outlined),
  appearance('Vzhled a data', Icons.palette_outlined);

  const SettingsPage(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Opens the settings as a dialog (desktop/tablet) or a full screen page
/// (phone).
Future<void> showSettingsDialog(
  BuildContext context, {
  SettingsPage initialPage = SettingsPage.servers,
  bool addServer = false,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final view = SettingsView(initialPage: initialPage, addServer: addServer);
  if (wide) {
    return showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
          child: view,
        ),
      ),
    );
  }
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => view));
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.initialPage = SettingsPage.servers,
    this.addServer = false,
  });

  final SettingsPage initialPage;
  final bool addServer;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsPage _page = widget.initialPage;

  Widget _content() => switch (_page) {
    SettingsPage.servers => ServersPage(openEditor: widget.addServer),
    SettingsPage.model => const ModelPage(),
    SettingsPage.agent => const AgentPage(),
    SettingsPage.appearance => const AppearancePage(),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final content = Expanded(
          child: Container(color: c.background, child: _content()),
        );
        if (wide) {
          return Material(
            color: c.background,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 220,
                  color: c.sidebar,
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                        child: Text(
                          'Nastavení',
                          style: TextStyle(
                            fontFamily: serifFamily,
                            fontFamilyFallback: serifFonts,
                            fontSize: 22,
                            color: c.text,
                          ),
                        ),
                      ),
                      for (final page in SettingsPage.values)
                        _PageButton(
                          page: page,
                          selected: page == _page,
                          onTap: () => setState(() => _page = page),
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Zavřít'),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, color: c.border),
                content,
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            backgroundColor: c.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('Nastavení'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final page in SettingsPage.values)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                          label: Text(page.label),
                          selected: page == _page,
                          onSelected: (_) => setState(() => _page = page),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          body: Column(children: [content]),
        );
      },
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final SettingsPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                page.icon,
                size: 18,
                color: selected ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  page.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Common scaffold of a settings page: title, description, content.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    required this.children,
    this.trailing,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: TextStyle(
              fontSize: 13.5,
              color: c.textSecondary,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

/// Label + control row used in the forms.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    this.help,
    required this.child,
  });

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                help!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.textTertiary,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Bordered card used inside settings pages.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    // Material (not a decorated Container) so that list tiles inside
    // can paint their ink.
    child: Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
    ),
  );
}

/// Inline result line (success / error) under a test button.
class ResultLine extends StatelessWidget {
  const ResultLine({super.key, required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? context.colors.success : context.colors.danger;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(fontSize: 13, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
