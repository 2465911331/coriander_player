import 'dart:async';
import 'dart:math';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_session.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

class LyricService extends ChangeNotifier {
  final PlayService playService;
  final _session = LyricSession();
  final _lines = StreamController<int>.broadcast();
  late final StreamSubscription<double> _positionSubscription;
  int _currentLine = -1;
  bool _disposed = false;

  LyricService(this.playService) {
    _positionSubscription = playService.playbackService.positionStream.listen(
      (position) => _updatePosition(position),
    );
  }

  Future<Lyric?> currLyricFuture = Future.value(null);
  Lyric? get currentLyric => _session.value;

  Stream<int> get lyricLineStream async* {
    if (_disposed) return;
    yield max(_currentLine, 0);
    yield* _lines.stream;
  }

  void _updatePosition(double seconds, {bool force = false}) {
    if (_disposed || _session.value == null) return;
    final index =
        _session.lineAt(Duration(milliseconds: (seconds * 1000).floor()));
    if (!force && index == _currentLine) return;
    _currentLine = index;
    final lyric = _session.value!;
    if (lyric.lines.isEmpty) return;
    _lines.add(max(index, 0));
    if (index >= 0) {
      playService.desktopLyricService.sendLyricLineMessage(lyric.lines[index]);
    } else {
      playService.desktopLyricService.clearLyric();
    }
  }

  void findCurrLyricLine() =>
      _updatePosition(playService.playbackService.position, force: true);

  Future<Lyric?> _getDefault(Audio audio) async {
    if (AppSettings.instance.localLyricFirst) {
      return await Lrc.fromAudioPath(audio) ?? await getMostMatchedLyric(audio);
    }
    return await getMostMatchedLyric(audio) ?? await Lrc.fromAudioPath(audio);
  }

  void _load(Future<Lyric?> request) {
    _currentLine = -1;
    playService.desktopLyricService.clearLyric();
    final safeRequest = request.catchError((Object error, StackTrace stack) {
      LOGGER.e(error, stackTrace: stack);
      return null;
    });
    currLyricFuture = _session.load(safeRequest, findCurrLyricLine);
    notifyListeners();
  }

  void updateLyric() {
    final audio = playService.playbackService.nowPlaying;
    if (audio == null) return;
    final source = LYRIC_SOURCES[audio.path];
    if (source == null) {
      _load(_getDefault(audio));
    } else if (source.source == LyricSourceType.local) {
      _load(Lrc.fromAudioPath(audio));
    } else {
      _load(getOnlineLyric(
          qqSongId: source.qqSongId,
          kugouSongHash: source.kugouSongHash,
          neteaseSongId: source.neteaseSongId));
    }
  }

  void useLocalLyric() {
    final audio = playService.playbackService.nowPlaying;
    if (audio != null) _load(Lrc.fromAudioPath(audio));
  }

  void useOnlineLyric() {
    final audio = playService.playbackService.nowPlaying;
    if (audio != null) _load(getMostMatchedLyric(audio));
  }

  void useSpecificLyric(Lyric lyric) => _load(Future.value(lyric));

  @override
  void dispose() {
    _disposed = true;
    _session.dispose();
    _positionSubscription.cancel();
    _lines.close();
    super.dispose();
  }
}
