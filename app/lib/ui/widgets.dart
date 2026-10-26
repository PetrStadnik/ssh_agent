import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The app mark: a terracotta "spark" (radiating strokes).
class SparkIcon extends StatelessWidget {
  const SparkIcon({
    super.key,
    this.size = 28,
    this.color,
    this.animate = false,
  });

  final double size;
  final Color? color;

  /// Slowly rotate while the agent is working.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _SparkPainter(color ?? context.colors.accent),
    );
    if (!animate) return painter;
    return _Spinning(child: painter);
  }
}

class _Spinning extends StatefulWidget {
  const _Spinning({required this.child});

  final Widget child;

  @override
  State<_Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<_Spinning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _controller, child: widget.child);
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.11;
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final angle = i * 2 * math.pi / rays;
      final long = i.isEven;
      final inner = radius * 0.18;
      final outer = radius * (long ? 0.95 : 0.7);
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => oldDelegate.color != color;
}

/// Small icon button with the subtle hover background used everywhere.
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      hoverColor: context.colors.hover,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          icon,
          size: size,
          color: color ?? context.colors.textSecondary,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Copies [text] and shows a short confirmation.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String message = 'Zkopírováno do schránky',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 280,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Coloured dot used for servers.
class ServerDot extends StatelessWidget {
  const ServerDot({super.key, required this.color, this.connected = false});

  final Color color;
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: connected
          ? Border.all(color: context.colors.success, width: 2)
          : null,
    ),
  );
}

/// Pill shaped chip in the composer (server, model...).
class ComposerChip extends StatelessWidget {
  const ComposerChip({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.leading,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: c.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading ?? Icon(icon, size: 15, color: c.textSecondary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: c.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Section heading used in the sidebar and settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 6, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Czech noun form for a count: 1 řádek, 2–4 řádky, 0 or 5+ řádků.
String plural(int count, String one, String few, String many) => count == 1
    ? one
    : count >= 2 && count <= 4
    ? few
    : many;

String formatDuration(int milliseconds) {
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  if (seconds < 60) {
    return '${seconds.toStringAsFixed(1).replaceAll('.', ',')} s';
  }
  return '${(seconds / 60).floor()} min ${(seconds % 60).round()} s';
}

/// Rebuilds [builder] every second (for live elapsed times).
class SecondsTicker extends StatefulWidget {
  const SecondsTicker({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<SecondsTicker> createState() => _SecondsTickerState();
}

class _SecondsTickerState extends State<SecondsTicker> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// 7412 -> "7 412".
String formatCount(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('\u00A0');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Whole seconds since [since], e.g. "12 s" or "2 min 5 s".
String elapsedSince(DateTime since) {
  final seconds = DateTime.now().difference(since).inSeconds.clamp(0, 1 << 30);
  if (seconds < 60) return '$seconds s';
  return '${seconds ~/ 60} min ${seconds % 60} s';
}

/// 1536 -> "1,5 kB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} kB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
