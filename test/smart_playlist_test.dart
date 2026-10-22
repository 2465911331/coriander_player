import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/smart_playlist_rule.dart';
import 'package:flutter_test/flutter_test.dart';

class LibraryTrack extends Fake implements Audio {
  LibraryTrack(this.path, this.artist);
  @override
  String path;
  @override
  String artist;
  @override
  String title = 'Test';
  @override
  String album = 'Album';
  @override
  int duration = 240;
  @override
  int? bitrate = 900;
}

bool match(SmartPlaylistRule rule,
        {String artist = '林俊杰',
        String album = '她说',
        String title = '一生的爱',
        String path = r'D:\Music\songs\track.FLAC',
        int seconds = 240,
        int? bitrate = 900}) =>
    rule.matches(
        songTitle: title,
        songArtist: artist,
        songAlbum: album,
        filePath: path,
        seconds: seconds,
        bitrate: bitrate);

void main() {
  test('duration range stays a single bounded condition in any-match mode', () {
    const rule = SmartPlaylistRule(
        artist: 'other', minSeconds: 120, maxSeconds: 300, matchAll: false);
    expect(match(rule), isTrue);
    expect(match(rule, seconds: 30), isFalse);
    expect(match(rule, seconds: 500), isFalse);
    expect(match(rule, seconds: 30, artist: 'other'), isTrue);
  });
  test('all conditions use case-insensitive text and inclusive numeric bounds',
      () {
    const rule = SmartPlaylistRule(
        artist: '俊杰',
        album: '她说',
        title: '爱',
        folder: r'd:\music',
        formats: ['flac'],
        minSeconds: 240,
        maxSeconds: 240,
        minBitrate: 900);
    expect(match(rule), isTrue);
    expect(match(rule, artist: '周杰伦'), isFalse);
    expect(match(rule, bitrate: null), isFalse);
    expect(match(rule, seconds: 239), isFalse);
  });
  test('any conditions and empty rules behave predictably', () {
    const rule =
        SmartPlaylistRule(artist: 'other', formats: ['mp3'], matchAll: false);
    expect(match(rule), isFalse);
    expect(match(rule, path: r'D:\Music\file.MP3'), isTrue);
    expect(match(const SmartPlaylistRule()), isTrue);
    expect(match(const SmartPlaylistRule(matchAll: false)), isTrue);
  });
  test(
      'folder includes children, handles slashes, and excludes similar siblings',
      () {
    const rule = SmartPlaylistRule(folder: 'D:/Music/songs/');
    expect(match(rule), isTrue);
    expect(match(rule, path: r'd:\music\songs\disc1\a.flac'), isTrue);
    expect(match(rule, path: r'D:\Music\songs-old\a.flac'), isFalse);
  });
  test('format matching is exact and accepts leading dots', () {
    const rule = SmartPlaylistRule(formats: ['.FLAC', 'mp3']);
    expect(match(rule), isTrue);
    expect(match(rule, path: 'D:/a.flac.backup'), isFalse);
  });
  test('smart rules survive playlist JSON and preserve legacy compatibility',
      () {
    final old = Playlist.fromMap({'name': 'Original', 'audios': []});
    expect(old.isSmart, isFalse);
    expect(old.toMap(), {'name': 'Original', 'audios': []});
    final smart = Playlist('Lossless', {},
        smartRule: const SmartPlaylistRule(
            formats: ['flac', 'ape'], minSeconds: 120, matchAll: false));
    final restored = Playlist.fromMap(smart.toMap());
    expect(restored.isSmart, isTrue);
    expect(restored.smartRule!.toJson(), smart.smartRule!.toJson());
    expect(restored.toMap()['audios'], isEmpty);
  });
  test('rules re-evaluate new tracks rather than saving a fixed match list',
      () {
    final library = AudioLibrary.instance;
    final original = library.audioCollection;
    try {
      library.audioCollection = [LibraryTrack('C:/other.wav', '周杰伦')];
      AudioLibrary.revision.value++;
      final playlist = Playlist('Smart', {},
          smartRule: const SmartPlaylistRule(artist: '林俊杰'));
      expect(playlist.audios, isEmpty);
      library.audioCollection.add(LibraryTrack('C:/new.wav', '林俊杰'));
      AudioLibrary.revision.value++;
      expect(playlist.audios.keys, ['C:/new.wav']);
      library.audioCollection.removeLast();
      AudioLibrary.revision.value++;
      expect(playlist.audios, isEmpty);
      playlist.smartRule = const SmartPlaylistRule(artist: '周杰伦');
      expect(playlist.audios.keys, ['C:/other.wav']);
    } finally {
      library.audioCollection = original;
      AudioLibrary.revision.value++;
    }
  });
}
