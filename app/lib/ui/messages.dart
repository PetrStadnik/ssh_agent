import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

import '../theme.dart';
import 'tool_card.dart';
import 'widgets.dart';

/// The user's message: a rounded beige bubble on the right.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width < 600 ? 320 : 560,
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 6, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.userBubble,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectableText(
            text,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// The agent's answer: reasoning, tool calls and text in the order they
/// happened, plus status and a small action row.
class AgentTurnView extends StatelessWidget {
  const AgentTurnView({
    super.key,
    required this.turn,
    required this.expandToolOutput,
    required this.serif,
  });

  final AgentTurn turn;
  final bool expandToolOutput;
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = <Widget>[];
    if (turn.connectMs != null) {
      children.add(
        _ProgressRow(
          icon: Icons.link_rounded,
          text:
              'Připojeno k serveru ${turn.server ?? ''} za '
              '${formatDuration(turn.connectMs!)}',
        ),
      );
    }
    for (var i = 0; i < turn.steps.length; i++) {
      final step = turn.steps[i];
      final isLast = i == turn.steps.length - 1;
      if (step.startedAt != null || step.modelMs != null) {
        children.add(
          _StepRow(
            step: step,
            number: i + 1,
            model: turn.model,
            running: turn.isRunning && isLast && step.modelMs == null,
          ),
        );
      }
      if (step.thinking.trim().isNotEmpty) {
        children.add(
          ThinkingBlock(
            text: step.thinking,
            active:
                turn.isRunning &&
                isLast &&
                step.text.isEmpty &&
                step.tools.isEmpty,
          ),
        );
      }
      if (step.text.trim().isNotEmpty) {
        children.add(AnswerMarkdown(text: step.text, serif: serif));
      }
      for (final call in step.tools) {
        children.add(
          ToolCallCard(
            key: ValueKey(call.id),
            call: call,
            initiallyExpanded: expandToolOutput,
          ),
        );
      }
    }
    for (final notice in turn.notices) {
      children.add(_Notice(text: notice, color: c.warning));
    }
    if (turn.status == AgentTurnStatus.error && turn.error != null) {
      children.add(_Notice(text: turn.error!, color: c.danger, error: true));
    }
    if (turn.status == AgentTurnStatus.cancelled) {
      children.add(
        _Notice(text: 'Zastaveno uživatelem.', color: c.textTertiary),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (turn.isRunning) LiveStatus(turn: turn),
          if (!turn.isRunning) _ActionRow(turn: turn),
        ],
      ),
    );
  }
}

/// What the agent is doing right now, with live elapsed time - so that a
/// slow model or a long command is never a silent "working...".
class LiveStatus extends StatelessWidget {
  const LiveStatus({super.key, required this.turn});

  final AgentTurn turn;

