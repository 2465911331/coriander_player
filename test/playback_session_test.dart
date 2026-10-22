import 'dart:io';
import 'package:coriander_player/play_service/playback_session.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackSession snapshot(
        {List<String>? paths, int index = 1, double position = 42}) =>
    PlaybackSession(
      paths: paths ?? ['c.wav', 'a.wav', 'b.wav'],
      originalPaths: ['a.wav', 'b.wav', 'c.wav'],
      index: index,
      position: position,
      shuffle: true,
      playMode: 'loop',
      volume: .65,
    );

void main() {
  test(
      'queue order, original order, selected duplicate and progress survive JSON',
      () {
    final saved = snapshot(paths: ['a.wav', 'a.wav', 'b.wav']);
    final loaded = PlaybackSession.fromJson(saved.toJson());
    final restored = loaded.resolve<String>((value) => value)!;
    expect(restored.queue, ['a.wav', 'a.wav', 'b.wav']);
    expect(restored.index, 1);
    expect(restored.position, 42);
    expect(restored.originalQueue, ['a.wav', 'b.wav', 'c.wav']);
    expect(loaded.shuffle, isTrue);
    expect(loaded.playMode, 'loop');
    expect(loaded.volume, .65);
  });

  test(
      'missing earlier tracks adjust the selected index without losing progress',
      () {
    final restored =
        snapshot().resolve<String>((value) => value == 'c.wav' ? null : value)!;
    expect(restored.queue, ['a.wav', 'b.wav']);
    expect(restored.index, 0);
    expect(restored.position, 42);
  });

  test('missing current track chooses next surviving song at zero', () {
    final restored =
        snapshot().resolve<String>((value) => value == 'a.wav' ? null : value)!;
    expect(restored.queue[restored.index], 'b.wav');
    expect(restored.position, 0);
  });

  test('missing final track wraps to the first surviving song at zero', () {
    final restored = snapshot(index: 2)
        .resolve<String>((value) => value == 'b.wav' ? null : value)!;
    expect(restored.index, 0);
    expect(restored.position, 0);
  });

  test('no surviving files yields no restored session', () {
    expect(snapshot().resolve<String>((_) => null), isNull);
  });

  test(
      'rejects invalid index, negative progress, unknown schema and bad volume',
      () {
    for (final patch in [
      {'index': -1},
      {'index': 3},
      {'position': -1},
      {'position': double.nan},
      {'version': 99},
      {'volume': 4},
    ]) {
      expect(() => PlaybackSession.fromJson({...snapshot().toJson(), ...patch}),
          throwsFormatException);
    }
  });

  group('session file', () {
    late Directory directory;
    late PlaybackSessionStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('coriander-session-');
      store = PlaybackSessionStore(() async => directory.path);
    });
    tearDown(() => directory.delete(recursive: true));

    test('fresh install has no session; save survives a new store instance',
        () async {
      expect(await store.read(), isNull);
      await store.save(snapshot());
      final loaded =
          await PlaybackSessionStore(() async => directory.path).read();
      expect(loaded!.toJson(), snapshot().toJson());
    });

    test('corrupt file recovers the previous valid progress', () async {
      await store.save(snapshot(position: 20));
      await store.save(snapshot(position: 40));
      await File('${directory.path}/playback_session.json')
          .writeAsString('{bad');
      expect((await store.read())!.position, 20);
    });

    test('turning memory off clears a session after an outstanding save',
        () async {
      final save = store.save(snapshot());
      final clear = store.clear();
      await Future.wait([save, clear]);
      expect(await store.read(), isNull);
    });
  });
}
