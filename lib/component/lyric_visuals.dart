import 'dart:math' as math;
import 'package:flutter/material.dart';

double lyricWordProgress(double positionMs, int startMs, int durationMs) {
  if (!positionMs.isFinite) return 0;
  if (durationMs <= 0) return positionMs >= startMs ? 1 : 0;
  return ((positionMs - startMs) / durationMs).clamp(0.0, 1.0);
}

class LyricLinePresentation extends StatelessWidget {
  const LyricLinePresentation(
      {super.key,
      required this.active,
      required this.child,
      this.animate = true,
      this.focus = true,
      this.inactiveOpacity = .38,
      this.alignment = Alignment.centerLeft,
      this.gentle = true});
  final bool active, animate, focus, gentle;
  final double inactiveOpacity;
  final Alignment alignment;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final allowed = animate &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: allowed ? 260 : 0);
    return AnimatedOpacity(
        opacity: active ? 1 : inactiveOpacity,
        duration: duration,
        child: AnimatedScale(
            scale: focus && active && allowed ? (gentle ? 1.025 : 1.05) : 1,
            alignment: alignment,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: child));
  }
}

class LyricEdgeFade extends StatelessWidget {
  const LyricEdgeFade({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => !enabled
      ? child
      : ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent
                  ],
                  stops: [
                    0,
                    .08,
                    .87,
                    1
                  ]).createShader(rect),
          child: child);
}

class InterludeDots extends StatefulWidget {
  const InterludeDots(
      {super.key,
      required this.progress,
      required this.playing,
      this.animate = true});
  final double progress;
  final bool playing, animate;
  @override
  State<InterludeDots> createState() => _InterludeDotsState();
}

class _InterludeDotsState extends State<InterludeDots>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  bool _visible = true;
  void _sync() {
    final run = widget.playing && widget.animate && _visible;
    if (run && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!run && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(InterludeDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 80,
      height: 40,
      child: RepaintBoundary(
          child: CustomPaint(
              painter: _InterludePainter(
                  _pulse,
                  widget.progress.isFinite
                      ? widget.progress.clamp(0.0, 1.0)
                      : 0,
                  Theme.of(context).colorScheme.primary))));
}

class _InterludePainter extends CustomPainter {
  _InterludePainter(this.pulse, this.progress, this.color)
      : super(repaint: pulse);
  final Animation<double> pulse;
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final fill = (progress * 3 - i).clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(14.0 + i * 24, size.height / 2),
          5.5 + pulse.value * .6,
          Paint()
            ..color = color.withValues(alpha: .22 + math.min(fill, 1) * .78));
    }
  }

  @override
  bool shouldRepaint(_InterludePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      pulse != oldDelegate.pulse;
}