  @override
  Widget build(BuildContext context) => SecondsTicker(
    builder: (context) {
      final c = context.colors;
      final step = turn.steps.isEmpty ? null : turn.steps.last;
      final running = turn.toolCalls
          .where((t) => t.status == ToolStatus.running)
          .lastOrNull;
      final phaseTime = elapsedSince(turn.phaseSince);
      final waited = DateTime.now().difference(turn.phaseSince).inSeconds;
      final text = switch (turn.phase) {
        AgentPhase.connecting =>
          'Připojuji se k serveru ${turn.phaseDetail ?? ''}…',
        AgentPhase.waitingForModel =>
          'Model ${turn.model ?? ''} zpracovává dotaz'
              '${step == null ? '' : ' (krok ${turn.steps.length})'}…',
        AgentPhase.thinking => 'Model přemýšlí…',
        AgentPhase.writing => 'Model píše odpověď…',
        AgentPhase.runningTool =>
          'Na serveru běží ${running?.name ?? turn.phaseDetail ?? 'příkaz'}'
              '${running == null || running.liveLines == 0 ? '' : ' · ${formatCount(running.liveLines)} ${plural(running.liveLines, 'řádek', 'řádky', 'řádků')} výstupu'}…',
        AgentPhase.processing => 'Předávám výsledek modelu…',
        AgentPhase.idle => 'Dokončuji…',
      };
      String? hint;
      if (turn.phase == AgentPhase.waitingForModel && waited >= 8) {
        final tokens = step?.approxPromptTokens;
        final size = tokens == null ? '' : ' (~${formatCount(tokens)} tokenů)';
        hint = turn.steps.length <= 1
            ? 'První dotaz bývá nejpomalejší: model se načítá do paměti a čte '
                  'zadání včetně definic nástrojů$size. Bez grafické karty to '
                  'může trvat i několik minut.'
            : 'Model čte celou dosavadní konverzaci a výstupy příkazů$size.';
      } else if (turn.phase == AgentPhase.connecting && waited >= 10) {
        hint =
            'Server neodpovídá – zkontrolujte adresu, port a síť. Spojení '
            'vyprší za 15–20 s.';
      }
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SparkIcon(size: 22, animate: true),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '$text  $phaseTime',
                    key: const Key('live-status'),
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'celkem ${elapsedSince(turn.at)}',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ],
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: c.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Small grey line in the flow of the answer (connection, model steps).
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: c.textTertiary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One model call: how long it took and how much it read and wrote.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.model,
    required this.running,
  });

  final AgentStepRecord step;
  final int number;
  final String? model;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final retry = step.retries > 0 ? ' (opakování ${step.retries}×)' : '';
    if (running) {
      final tokens = step.approxPromptTokens;
      return SecondsTicker(
        builder: (context) => _ProgressRow(
          icon: Icons.memory_rounded,
          text:
              'Krok $number$retry · dotaz na model ${model ?? ''}'
              '${tokens == null ? '' : ' · vstup ~${formatCount(tokens)} tokenů'}'
              ' · ${step.startedAt == null ? '' : elapsedSince(step.startedAt!)}',
        ),
      );
    }
    final parts = <String>[
      'Krok $number$retry',
      if (step.modelMs != null) 'model ${formatDuration(step.modelMs!)}',
      if ((step.loadMs ?? 0) > 500)
        'načtení modelu ${formatDuration(step.loadMs!)}',
      if (step.promptTokens != null)
        'vstup ${formatCount(step.promptTokens!)} tok.'
            '${step.promptEvalMs == null ? '' : ' (${formatDuration(step.promptEvalMs!)})'}',
      if (step.completionTokens != null)
        'výstup ${formatCount(step.completionTokens!)} tok.',
      if (step.tools.isNotEmpty)
        'volá: ${step.tools.map((t) => t.name).join(', ')}',
    ];
    return _ProgressRow(icon: Icons.memory_rounded, text: parts.join(' · '));
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.turn});

  final AgentTurn turn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tools = turn.toolCalls.length;
    final details = [
      if (turn.model != null) turn.model!,
      if (tools > 0) '$tools ${plural(tools, 'příkaz', 'příkazy', 'příkazů')}',
      if (turn.completionTokens > 0)
        '${formatCount(turn.promptTokens + turn.completionTokens)} tokenů',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (turn.answer.isNotEmpty)
            SoftIconButton(
              icon: Icons.copy_rounded,
              size: 16,
              tooltip: 'Kopírovat odpověď',
              onPressed: () => copyToClipboard(context, turn.answer),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              details,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, this.error = false});

  final String text;
  final Color color;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            text,
            style: TextStyle(fontSize: 13.5, color: color, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

/// Collapsible reasoning of a thinking model.
class ThinkingBlock extends StatefulWidget {
  const ThinkingBlock({super.key, required this.text, required this.active});

  final String text;
  final bool active;

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _open = false;

  static String _tail(String text, int lines) {
    final all = text.split('\n');
    if (all.length <= lines) return text;
    return '…\n${all.sublist(all.length - lines).join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 17,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.active ? 'Přemýšlí…' : 'Myšlenkový postup',
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_open || widget.active)
            Container(
              margin: const EdgeInsets.only(top: 4, left: 8),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c.border, width: 2)),
              ),
              child: SelectableText(
                // While the model is thinking, show the latest lines live.
                _open ? widget.text.trim() : _tail(widget.text.trim(), 6),
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: c.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Markdown answer styled like Claude (serif body, soft code blocks).
class AnswerMarkdown extends StatelessWidget {
  const AnswerMarkdown({super.key, required this.text, required this.serif});

  final String text;
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final body = TextStyle(
      fontSize: 16,
      height: 1.6,
      color: c.text,
      fontFamily: serif ? serifFamily : null,
      fontFamilyFallback: serif ? serifFonts : null,
    );
    final code = monoStyle(context, size: 13).copyWith(backgroundColor: c.code);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      listBullet: body,
      a: body.copyWith(color: c.accent, decoration: TextDecoration.underline),
      h1: body.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.4),
      h2: body.copyWith(fontSize: 19, fontWeight: FontWeight.w600, height: 1.4),
      h3: body.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      em: body.copyWith(fontStyle: FontStyle.italic),
      code: code,
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: c.code,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      tableHead: body.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
      tableBody: body.copyWith(fontSize: 14.5),
      tableBorder: TableBorder.all(color: c.border, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      blockSpacing: 12,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: sheet,
        softLineBreak: true,
      ),
    );
  }
}
