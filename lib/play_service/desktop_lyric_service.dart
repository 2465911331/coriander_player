import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/ipc/lines.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:desktop_lyric/message.dart' as msg;

class DesktopLyricService extends ChangeNotifier {
  final PlayService playService;
  DesktopLyricService(this.playService);
  PlaybackService get _playbackService => playService.playbackService;
  Future<Process?> desktopLyric = Future.value(null);
  StreamSubscription? _messages;
  StreamSubscription? _errors;
  Process? _process;
  bool _starting = false;
  bool isLocked = false;

  Future<void> startDesktopLyric() async {
    if (_starting || _process != null) return;
    _starting = true;
    try {
      final executable = path.join(path.dirname(Platform.resolvedExecutable),
          'desktop_lyric', 'desktop_lyric.exe');
      final audio = _playbackService.nowPlaying;
      final scheme = ThemeProvider.instance.currScheme;
      desktopLyric = Process.start(executable, [
        json.encode(msg.InitArgsMessage(
          _playbackService.playerState == PlayerState.playing,
          audio?.title ?? '无',
          audio?.artist ?? '无',
          audio?.album ?? '无',
          ThemeProvider.instance.themeMode == ThemeMode.dark,
          scheme.primary.value,
          scheme.surfaceContainer.value,
          scheme.onSurface.value,
        ).toJson()),
      ]);
      final process = await desktopLyric;
      if (process == null) return;
      _process = process;
      _errors = process.stderr.transform(utf8.decoder).listen(
            (message) => LOGGER.e('[desktop lyric] $message'),
            onError: (Object error) => LOGGER.e(error),
          );
      _messages = messageLines(process.stdout)
          .listen(_handleMessage, onError: (Object error) => LOGGER.e(error));
      process.stdin.done.catchError((Object error) {
        LOGGER.e('[desktop lyric input] $error');
      });
      process.exitCode.then((_) {
        if (!identical(_process, process)) return;
        _process = null;
        desktopLyric = Future.value(null);
        _messages?.cancel();
        _errors?.cancel();
        isLocked = false;
        notifyListeners();
      });
      notifyListeners();
      if (_playbackService.nowPlaying != null) {
        sendNowPlayingMessage(_playbackService.nowPlaying!);
        sendPlayerStateMessage(
            _playbackService.playerState == PlayerState.playing);
        playService.lyricService.findCurrLyricLine();
      }
    } catch (error, stack) {
      desktopLyric = Future.value(null);
      _process?.kill();
      _process = null;
      LOGGER.e(error, stackTrace: stack);
      showTextOnSnackBar('桌面歌词启动失败，请检查组件是否完整');
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  void _handleMessage(String line) {
    try {
      final decoded = json.decode(line) as Map<String, dynamic>;
      if (decoded['type'] != msg.getMessageTypeName<msg.ControlEventMessage>())
        return;
      final event = msg.ControlEventMessage.fromJson(decoded['message']).event;
      switch (event) {
        case msg.ControlEvent.pause:
          _playbackService.pause();
          break;
        case msg.ControlEvent.start:
          _playbackService.start();
          break;
        case msg.ControlEvent.previousAudio:
          _playbackService.lastAudio();
          break;
        case msg.ControlEvent.nextAudio:
          _playbackService.nextAudio();
          break;
        case msg.ControlEvent.lock:
          isLocked = true;
          notifyListeners();
          break;
        case msg.ControlEvent.close:
          killDesktopLyric();
          break;
      }
    } catch (error, stack) {
      LOGGER.e(error, stackTrace: stack);
    }
  }

  Future<bool> get canSendMessage async => _process != null;

  void sendMessage(msg.Message message) {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(message.buildMessageJson());
    } catch (error, stack) {
      LOGGER.e(error, stackTrace: stack);
    }
  }

  Future<void> killDesktopLyric() async {
    final process = await desktopLyric;
    if (process == null) return;
    _process = null;
    desktopLyric = Future.value(null);
    await _messages?.cancel();
    await _errors?.cancel();
    _messages = null;
    _errors = null;
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
    isLocked = false;
    notifyListeners();
  }

  void clearLyric() =>
      sendMessage(const msg.LyricLineChangedMessage('', Duration.zero));
  void sendUnlockMessage() {
    sendMessage(const msg.UnlockMessage());
    isLocked = false;
    notifyListeners();
  }

  void sendThemeModeMessage(bool darkMode) {
    sendMessage(msg.ThemeModeChangedMessage(darkMode));
  }

  void sendThemeMessage(ColorScheme scheme) {
    sendMessage(msg.ThemeChangedMessage(
      scheme.primary.value,
      scheme.surfaceContainer.value,
      scheme.onSurface.value,
    ));
  }

  void sendPlayerStateMessage(bool isPlaying) {
    sendMessage(msg.PlayerStateChangedMessage(isPlaying));
  }

  void sendNowPlayingMessage(Audio nowPlaying) {
    sendMessage(msg.NowPlayingChangedMessage(
      nowPlaying.title,
      nowPlaying.artist,
      nowPlaying.album,
    ));
  }

  void sendLyricLineMessage(LyricLine line) {
    if (line is SyncLyricLine) {
      sendMessage(msg.LyricLineChangedMessage(
        line.content,
        line.length,
        line.translation,
      ));
    } else if (line is LrcLine) {
      final splitted = line.content.split("┃");
      final content = splitted.first;
      final translation = splitted.length > 1 ? splitted[1] : null;
      sendMessage(msg.LyricLineChangedMessage(
        content,
        line.length,
        translation,
      ));
    }
  }
}
