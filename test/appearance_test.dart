import 'dart:convert';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/cover_backdrop.dart';
import 'package:coriander_player/component/playback_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool visible = true, bool reduceMotion = false}) =>
    MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: TickerMode(
                enabled: visible,
                child: Scaffold(
                    body: Center(
                        child: SizedBox(
                            width: 400, height: 400, child: child))))));

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

double recordAngle(WidgetTester tester) {
  final finder = find.descendant(
      of: find.byType(VinylArtwork), matching: find.byType(Transform));
  return tester.widget<Transform>(finder.first).transform.storage[1];
}

void main() {
  test('appearance survives JSON round trip without losing custom choices', () {
    final settings = AppearancePreferences()
      ..artwork = ArtworkStyle.classic
      ..progress = ProgressStyle.line
      ..motion = MotionLevel.full
      ..rotationSeconds = 32
      ..waveAmplitude = 7
      ..backgroundBlur = 42
      ..backgroundStrength = .5
      ..savePower = false
      ..coverBackground = false
      ..animateControls = false;
    final restored = AppearancePreferences()
      ..read(jsonDecode(jsonEncode(settings.toJson())));
    expect(restored.toJson(), settings.toJson());
  });
  test('old settings and unknown enum values retain usable defaults', () {
    final settings = AppearancePreferences()..read(null);
    expect(settings.artwork, ArtworkStyle.vinyl);
    settings.read({'artwork': 'future', 'motion': 1, 'progress': ''});
    expect(settings.motion, MotionLevel.gentle);
    expect(settings.progress, ProgressStyle.wave);
  });
  test('invalid numeric preferences cannot break painters or tickers', () {
    final settings = AppearancePreferences()
      ..read({
        'rotationSeconds': 0,
        'waveAmplitude': double.nan,
        'backgroundBlur': double.infinity,
        'backgroundStrength': 90
      });
    expect(settings.rotationSeconds, 12);
    expect(settings.waveAmplitude, 5);
    expect(settings.backgroundBlur, 28);
    expect(settings.backgroundStrength, .6);
  });

  testWidgets('wave seek preserves drag completion and keyboard seeking',
      (tester) async {
    double value = 20;
    final seeks = <double>[];
    final seekFocus = FocusNode();
    addTearDown(seekFocus.dispose);
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => WaveSeekBar(
            value: value,
            focusNode: seekFocus,
            duration: 100,
            onChanged: (next) => setState(() => value = next),
            onChangeEnd: seeks.add))));
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(20));
    final beforeKey = value;
    seekFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, greaterThan(beforeKey));
    expect(seeks, hasLength(2));
  });
  testWidgets(
      'empty duration disables seeking and invalid positions are clamped',
      (tester) async {
    await tester.pumpWidget(host(WaveSeekBar(
        value: double.nan, duration: 0, onChanged: (_) => fail('disabled'))));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await tester.pumpWidget(
        host(WaveSeekBar(value: 900, duration: 100, onChanged: (_) {})));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 100);
    expect(tester.takeException(), isNull);
  });
  testWidgets('waves animate only while playing and visible', (tester) async {
    Widget seek({bool playing = true}) => WaveSeekBar(
        value: 40, duration: 100, playing: playing, onChanged: (_) {});
    await tester.pumpWidget(host(seek()));
    await frames(tester, 3);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(seek(playing: false)));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(seek(), visible: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(seek(), reduceMotion: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('record coasts to rest and resumes at the preserved angle',
      (tester) async {
    await tester.pumpWidget(host(const VinylArtwork(playing: true)));
    await frames(tester, 30);
    expect(recordAngle(tester), greaterThan(0));
    await tester.pumpWidget(host(const VinylArtwork(playing: false)));
    final pauseAngle = recordAngle(tester);
    await frames(tester, 100);
    final stoppedAngle = recordAngle(tester);
    expect(stoppedAngle, greaterThan(pauseAngle));
    expect(tester.binding.transientCallbackCount, 0);
    await frames(tester, 10);
    expect(recordAngle(tester), stoppedAngle);
    await tester.pumpWidget(host(const VinylArtwork(playing: true)));
    expect(recordAngle(tester), stoppedAngle);
    await frames(tester, 10);
    expect(recordAngle(tester), greaterThan(stoppedAngle));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'hidden records freeze immediately and restore without a time jump',
      (tester) async {
    await tester.pumpWidget(host(const VinylArtwork(playing: true)));
    await frames(tester, 20);
    await tester
        .pumpWidget(host(const VinylArtwork(playing: true), visible: false));
    final before = recordAngle(tester);
    await tester.pump(const Duration(minutes: 10));
    expect(recordAngle(tester), before);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(const VinylArtwork(playing: true)));
    expect(recordAngle(tester), before);
    await frames(tester, 10);
    expect(recordAngle(tester), greaterThan(before));
  });
  testWidgets('motion disabled leaves artwork static and controls clickable',
      (tester) async {
    await tester
        .pumpWidget(host(const VinylArtwork(playing: true, animate: false)));
    await frames(tester, 4);
    expect(recordAngle(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    var presses = 0;
    await tester.pumpWidget(host(PlaybackPressFeedback(
        animate: false,
        child: IconButton(
            tooltip: '播放',
            onPressed: () => presses++,
            icon:
                const AnimatedPlaybackIcon(playing: false, animate: false)))));
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });
  testWidgets(
      'backdrop tolerates corrupt images and removes cover when disabled',
      (tester) async {
    final broken = MemoryImage(Uint8List.fromList([1, 2, 3]));
    await tester.pumpWidget(host(CoverBackdrop(cover: broken, trackKey: 'a')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
        host(CoverBackdrop(cover: broken, trackKey: 'a', enabled: false)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });
}
