import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/audio_spectrum.dart';
import 'package:coriander_player/component/lyric_visuals.dart';
import 'package:coriander_player/component/playback_visuals.dart';
import 'package:coriander_player/play_service/waveform_cache.dart';
import 'package:coriander_player/play_service/waveform_model.dart';
import 'package:coriander_player/src/bass/analysis_queue.dart';
import 'package:coriander_player/src/bass/spectrum_reader.dart';
import 'package:flutter/material.dart';
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
                            width: 400, height: 100, child: child))))));

void main() {
  test('second-batch preferences migrate and round-trip with safe bounds', () {
    final preferences = AppearancePreferences()
      ..read({
        'spectrum': 'unknown',
        'inactiveLyricOpacity': double.nan,
        'lyricLineSpacing': 999
      });
    expect(preferences.spectrum, SpectrumStyle.bars);
    expect(preferences.inactiveLyricOpacity, .38);
    expect(preferences.lyricLineSpacing, 24);
    preferences.progress = ProgressStyle.waveform;
    preferences.spectrum = SpectrumStyle.ring;
    preferences.lyricEdgeFade = false;
    expect(
        (AppearancePreferences()
              ..read(jsonDecode(jsonEncode(preferences.toJson()))))
            .toJson(),
        preferences.toJson());
  });
  test('envelope preserves stereo transients and relative quiet sections', () {
    final samples = WaveformAccumulator(8, 2, columns: 4);
    samples.add([0, .1, 0, .25, 0, .5, 0, .2], 8);
    samples.add([0, 1, 0, .1, 0, 0, 0, 0], 8);
    expect(samples.finish(), [64, 128, 255, 0]);
    expect(samples.frames, 8);
  });
  test('silence remains silent and invalid PCM does not contaminate envelope',
      () {
    final samples = WaveformAccumulator(4, 1, columns: 4);
    samples.add([double.nan, 0, double.infinity, 0], 4);
    expect(samples.finish(), [0, 0, 0, 0]);
    expect(
        WaveformData.fromJson({
          'version': 1,
          'duration': 5,
          'peaks': [255]
        }),
        isNull);
    expect(
        WaveformData.fromJson(WaveformData(10, List.filled(1200, 5)).toJson())
            ?.peaks,
        hasLength(1200));
  });
  test('frequency bands distinguish low and high tones, never invent silence',
      () {
    final low = List.filled(1024, 0.0)..[5] = .7;
    final high = List.filled(1024, 0.0)..[300] = .7;
    final lowBands = spectrumBands(low, 48000),
        highBands = spectrumBands(high, 48000);
    expect(lowBands.indexWhere((value) => value > .8),
        lessThan(highBands.indexWhere((value) => value > .8)));
    expect(spectrumBands(List.filled(1024, 0), 48000), everyElement(0));
    expect(
        spectrumBands([double.nan, double.infinity], 48000), everyElement(0));
  });
  test('native jobs serialize and a failure cannot block the next worker',
      () async {
    final queue = AudioAnalysisQueue(),
        gate = Completer<void>(),
        events = <String>[];
    final first = queue.run(() async {
      events.add('first');
      await gate.future;
      events.add('end');
    });
    final failed = queue.run<void>(() async {
      events.add('failed');
      throw StateError('fixture');
    });
    final failure = expectLater(failed, throwsStateError);
    final last = queue.run(() async {
      events.add('last');
      return 3;
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first']);
    gate.complete();
    await first;
    await failure;
    expect(await last, 3);
    expect(events, ['first', 'end', 'failed', 'last']);
  });
  test(
      'word progress handles pause positions, zero durations and invalid values',
      () {
    expect(lyricWordProgress(2500, 2000, 1000), .5);
    expect(lyricWordProgress(1999, 2000, 0), 0);
    expect(lyricWordProgress(2000, 2000, 0), 1);
    expect(lyricWordProgress(double.nan, 0, 0), 0);
    expect(lyricWordProgress(9999, 2000, 1000), 1);
  });

  group('waveform cache', () {
    late Directory directory;
    late File audio;
    late int analyses;
    late WaveformCache cache;
    WaveformCache create() => WaveformCache(
        directory: () async => '${directory.path}/cache',
        analyze: (_) async {
          analyses++;
          return WaveformData(10, List.filled(1200, analyses));
        });
    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('coriander-waveform-test-');
      audio = await File('${directory.path}/track.wav').writeAsBytes([1, 2, 3]);
      analyses = 0;
      cache = create();
    });
    tearDown(() => directory.delete(recursive: true));
    test('deduplicates concurrent requests and reuses disk cache after restart',
        () async {
      final results =
          await Future.wait([cache.load(audio.path), cache.load(audio.path)]);
      expect(analyses, 1);
      expect(results[0]?.peaks, results[1]?.peaks);
      expect((await create().load(audio.path))?.peaks.first, 1);
      expect(analyses, 1);
    });
    test('file changes invalidate cached envelopes', () async {
      await cache.load(audio.path);
      await audio.writeAsBytes([1, 2, 3, 4]);
      expect((await cache.load(audio.path))?.peaks.first, 2);
      expect(analyses, 2);
    });
    test('corrupt and invalid caches are rebuilt; missing files do not analyze',
        () async {
      await cache.load(audio.path);
      final file = (await Directory('${directory.path}/cache').list().toList())
          .whereType<File>()
          .single;
      await file.writeAsString('{broken');
      expect((await create().load(audio.path))?.peaks.first, 2);
      expect(analyses, 2);
      expect(await cache.load('${directory.path}/missing.wav'), isNull);
      expect(analyses, 2);
    });
    test('file replaced during analysis never receives a usable cache',
        () async {
      cache = WaveformCache(
          directory: () async => '${directory.path}/cache',
          analyze: (_) async {
            await audio.writeAsBytes([9, 8, 7, 6]);
            return WaveformData(10, List.filled(1200, 5));
          });
      expect(await cache.load(audio.path), isNull);
      expect(
          await Directory('${directory.path}/cache').list().toList(), isEmpty);
    });
    test('unwritable cache location still returns an in-memory waveform',
        () async {
      cache = WaveformCache(
          directory: () async => audio.path,
          analyze: (_) async => WaveformData(5, List.filled(1200, 10)));
      expect((await cache.load(audio.path))?.peaks.first, 10);
    });
  });

  testWidgets(
      'spectrum samples only while playing, visible and animations enabled',
      (tester) async {
    var reads = 0;
    Widget spectrum({bool playing = true, bool animate = true}) =>
        AudioSpectrum(
            playing: playing,
            animate: animate,
            readSpectrum: () {
              reads++;
              return List.filled(40, .4);
            });
    await tester.pumpWidget(host(spectrum()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(reads, greaterThan(1));
    await tester.pumpWidget(host(spectrum(playing: false)));
    var before = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
    await tester.pumpWidget(host(spectrum(), visible: false));
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
    await tester.pumpWidget(host(spectrum(), reduceMotion: true));
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
    await tester.pumpWidget(host(spectrum()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(reads, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    before = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
  });
  testWidgets('ring handles invalid samples and clears when song changes',
      (tester) async {
    await tester.pumpWidget(host(AudioSpectrum(
        playing: true,
        ring: true,
        trackKey: 'a',
        readSpectrum: () => [double.nan, double.infinity, -.5, 90])));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(AudioSpectrum(
        playing: false,
        ring: true,
        trackKey: 'b',
        readSpectrum: () => throw StateError('ended'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('whole-song waveform retains native seek completion',
      (tester) async {
    double? sought;
    await tester.pumpWidget(host(WaveSeekBar(
        value: 30,
        duration: 100,
        wave: false,
        waveform: List.generate(1200, (index) => index % 256),
        onChanged: (_) {},
        onChangeEnd: (value) => sought = value)));
    await tester
        .tapAt(tester.getCenter(find.byType(Slider)) + const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(sought, greaterThan(50));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'lyric focus preserves taps and reduced motion has no scale animation',
      (tester) async {
    var taps = 0;
    Widget line(bool active) => LyricLinePresentation(
        active: active,
        child: TextButton(
            onPressed: () => taps++, child: const Text('A lyric line')));
    await tester.pumpWidget(host(line(false)));
    await tester.pumpWidget(host(line(true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A lyric line'));
    expect(taps, 1);
    await tester.pumpWidget(host(line(true), reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
      'interlude stops in background, remains static on pause and disposes cleanly',
      (tester) async {
    await tester
        .pumpWidget(host(const InterludeDots(progress: .5, playing: true)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(
        host(const InterludeDots(progress: .5, playing: true), visible: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester
        .pumpWidget(host(const InterludeDots(progress: 1, playing: false)));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
