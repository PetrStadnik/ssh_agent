import 'package:flutter/material.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../theme.dart';
import 'widgets.dart';

/// Shows one tool call: which function the agent called, with which
/// arguments, the exact command, where it ran and what it returned.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.call,
    required this.initiallyExpanded,
  });

  final ToolInvocation call;
  final bool initiallyExpanded;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  /// A running command is always shown open so that its output is visible.
  late bool _expanded =
      widget.initiallyExpanded || widget.call.status == ToolStatus.running;
  bool _showAll = false;
  bool _showFullCommand = false;

  static const _collapsedLines = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    final running = call.status == ToolStatus.running;
    final failed = call.status == ToolStatus.failed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            hoverColor: c.hover,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 17, color: c.accent),
                  const SizedBox(width: 8),
                  Text(
                    call.name,
                    style: monoStyle(
                      context,
                      size: 13.5,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _argumentSummary(call.arguments),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        context,
                        size: 12.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(call: call),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _metaLine(context),
                  if (call.script != null) ...[
                    const SizedBox(height: 6),
                    _commandBlock(context),
                  ],
                  if (call.note != null) ...[
                    const SizedBox(height: 6),
                    _message(
                      context,
                      Icons.info_outline_rounded,
                      call.note!,
                      c.warning,
                    ),
                  ],
                  if (call.error != null) ...[
                    const SizedBox(height: 6),
                    _message(
                      context,
                      Icons.error_outline_rounded,
                      call.error!,
                      c.danger,
                    ),
                  ],
                  if (!running && call.error == null) ...[
                    const SizedBox(height: 6),
                    _outputBlock(context),
                  ],
                  if (running) ...[
                    const SizedBox(height: 6),
                    _liveBlock(context),
                  ],
                ],
              ),
            ),
          ] else if (failed && call.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                call.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.danger),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaLine(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    final style = TextStyle(fontSize: 12, color: c.textTertiary);
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _meta(Icons.dns_outlined, call.server, style),
        if (call.runAs != null) _meta(Icons.person_outline, call.runAs!, style),
        _meta(Icons.folder_outlined, call.cwd ?? '~', style),
        if (call.durationMs > 0)
          _meta(Icons.timer_outlined, formatDuration(call.durationMs), style),
      ],
    );
  }

  Widget _meta(IconData icon, String text, TextStyle style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: style.color),
      const SizedBox(width: 4),
      Text(text, style: style),
    ],
  );

  Widget _commandBlock(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    final text = _showFullCommand && call.fullCommand != null
        ? call.fullCommand!
        : call.script!;
    return Container(
      decoration: BoxDecoration(
        color: c.code,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('\$ ', style: monoStyle(context, color: c.accent)),
          Expanded(
            child: SelectableText(
              text,
              style: monoStyle(context, color: c.textSecondary),
            ),
          ),
          Column(
            children: [
              SoftIconButton(
                icon: Icons.copy_rounded,
                size: 15,
                tooltip: 'Kopírovat příkaz',
                onPressed: () => copyToClipboard(context, text),
              ),
              if (call.fullCommand != null)
                SoftIconButton(
                  icon: _showFullCommand
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 15,
                  tooltip: _showFullCommand
                      ? 'Zobrazit skript nástroje'
                      : 'Zobrazit přesný příkaz odeslaný přes SSH',
                  onPressed: () =>
                      setState(() => _showFullCommand = !_showFullCommand),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _outputBlock(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    final stdout = call.stdout.trimRight();
    final stderr = call.stderr.trimRight();
    if (stdout.isEmpty && stderr.isEmpty) {
      return Text(
        '(žádný výstup)',
        style: TextStyle(fontSize: 12.5, color: c.textTertiary),
      );
    }
    final lines = stdout.isEmpty ? <String>[] : stdout.split('\n');
    final cut = !_showAll && lines.length > _collapsedLines;
    final shown = cut ? lines.take(_collapsedLines).join('\n') : stdout;

    return Container(
      decoration: BoxDecoration(
        color: c.code,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
            child: Row(
              children: [
                Text(
                  'Výstup',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: c.textTertiary,
                  ),
                ),
                if (call.truncated) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(oříznuto)',
                    style: TextStyle(fontSize: 11.5, color: c.warning),
                  ),
                ],
                const Spacer(),
                SoftIconButton(
                  icon: Icons.copy_rounded,
                  size: 15,
                  tooltip: 'Kopírovat výstup',
                  onPressed: () => copyToClipboard(
                    context,
                    [stdout, stderr].where((s) => s.isNotEmpty).join('\n'),
                  ),
                ),
              ],
            ),
          ),
          if (stdout.isNotEmpty) _scrollable(context, shown),
          if (cut || _showAll && lines.length > _collapsedLines)
            InkWell(
              onTap: () => setState(() => _showAll = !_showAll),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: Text(
                  _showAll
                      ? 'Zobrazit méně'
                      : 'Zobrazit vše (${lines.length} '
                            '${plural(lines.length, 'řádek', 'řádky', 'řádků')})',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
              ),
            ),
          if (stderr.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'stderr',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.warning,
                    ),
                  ),
                  SelectableText(
                    stderr.length > 4000
                        ? '${stderr.substring(0, 4000)}\n…'
                        : stderr,
                    style: monoStyle(context, size: 12, color: c.warning),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _liveLines = 14;

  /// Output received so far while the command still runs.
  Widget _liveBlock(BuildContext context) {
    final c = context.colors;
    final call = widget.call;
    String tail(String text, int lines) {
      final all = text.trimRight().split('\n');
      return all.length <= lines
          ? all.join('\n')
          : all.sublist(all.length - lines).join('\n');
    }

    final out = call.liveStdout.trimRight();
    final err = call.liveStderr.trimRight();
    return Container(
      key: const Key('live-output'),
      decoration: BoxDecoration(
        color: c.code,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: SecondsTicker(
              builder: (context) => Row(
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        'Běží na serveru',
                        if (call.startedAt != null)
                          elapsedSince(call.startedAt!),
                        if (call.liveLines > 0)
                          '${formatCount(call.liveLines)} '
                              '${plural(call.liveLines, 'řádek', 'řádky', 'řádků')}',
                        if (call.liveBytes > 0) formatBytes(call.liveBytes),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (out.isEmpty && err.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: SecondsTicker(
                builder: (context) {
                  final started = call.startedAt;
                  final quiet =
                      started != null &&
                      DateTime.now().difference(started).inSeconds >= 5;
                  return Text(
                    quiet
                        ? 'Čekám na výstup… Příkaz zatím nic nevypsal – '
                              'některé programy posílají výstup po větších '
                              'blocích nebo až na konci.'
                        : 'Čekám na výstup…',
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  );
                },
              ),
            ),
          if (out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  tail(out, _liveLines),
                  style: monoStyle(context, size: 12),
                ),
              ),
            ),
          if (err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                tail(err, 5),
                style: monoStyle(context, size: 12, color: c.warning),
              ),
            ),
        ],
      ),
    );
  }

  /// Output text: scrolls horizontally (long lines are common), and
  /// vertically inside a fixed height once fully expanded.
  Widget _scrollable(BuildContext context, String text) {
    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(text, style: monoStyle(context, size: 12)),
      ),
    );
    if (_showAll) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(child: content),
      );
    }
    return content;
  }

  Widget _message(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: SelectableText(
          text,
          style: TextStyle(fontSize: 12.5, color: color, height: 1.4),
        ),
      ),
    ],
  );

  static String _argumentSummary(Map<String, Object?> args) => args.entries
      .where((e) => e.value != null)
      .map((e) => '${e.key}=${e.value is String ? e.value : '${e.value}'}')
      .join('  ');
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.call});

  final ToolInvocation call;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (call.status == ToolStatus.running) {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final ok = call.status == ToolStatus.done;
    final label = call.error != null
        ? 'chyba'
        : call.timedOut
        ? 'timeout'
        : 'exit ${call.exitCode ?? '?'}';
    final color = ok
        ? c.success
        : (call.exitCode == 1 && call.error == null ? c.warning : c.danger);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_rounded : Icons.close_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
