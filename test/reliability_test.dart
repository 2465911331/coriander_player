import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:coriander_player/storage/safe_json.dart';
import 'package:coriander_player/ipc/lines.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_session.dart';
import 'package:coriander_player/library/playlist.dart';

class TestLyric extends Lyric {
  TestLyric(List<int> times)
      : super(times.map((t) => TestLine(Duration(milliseconds: t))).toList());
}
class TestLine extends LyricLine {
  TestLine(super.start);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('safe storage', () {
    late Directory directory;
    late String path;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('coriander-json-test-');
      path = '${directory.path}/state.json';
    });
    tearDown(() => directory.delete(recursive: true));
    test('overlapping saves preserve order and a previous valid snapshot', () async {
      await Future.wait([
        writeJsonSafely(path, {'version': 1}),
        writeJsonSafely(path, {'version': 2}),
        writeJsonSafely(path, {'version': 3}),
      ]);
      expect(await readJsonSafely(path, {}), {'version': 3});
      expect(json.decode(await File('$path.bak').readAsString()), {'version': 2});
    });
    test('corrupt original recovers from backup and does not overwrite it', () async {
      await writeJsonSafely(path, {'version': 1});
      await writeJsonSafely(path, {'version': 2});
      await File(path).writeAsString('{broken');
      expect(await readJsonSafely(path, {}), {'version': 1});
      await writeJsonSafely(path, {'version': 3});
      expect(json.decode(await File('$path.bak').readAsString()), {'version': 1});
    });
    test('missing original recovers backup, missing both yields initial state', () async {
      expect(await readJsonSafely(path, []), []);
      await writeJsonSafely(path, [1]);
      await writeJsonSafely(path, [2]);
      await File(path).delete();
      expect(await readJsonSafely(path, []), [1]);
    });
    test('failed save leaves original intact and later saves can succeed', () async {
      await writeJsonSafely(path, [1]);
      await Directory('$path.tmp').create();
      await expectLater(writeJsonSafely(path, [2]), throwsA(isA<FileSystemException>()));
      expect(await readJsonSafely(path, []), [1]);
      await Directory('$path.tmp').delete();
      await writeJsonSafely(path, [3]);
      expect(await readJsonSafely(path, []), [3]);
    });
  });

  group('lyrics', () {
    test('old song arriving last cannot replace current lyrics or reset position', () async {
      final session = LyricSession();
      final old = Completer<Lyric?>();
      final current = Completer<Lyric?>();
      var notifications = 0;
      final oldResult = session.load(old.future, () => notifications++);
      final currentResult = session.load(current.future, () => notifications++);
      final lyric = TestLyric([100, 500, 900]);
      current.complete(lyric);
      await currentResult;
      expect(session.lineAt(const Duration(milliseconds: 750)), 1);
      old.complete(TestLyric([0]));
      expect(await oldResult, isNull);
      expect(session.value, same(lyric));
      expect(notifications, 1);
    });
    test('seeking, equal timestamps, delayed loading and empty lyrics', () async {
      final session = LyricSession();
      await session.load(Future.value(TestLyric([100, 500, 500, 900])), () {});
      expect(session.lineAt(Duration.zero), -1);
      expect(session.lineAt(const Duration(milliseconds: 500)), 2);
      expect(session.lineAt(const Duration(seconds: 5)), 3);
      expect(session.lineAt(const Duration(milliseconds: 100)), 0);
      await session.load(Future.value(TestLyric([])), () {});
      expect(session.lineAt(Duration.zero), -1);
    });
    test('dispose ignores an outstanding request', () async {
      final session = LyricSession();
      final request = Completer<Lyric?>();
      var changed = false;
      final pending = session.load(request.future, () => changed = true);
      session.dispose();
      request.complete(TestLyric([0]));
      await pending;
      expect(changed, isFalse);
      expect(session.value, isNull);
    });
  });

  test('pipe framing handles byte-wise UTF-8, merged JSON and escaped newlines', () async {
    final messages = [ {'text': '歌词\n第二行🎵'}, {'playing': true}, {'title': '下一首'} ];
    final bytes = utf8.encode(messages.map(json.encode).join('\n') + '\n');
    final split = await messageLines(Stream.fromIterable(bytes.map((b) => [b])))
        .map(json.decode).toList();
    final merged = await messageLines(Stream.value(bytes)).map(json.decode).toList();
    expect(split, messages);
    expect(merged, messages);
  });

  test('playlist reread preserves in-memory edits without appending duplicates', () async {
    final root = Platform.environment['CORIANDER_DATA_DIR'];
    expect(root, isNotNull, reason: 'Tests must use an isolated data directory');
    final file = '$root/playlists.json';
    await writeJsonSafely(file, [{'name': 'original', 'audios': []}]);
    playlistsLoaded = false;
    PLAYLISTS = [];
    await readPlaylists();
    expect(PLAYLISTS.length, 1);
    PLAYLISTS.first.name = 'edited';
    await readPlaylists();
    expect(PLAYLISTS.single.name, 'edited');
    schedulePlaylistSave();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final saved = await readJsonSafely(file, []) as List;
    expect(saved.single['name'], 'edited');
    await savePlaylists();
  });
}
