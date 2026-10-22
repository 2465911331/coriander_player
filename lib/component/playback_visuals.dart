import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Preserves its angle across pause/resume; decelerates only while on screen.
class VinylArtwork extends StatefulWidget {
  const VinylArtwork(
      {super.key,
      this.cover,
      required this.playing,
      this.animate = true,
      this.secondsPerTurn = 24});
  final ImageProvider? cover;
  final bool playing, animate;
  final double secondsPerTurn;
  @override
  State<VinylArtwork> createState() => _VinylArtworkState();
}

class _VinylArtworkState extends State<VinylArtwork>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _angle = ValueNotifier(0.0);
  double _speed = 0;
  Duration? _last;
  bool _visible = true;

  void _sync() {
    final run = widget.animate && _visible && (widget.playing || _speed > .002);
    if (run && !_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
    if (!run && _ticker.isActive) {
      _ticker.stop();
      _last = null;
    }
    if (!widget.animate || !_visible) _speed = 0;
  }

  void _tick(Duration elapsed) {
    final dt = _last == null
        ? 0.0
        : ((elapsed - _last!).inMicroseconds / 1000000).clamp(0.0, .05);
    _last = elapsed;
    final target = widget.playing ? 2 * math.pi / widget.secondsPerTurn : 0.0;
    _speed += (target - _speed) * (1 - math.exp(-dt / .22));
    _angle.value = (_angle.value + _speed * dt) % (2 * math.pi);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(VinylArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final side = math.min(bounds.maxWidth, bounds.maxHeight);
        final label = ClipOval(
            child: Stack(fit: StackFit.expand, children: [
          ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: widget.cover == null
                  ? const Icon(Icons.music_note_rounded, size: 48)
                  : Image(
                      image: widget.cover!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.music_note_rounded, size: 48))),
          Center(
              child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xffdbd9d4),
                      border: Border.all(
                          color: const Color(0xff343438), width: 2)))),
        ]));
        final record = RepaintBoundary(
            child: CustomPaint(
                painter: const _RecordPainter(),
                child: Center(
                    child: FractionallySizedBox(
                        widthFactor: .38, heightFactor: .38, child: label))));
        return Center(
            child: SizedBox.square(
                dimension: side,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: DecoratedBox(
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x38000000),
                                blurRadius: 22,
                                offset: Offset(0, 12))
                          ]),
                      child: ValueListenableBuilder<double>(
                          valueListenable: _angle,
                          child: record,
                          builder: (context, angle, child) =>
                              Transform.rotate(angle: angle, child: child))),
                )));
      });
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            const Color(0xff35353b),
            const Color(0xff111115),
            const Color(0xff29292e)
          ], [
            0,
            .65,
            1
          ]));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65;
    for (double r = radius * .44; r < radius * .96; r += 3) {
      canvas.drawCircle(
          center, r, groove..color = Colors.white.withValues(alpha: .075));
    }
    canvas.drawCircle(center, radius * .99, groove..color = Colors.white24);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.sweep(center, [
            Colors.transparent,
            Colors.white.withValues(alpha: .15),
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: .1),
            Colors.transparent
          ], [
            0,
            .12,
            .25,
            .5,
            .62,
            .78
          ]));
  }

  @override
  bool shouldRepaint(_RecordPainter oldDelegate) => false;
}

/// Uses Flutter's slider for focus, keyboard, accessibility, drag and time bubble.
class WaveSeekBar extends StatefulWidget {
  const WaveSeekBar(
      {super.key,
      required this.value,
      required this.duration,
      required this.onChanged,
      this.onChangeStart,
      this.onChangeEnd,
      this.label,
      this.focusNode,
      this.waveform,
      this.playing = false,
      this.wave = true,
      this.animate = true,
      this.amplitude = 5,
      this.gentle = true});
  final double value, duration, amplitude;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final String? label;
  final FocusNode? focusNode;
  final List<int>? waveform;
  final bool playing, wave, animate, gentle;
  @override
  State<WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<WaveSeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));
  bool _visible = true;
  void _sync() {
    final run = widget.playing &&
        widget.wave &&
        widget.waveform == null &&
        widget.animate &&
        _visible;
    if (run && !_phase.isAnimating) _phase.repeat();
    if (!run && _phase.isAnimating) _phase.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(WaveSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final length =
        widget.duration.isFinite && widget.duration > 0 ? widget.duration : 0.0;
    final position =
        widget.value.isFinite ? widget.value.clamp(0.0, length) : 0.0;
    return AnimatedBuilder(
        animation: _phase,
        builder: (context, _) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  inactiveTrackColor: Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer
                      .withValues(alpha: .25),
                  trackHeight: 3,
                  showValueIndicator: ShowValueIndicator.always,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 22),
                  trackShape: _WaveTrack(
                      waveform: widget.waveform,
                      phase: _phase.value * 2 * math.pi,
                      amplitude: widget.wave
                          ? widget.amplitude * (widget.gentle ? .65 : 1)
                          : 0)),
              child: Slider(
                  focusNode: widget.focusNode,
                  value: position,
                  min: 0,
                  max: length > 0 ? length : 1,
                  label: widget.label,
                  semanticFormatterCallback: (value) => '${value.round()} 秒',
                  onChanged: length > 0 ? widget.onChanged : null,
                  onChangeStart: widget.onChangeStart,
                  onChangeEnd: widget.onChangeEnd),
            ));
  }
}

