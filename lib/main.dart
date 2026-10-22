import 'package:coriander_player/play_service/waveform_service.dart';
import 'package:coriander_player/appearance.dart';
import 'dart:io';
import 'package:coriander_player/lifecycle_trace.dart';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/entry.dart';
import 'package:coriander_player/component/close_confirmation_dialog.dart';
import 'package:coriander_player/window_behavior.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/loudness_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/src/rust/api/logger.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/tray_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initWindow() async {
  await windowManager.ensureInitialized();
  VisualActivity.instance.attach();
  await TrayService(
    closeBehavior: () => AppSettings.instance.closeBehavior,
    confirmClose: () async {
      final context = ROUTER_KEY.currentContext;
      if (context == null || !context.mounted) return null;
      return showDialog<CloseBehavior>(
        context: context,
        builder: (_) => const CloseConfirmationDialog(),
      );
    },
    onTogglePlayback: () {
      final player = PlayService.instance.playbackService;
      if (player.nowPlaying == null) return;
      if (player.playerState == PlayerState.playing) {
        player.pause();
      } else {
        player.start();
      }
    },
    onPrevious: () => PlayService.instance.playbackService.lastAudio(),
    onNext: () => PlayService.instance.playbackService.nextAudio(),
    onHide: () async {
      await AppSettings.instance.saveSettings();
      await PlayService.savePlaybackIfInitialized();
    },
    onExit: () async {
      LifecycleTrace.record('save playback session');
      await PlayService.savePlaybackIfInitialized();
      LifecycleTrace.record('save playlists');
      await savePlaylists();
      LifecycleTrace.record('save lyric sources');
      await saveLyricSources();
      LifecycleTrace.record('save settings');
      await AppSettings.instance.saveSettings();
      LifecycleTrace.record('save preferences');
      await AppPreference.instance.save();
      LifecycleTrace.record('unregister hotkeys');
      await HotkeysHelper.unregisterAll();
      LifecycleTrace.record('close playback services');
      await Future.wait(
          [WaveformService.instance.close(), LoudnessService.instance.close()]);
      await PlayService.closeIfInitialized();
      LifecycleTrace.record('playback services closed');
    },
  ).init();
  WindowOptions windowOptions = WindowOptions(
    minimumSize: const Size(507, 507),
    size: AppSettings.instance.windowSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> loadPrefFont() async {
  final settings = AppSettings.instance;
  if (settings.fontFamily != null) {
    try {
      final fontLoader = FontLoader(settings.fontFamily!);

      fontLoader.addFont(
        File(settings.fontPath!).readAsBytes().then((value) {
          return ByteData.sublistView(value);
        }),
      );
      await fontLoader.load();
      ThemeProvider.instance.changeFontFamily(settings.fontFamily!);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RustLib.init();

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  // For hot reload, `unregisterAll()` needs to be called.
  await HotkeysHelper.unregisterAll();
  HotkeysHelper.registerHotKeys();

  await migrateAppData();

  final supportPath = (await getAppDataDir()).path;
  LifecycleTrace.initialize(supportPath);
  if (File("$supportPath\\settings.json").existsSync()) {
    await AppSettings.readFromJson();
    await loadPrefFont();
  }
  if (File("$supportPath\\app_preference.json").existsSync()) {
    await AppPreference.read();
  }
  final welcome = !File("$supportPath\\index.json").existsSync();

  await Future.wait([readPlaylists(), readLyricSources()]);
  await LoudnessService.instance.init();
  await initWindow();

  runApp(Entry(welcome: welcome));
}
