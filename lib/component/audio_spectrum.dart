import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The timer exists only while visible, playing and motion is allowed. Samples
/// repaint a small isolated canvas without rebuilding the player or decoding.
class AudioSpectrum extends StatefulWidget {
  const AudioSpectrum(
      {super.key,
      required this.readSpectrum,
      required this.playing,
      this.animate = true,
      this.ring = false,
      this.gentle = true,
      this.trackKey});
  final List<double> Function() readSpectrum;
  final bool playing, animate, ring, gentle;
  final Object? trackKey;
  @override
  State<AudioSpectrum> createState() => _AudioSpectrumState();
}

class _AudioSpectrumState extends State<AudioSpectrum> {
  Timer? _timer;
  final _levels = ValueNotifier<List<double>>(const []);
  bool _visible = true;
  void _sample() {
    try {
      final values = widget.readSpectrum(), old = _levels.value;
      _levels.value = List.generate(values.length, (index) {
        final next =
            values[index].isFinite ? values[index].clamp(0.0, 1.0) : 0.0;
        final previous = index < old.length ? old[index] : 0.0;
        return previous + (next - previous) * (next > previous ? .7 : .3);
      });
    } catch (_) {
      _levels.value = const [];
    }
  }

  void _sync() {
    final run = widget.playing && widget.animate && _visible;
    if (!run) {
      _timer?.cancel();
      _timer = null;
      _levels.value = const [];
    } else if (_timer == null) {
      _timer = Timer.periodic(
          Duration(milliseconds: widget.gentle ? 66 : 33), (_) => _sample());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(AudioSpectrum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gentle != widget.gentle) {
      _timer?.cancel();
      _timer = null;
    }
    if (oldWidget.trackKey != widget.trackKey) _levels.value = const [];
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: ExcludeSemantics(
          child: RepaintBoundary(
              child: CustomPaint(
                  painter: _SpectrumPainter(
                      _levels, Theme.of(context).colorScheme.primary,
                      ring: widget.ring),
                  child: const SizedBox.expand()))));
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.levels, this.color, {required this.ring})
      : super(repaint: levels);
  final ValueNotifier<List<double>> levels;
  final Color color;
  final bool ring;
  @override
  void paint(Canvas canvas, Size size) {
    final values = levels.value;
    if (values.isEmpty) return;
    final count = values.length;
    final paint = Paint()
      ..color = color.withValues(alpha: .8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (ring) {
      final center = size.center(Offset.zero),
          radius = math.max(0.0, size.shortestSide / 2 - 22);
      if (radius < 8) return;
      for (var i = 0; i < count; i++) {
        final angle = i / count * 2 * math.pi - math.pi / 2;
        final amount = values[i];
        if (amount < .001) continue;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(center + direction * radius,
            center + direction * (radius + 2 + amount * 15), paint);
      }
    } else {
      final step = size.width / count;
      paint.strokeWidth = (step * .55).clamp(1.0, 7.0);
      for (var i = 0; i < count; i++) {
        final amount = values[i];
        if (amount < .001) continue;
        final x = (i + .5) * step,
            height = 2 + amount * math.max(0, size.height - 4);
        canvas.drawLine(
            Offset(x, size.height), Offset(x, size.height - height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      color != oldDelegate.color ||
      ring != oldDelegate.ring ||
      levels != oldDelegate.levels;
}