class _WaveTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _WaveTrack(
      {required this.phase, required this.amplitude, this.waveform});
  final List<int>? waveform;
  final double phase, amplitude;
  @override
  void paint(PaintingContext context, Offset offset,
      {required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required Animation<double> enableAnimation,
      required Offset thumbCenter,
      Offset? secondaryOffset,
      bool isEnabled = false,
      bool isDiscrete = false,
      required TextDirection textDirection}) {
    final rect = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete);
    if (waveform != null && waveform!.isNotEmpty) {
      final peaks = waveform!, rtl = textDirection == TextDirection.rtl;
      final count = math.max(1, (rect.width / 4).floor());
      final paint = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var index = 0; index < count; index++) {
        final from = index * peaks.length ~/ count;
        final to = math
            .max(from + 1, (index + 1) * peaks.length ~/ count)
            .clamp(0, peaks.length);
        var peak = 0;
        for (var bin = from; bin < to; bin++) {
          peak = math.max(peak, peaks[bin]);
        }
        final distance = (index + .5) / count * rect.width;
        final x = rtl ? rect.right - distance : rect.left + distance;
        final active = rtl ? x >= thumbCenter.dx : x <= thumbCenter.dx;
        paint.color = (isEnabled
            ? (active
                ? sliderTheme.activeTrackColor
                : sliderTheme.inactiveTrackColor)
            : sliderTheme.disabledInactiveTrackColor)!;
        final height = 1 + peak / 255 * 15;
        context.canvas.drawLine(Offset(x, rect.center.dy - height),
            Offset(x, rect.center.dy + height), paint);
      }
      return;
    }
    final rtl = textDirection == TextDirection.rtl;
    final start = rtl ? rect.right : rect.left,
        end = thumbCenter.dx.clamp(rect.left, rect.right);
    final inactive = rtl ? rect.left : rect.right;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = (isEnabled
          ? sliderTheme.inactiveTrackColor
          : sliderTheme.disabledInactiveTrackColor)!;
    context.canvas.drawLine(
        Offset(end, rect.center.dy), Offset(inactive, rect.center.dy), paint);
    final distance = (end - start).abs();
    if (distance <= 0) return;
    final path = Path()..moveTo(start, rect.center.dy);
    for (double x = 0; x <= distance; x += 1.5) {
      final taper = math.min(1.0, math.min(x, distance - x) / 12);
      path.lineTo(
          start + (rtl ? -x : x),
          rect.center.dy +
              math.sin(x / 34 * 2 * math.pi - phase) * amplitude * taper);
    }
    path.lineTo(end, rect.center.dy);
    paint.color = (isEnabled
        ? sliderTheme.activeTrackColor
        : sliderTheme.disabledActiveTrackColor)!;
    context.canvas.drawPath(path, paint);
  }
}

class AnimatedPlaybackIcon extends StatelessWidget {
  const AnimatedPlaybackIcon(
      {super.key, required this.playing, this.animate = true});
  final bool playing, animate;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
      duration: Duration(
          milliseconds:
              animate && !MediaQuery.disableAnimationsOf(context) ? 180 : 0),
      transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
              scale: Tween(begin: .75, end: 1.0).animate(animation),
              child: child)),
      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(playing)));
}

class PlaybackPressFeedback extends StatefulWidget {
  const PlaybackPressFeedback(
      {super.key, required this.child, this.animate = true});
  final Widget child;
  final bool animate;
  @override
  State<PlaybackPressFeedback> createState() => _PlaybackPressFeedbackState();
}

class _PlaybackPressFeedbackState extends State<PlaybackPressFeedback> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: (_) => setState(() => pressed = true),
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: AnimatedScale(
          scale: widget.animate && pressed ? .92 : 1,
          duration: Duration(
              milliseconds:
                  widget.animate && !MediaQuery.disableAnimationsOf(context)
                      ? 100
                      : 0),
          child: widget.child));
}
