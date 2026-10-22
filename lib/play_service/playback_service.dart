import 'dart:async';
import 'dart:io';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/lifecycle_trace.dart';
import 'package:coriander_player/play_service/playback_session.dart';
import 'package:coriander_player/play_service/loudness_service.dart';
import 'package:coriander_player/src/bass/gapless_mixer.dart';
import 'package:path/path.dart' as path;

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/src/rust/api/smtc_flutter.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

enum PlayMode {
  /// 顺序播放到播放列表结尾
  forward,

  /// 循环整个播放列表
  loop,

  /// 循环播放单曲
  singleLoop;

  static PlayMode? fromString(String playMode) {
    for (var value in PlayMode.values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

/// 只通知 now playing 变更
class PlaybackService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _playerStateStreamSub;
  late StreamSubscription _smtcEventStreamSub;
  late StreamSubscription _positionStreamSub;
  late StreamSubscription<int> _transitionSub;
  Timer? _prepareTimer;
  int? _lastSmtcSecond;
  bool _closing = false;
  bool _restoreAttempted = false;
  Timer? _sessionSaveTimer;
  Timer? _sessionCheckpoint;
  final _sessionStore = PlaybackSessionStore(
    () async => (await getAppDataDir()).path,
  );

  PlaybackService(this.playService) {
    _transitionSub = _player.trackTransitions.listen(_onGaplessTransition);
    LoudnessService.instance.addListener(_applyNormalization);
    _playerStateStreamSub = playerStateStream.listen((event) {
      if (event == PlayerState.completed) {
        _autoNextAudio();
      }
    });

    _smtcEventStreamSub = _smtc.subscribeToControlEvents().listen((event) {
      if (_closing) return;
      switch (event) {
        case SMTCControlEvent.play:
          start();
          break;
        case SMTCControlEvent.pause:
          pause();
          break;
        case SMTCControlEvent.previous:
          lastAudio();
          break;
        case SMTCControlEvent.next:
          nextAudio();
          break;
        case SMTCControlEvent.unknown:
      }
    });

    _positionStreamSub = positionStream.listen((progress) {
      final second = progress.floor();
      if (second == _lastSmtcSecond) return;
      _lastSmtcSecond = second;
      _smtc.updateTimeProperties(progress: (progress * 1000).floor());
    });
    playlist.addListener(_scheduleSessionSave);
    playlist.addListener(_schedulePrepareNext);
    _sessionCheckpoint = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playerState == PlayerState.playing) _scheduleSessionSave();
    });
  }

  final _player = BassPlayer();
  final _smtc = SmtcFlutter();
  final _pref = AppPreference.instance.playbackPref;

  late final _wasapiExclusive = ValueNotifier(_player.wasapiExclusive);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    if (_player.useExclusiveMode(exclusive)) {
      _wasapiExclusive.value = exclusive;
      _schedulePrepareNext();
      _applyNormalization();
    }
  }

  Audio? nowPlaying;

  int? _playlistIndex;
  int get playlistIndex => _playlistIndex ?? 0;

  final ValueNotifier<List<Audio>> playlist = ValueNotifier([]);
  List<Audio> _playlistBackup = [];

  late final _playMode = ValueNotifier(_pref.playMode);
  ValueNotifier<PlayMode> get playMode => _playMode;

  void setPlayMode(PlayMode playMode) {
    this.playMode.value = playMode;
    _pref.playMode = playMode;
    _scheduleSessionSave();
    _schedulePrepareNext();
  }

  late final _shuffle = ValueNotifier(false);
  ValueNotifier<bool> get shuffle => _shuffle;

  double get length => _player.length;

  double get position => _player.position;

  PlayerState get playerState => _player.playerState;

  List<double> readSpectrum() => _closing ? const [] : _player.readSpectrum();

  double get volumeDsp => _player.volumeDsp;

  /// 修改解码时的音量（不影响 Windows 系统音量）
  void setVolumeDsp(double volume) {
    _player.setVolumeDsp(volume);
    _pref.volumeDsp = volume;
    _scheduleSessionSave();
  }

  Stream<double> get positionStream => _player.positionStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 1. 更新 [_playlistIndex] 为 [audioIndex]
  /// 2. 更新 [nowPlaying] 为 playlist[_nowPlayingIndex]
  /// 3. _bassPlayer.setSource
  /// 4. 设置解码音量
  /// 4. 获取歌词 **将 [_nextLyricLine] 置为0**
  /// 5. 播放
  /// 6. 通知并更新主题色
  bool _loadAndPlay(int audioIndex, List<Audio> playlist,
      {bool autoPlay = true, double resumePosition = 0}) {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) return false;
      _lastSmtcSecond = null;
      final audio = playlist[audioIndex];
      _player.gaplessEnabled = AppSettings.instance.gaplessPlayback;
      _player.setSource(audio.path,
          token: audioIndex,
          normalizationGain: LoudnessService.instance.gainFor(audio));
      _playlistIndex = audioIndex;
      nowPlaying = audio;
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      // Never start the output device just to restore a paused session.
      final target = resumePosition.isFinite &&
              resumePosition >= 0 &&
              resumePosition < length
          ? resumePosition
          : 0.0;
      if (target > 0) _player.seek(target);

      playService.lyricService.updateLyric();

      if (autoPlay) _player.start();
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      _smtc.updateState(state: autoPlay ? SMTCState.playing : SMTCState.paused);
      _smtc.updateDisplay(
        title: nowPlaying!.title,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.path,
      );
      _smtc.updateTimeProperties(progress: (target * 1000).floor());

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
      _scheduleSessionSave();
      _schedulePrepareNext();
      return true;
    } catch (err) {
      LOGGER.e("[load and play] $err");
      showTextOnSnackBar(err.toString());
      return false;
    }
  }

  /// 播放当前播放列表的第几项，只能用在播放列表界面
  void playIndexOfPlaylist(int audioIndex) {
    _loadAndPlay(audioIndex, playlist.value);
  }

  /// 播放playlist[audioIndex]并设置播放列表为playlist
  void play(int audioIndex, List<Audio> playlist) {
    if (shuffle.value) {
      this.playlist.value = List.from(playlist);
      final willPlay = this.playlist.value.removeAt(audioIndex);
      this.playlist.value.shuffle();
      this.playlist.value.insert(0, willPlay);
      _playlistBackup = List.from(playlist);
      _loadAndPlay(0, this.playlist.value);
    } else {
      _loadAndPlay(audioIndex, playlist);
      this.playlist.value = List.from(playlist);
      _playlistBackup = List.from(playlist);
    }
    _scheduleSessionSave();
  }

  void shuffleAndPlay(List<Audio> audios) {
    playlist.value = List.from(audios);
    playlist.value.shuffle();
    _playlistBackup = List.from(audios);

    shuffle.value = true;

    _loadAndPlay(0, playlist.value);
  }

  /// 下一首播放
  void addToNext(Audio audio) {
    if (_playlistIndex != null) {
      final updated = List<Audio>.from(playlist.value);
      updated.insert(_playlistIndex! + 1, audio);
      playlist.value = updated;
      _playlistBackup = List.from(playlist.value);
    }
  }

  void useShuffle(bool flag) {
    if (nowPlaying == null) return;
    if (flag == shuffle.value) return;

    if (flag) {
      playlist.value.shuffle();
      playlist.value.remove(nowPlaying!);
      playlist.value.insert(0, nowPlaying!);
      _playlistIndex = 0;
      shuffle.value = true;
    } else {
      playlist.value = List.from(_playlistBackup);
      _playlistIndex = playlist.value.indexOf(nowPlaying!);
      shuffle.value = false;
    }
    _scheduleSessionSave();
    _schedulePrepareNext();
  }

  void _schedulePrepareNext() {
    if (_closing) return;
    _prepareTimer?.cancel();
    _prepareTimer = Timer(Duration.zero, _prepareNext);
  }

  void _prepareNext() {
    if (_closing ||
        nowPlaying == null ||
        _playlistIndex == null ||
        playlist.value.isEmpty) return;
    unawaited(LoudnessService.instance.ensureFor(nowPlaying!));
    final tracks = <GaplessTrack>[];
    var index = _playlistIndex!;
    var seconds = 0;
    for (var count = 0;
        count < 32 && (tracks.length < 2 || seconds < 5);
        count++) {
      if (playMode.value != PlayMode.singleLoop) {
        index++;
        if (index >= playlist.value.length) {
          if (playMode.value == PlayMode.forward) break;
          index = 0;
        }
      }
      final audio = playlist.value[index];
      if (!File(audio.path).existsSync()) continue;
      tracks.add(GaplessTrack(audio.path, index,
          gain: LoudnessService.instance.gainFor(audio)));
      seconds += audio.duration;
      unawaited(LoudnessService.instance.ensureFor(audio));
    }
    try {
      _player.prepareNext(tracks);
    } catch (error, stack) {
      LOGGER.e('Unable to prepare next track: $error', stackTrace: stack);
    }
  }

  void _applyNormalization() {
    if (_closing || nowPlaying == null) return;
    _player.updateNormalization(LoudnessService.instance.gainFor(nowPlaying!),
        (track) {
      if (track.token < 0 || track.token >= playlist.value.length) return 1;
      final audio = playlist.value[track.token];
      return audio.path == track.path
          ? LoudnessService.instance.gainFor(audio)
          : 1;
    });
  }

  void updateAudioSettings({bool rebuildOutput = false}) {
    if (nowPlaying == null || _playlistIndex == null) return;
    if (rebuildOutput) {
      final wasPlaying = playerState == PlayerState.playing;
      final at = position;
      _loadAndPlay(_playlistIndex!, playlist.value,
          autoPlay: wasPlaying, resumePosition: at);
    } else {
      _applyNormalization();
    }
    _schedulePrepareNext();
  }

  void _onGaplessTransition(int index) {
    if (_closing || index < 0 || index >= playlist.value.length) return;
    _playlistIndex = index;
    nowPlaying = playlist.value[index];
    _lastSmtcSecond = null;
    _player.acknowledgeTransition(nowPlaying!.path);
    _applyNormalization();
    playService.lyricService.updateLyric();
    notifyListeners();
    ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);
    _smtc.updateDisplay(
        title: nowPlaying!.title,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.path);
    _smtc.updateState(
        state: playerState == PlayerState.playing
            ? SMTCState.playing
            : SMTCState.paused);
    playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
    LifecycleTrace.record('gapless transition: index=$index');
    _scheduleSessionSave();
    _schedulePrepareNext();
  }

  void _nextAudio_forward() {
    if (_playlistIndex == null) return;

    if (_playlistIndex! < playlist.value.length - 1) {
      _loadAndPlay(_playlistIndex! + 1, playlist.value);
    }
  }

  void _nextAudio_loop() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! + 1;
    if (newIndex >= playlist.value.length) {
      newIndex = 0;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  void _nextAudio_singleLoop() {
    if (_playlistIndex == null) return;

    _loadAndPlay(_playlistIndex!, playlist.value);
  }

  void _autoNextAudio() {
    switch (playMode.value) {
      case PlayMode.forward:
        _nextAudio_forward();
        break;
      case PlayMode.loop:
        _nextAudio_loop();
        break;
      case PlayMode.singleLoop:
        _nextAudio_singleLoop();
        break;
    }
  }

  /// 手动下一曲时默认循环播放列表
  void nextAudio() => _nextAudio_loop();

  /// 手动上一曲时默认循环播放列表
  void lastAudio() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  /// 暂停
  void pause() {
    try {
      _player.pause();
      _smtc.updateState(state: SMTCState.paused);
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(false);
      });
      _scheduleSessionSave();
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    try {
      _player.start();
      _smtc.updateState(state: SMTCState.playing);
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(true);
      });
    } catch (err) {
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 再次播放。在顺序播放完最后一曲时再次按播放时使用。
  /// 与 [start] 的差别在于它会通知重绘组件
  void playAgain() => _nextAudio_singleLoop();

  void seek(double position) {
    _lastSmtcSecond = null;
    _player.seek(position);
    playService.lyricService.findCurrLyricLine();
    _scheduleSessionSave();
  }

  void _scheduleSessionSave() {
    if (_closing) return;
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await saveSession();
      } catch (error, stack) {
        LOGGER.e('Unable to save playback session: $error', stackTrace: stack);
      }
    });
  }

  Future<void> saveSession() async {
    _sessionSaveTimer?.cancel();
    if (!AppSettings.instance.rememberPlayback) {
      await _sessionStore.clear();
      return;
    }
    if (nowPlaying == null || playlist.value.isEmpty || _playlistIndex == null)
      return;
    await _sessionStore.save(PlaybackSession(
      paths: playlist.value.map((audio) => audio.path).toList(),
      originalPaths: _playlistBackup.map((audio) => audio.path).toList(),
      index: _playlistIndex!,
      position: position.isFinite && position >= 0 ? position : 0,
      shuffle: shuffle.value,
      playMode: playMode.value.name,
      volume: _pref.volumeDsp,
    ));
  }

  Future<void> restoreSession() async {
    if (_restoreAttempted || _closing) return;
    _restoreAttempted = true;
    if (!AppSettings.instance.rememberPlayback) return;
    try {
      final saved = await _sessionStore.read();
      if (saved == null || _closing || nowPlaying != null) return;
      String identity(String value) =>
          path.windows.normalize(value).toLowerCase();
      final available = {
        for (final audio in AudioLibrary.instance.audioCollection)
          identity(audio.path): audio,
      };
      final resolved = saved.resolve<Audio>((value) {
        final audio = available[identity(value)];
        return audio != null && File(audio.path).existsSync() ? audio : null;
      });
      if (resolved == null) return;
      playlist.value = resolved.queue;
      _playlistBackup = resolved.originalQueue;
      shuffle.value = saved.shuffle;
      _pref.volumeDsp = saved.volume;
      setPlayMode(PlayMode.fromString(saved.playMode) ?? PlayMode.forward);
      // Try later tracks if a surviving file has become unreadable.
      for (var offset = 0; offset < resolved.queue.length; offset++) {
        final index = (resolved.index + offset) % resolved.queue.length;
        if (_loadAndPlay(index, resolved.queue,
            autoPlay: false,
            resumePosition: offset == 0 ? resolved.position : 0)) {
          LifecycleTrace.record(
              'session restored paused: index=$index position=$position');
          return;
        }
      }
      nowPlaying = null;
      _playlistIndex = null;
      playlist.value = [];
      notifyListeners();
    } catch (error, stack) {
      LOGGER.e('Unable to restore playback session: $error', stackTrace: stack);
    }
  }

  Future<void> close() async {
    _closing = true;
    _sessionCheckpoint?.cancel();
    _sessionSaveTimer?.cancel();
    playlist.removeListener(_scheduleSessionSave);
    _prepareTimer?.cancel();
    playlist.removeListener(_schedulePrepareNext);
    LoudnessService.instance.removeListener(_applyNormalization);
    await _transitionSub.cancel();
    LifecycleTrace.record('cancel player state');
    await _playerStateStreamSub.cancel();
    LifecycleTrace.record('cancel position');
    await _positionStreamSub.cancel();
    // The FRB async generator cannot finish cancellation until its native
    // event sink is released. Close the producer before awaiting cancellation.
    LifecycleTrace.record('close SMTC');
    await _smtc.close();
    LifecycleTrace.record('SMTC closed');
    await _smtcEventStreamSub.cancel();
    LifecycleTrace.record('free BASS');
    _player.free();
    LifecycleTrace.record('playback closed');
  }
}
