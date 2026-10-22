import 'package:coriander_player/app_design.dart';
import 'package:coriander_player/component/player_artwork_hero.dart';
import 'package:coriander_player/component/playback_queue_panel.dart';
import 'package:coriander_player/component/audio_spectrum.dart';
import 'package:coriander_player/play_service/waveform_model.dart';
import 'package:coriander_player/play_service/waveform_service.dart';
// ignore_for_file: camel_case_types

import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/playback_visuals.dart';
import 'package:coriander_player/component/cover_backdrop.dart';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/responsive_builder.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/page/now_playing_page/component/filled_icon_button_style.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

part 'small_page.dart';
part 'large_page.dart';

enum NowPlayingViewMode {
  onlyMain,
  withLyric,
  withPlaylist;

  static NowPlayingViewMode? fromString(String nowPlayingViewMode) {
    for (var value in NowPlayingViewMode.values) {
      if (value.name == nowPlayingViewMode) return value;
    }
    return null;
  }
}

final NOW_PLAYING_VIEW_MODE = ValueNotifier(
  AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode,
);

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final playbackService = PlayService.instance.playbackService;
  ImageProvider<Object>? nowPlayingCover;
  String? _coverTrack;
  int _coverGeneration = 0;
  bool _coverInitialized = false;

  void updateCover() {
    final audio = playbackService.nowPlaying;
    if (_coverInitialized && _coverTrack == audio?.path) return;
    _coverInitialized = true;
    _coverTrack = audio?.path;
    final generation = ++_coverGeneration;
    setState(() => nowPlayingCover = null);
    if (audio == null) return;
    audio.largeCover.then((cover) {
      if (mounted && generation == _coverGeneration) {
        setState(() => nowPlayingCover = cover);
      }
    }).catchError((Object error) {
      // A broken cover must not keep the previous song's artwork.
      if (mounted && generation == _coverGeneration) {
        setState(() => nowPlayingCover = null);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    playbackService.addListener(updateCover);
    updateCover();
  }

  @override
  void dispose() {
    playbackService.removeListener(updateCover);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppSettings.instance.appearance;
    return AppearanceScope(
      preferences: preferences,
      child: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => ValueListenableBuilder<bool>(
          valueListenable: VisualActivity.instance,
          builder: (context, visible, _) => TickerMode(
            enabled:
                TickerMode.of(context) && (!preferences.savePower || visible),
            child: Builder(builder: (context) {
              final animate = allowVisualMotion(context, preferences);
              return Scaffold(
                appBar: const PreferredSize(
                    preferredSize: Size.fromHeight(56),
                    child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Row(children: [
                          NavBackBtn(),
                          Expanded(
                              child: DragToMoveArea(child: SizedBox.expand())),
                          WindowControlls()
                        ]))),
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                body: Stack(fit: StackFit.expand, children: [
                  CoverBackdrop(
                      cover: nowPlayingCover,
                      trackKey: _coverTrack,
                      enabled: preferences.coverBackground,
                      animate: animate,
                      blur: preferences.backgroundBlur,
                      strength: preferences.backgroundStrength),
                  _ArtworkData(
                      cover: nowPlayingCover,
                      trackKey: _coverTrack,
                      child: ChangeNotifierProvider.value(
                          value: playbackService,
                          builder: (context, _) => ResponsiveBuilder2(
                              builder: (context, screenType) =>
                                  screenType == ScreenType.small
                                      ? const _NowPlayingPage_Small()
                                      : const _NowPlayingPage_Large()))),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ArtworkData extends InheritedWidget {
  const _ArtworkData(
      {required this.cover, required this.trackKey, required super.child});
  final ImageProvider? cover;
  final String? trackKey;
  @override
  bool updateShouldNotify(_ArtworkData oldWidget) =>
      cover != oldWidget.cover || trackKey != oldWidget.trackKey;
}

class _ExclusiveModeSwitch extends StatelessWidget {
  const _ExclusiveModeSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: PlayService.instance.playbackService.wasapiExclusive,
      builder: (context, exclusive, _) => IconButton(
        tooltip: "独占模式；现在：${exclusive ? "启用" : "禁用"}",
        onPressed: () {
          PlayService.instance.playbackService.useExclusiveMode(!exclusive);
        },
        icon: Center(
          child: Text(
            exclusive ? "Excl" : "Shrd",
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingMoreAction extends StatelessWidget {
  const _NowPlayingMoreAction();

  @override
  Widget build(BuildContext context) {
    final playbackService = context.watch<PlaybackService>();
    final nowPlaying = playbackService.nowPlaying;
    final scheme = Theme.of(context).colorScheme;

    if (nowPlaying == null) {
      return IconButton(
        tooltip: "更多",
        onPressed: null,
        icon: const Icon(Symbols.more_vert),
        color: scheme.onSecondaryContainer,
      );
    }

    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          menuChildren: List.generate(
            nowPlaying.splitedArtists.length,
            (i) => MenuItemButton(
              onPressed: () {
                final Artist artist = AudioLibrary
                    .instance.artistCollection[nowPlaying.splitedArtists[i]]!;
                context.pushReplacement(
                  app_paths.ARTIST_DETAIL_PAGE,
                  extra: artist,
                );
              },
              leadingIcon: const Icon(Symbols.people),
              child: Text(nowPlaying.splitedArtists[i]),
            ),
          ),
          child: const Text("艺术家"),
        ),
        MenuItemButton(
          onPressed: () {
            final Album album =
                AudioLibrary.instance.albumCollection[nowPlaying.album]!;
            context.pushReplacement(app_paths.ALBUM_DETAIL_PAGE, extra: album);
          },
          leadingIcon: const Icon(Symbols.album),
          child: Text(nowPlaying.album),
        ),
        MenuItemButton(
          onPressed: () {
            context.pushReplacement(app_paths.AUDIO_DETAIL_PAGE,
                extra: nowPlaying);
          },
          leadingIcon: const Icon(Symbols.info),
          child: const Text("详细信息"),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: "更多",
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Symbols.more_vert),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _DesktopLyricSwitch extends StatelessWidget {
  const _DesktopLyricSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: PlayService.instance.desktopLyricService,
      builder: (context, _) {
        final desktopLyricService = PlayService.instance.desktopLyricService;
        return FutureBuilder(
          future: desktopLyricService.desktopLyric,
          builder: (context, snapshot) => IconButton(
            tooltip: "桌面歌词；现在：${snapshot.data == null ? "禁用" : "启用"}",
            onPressed: snapshot.data == null
                ? desktopLyricService.startDesktopLyric
                : desktopLyricService.isLocked
                    ? desktopLyricService.sendUnlockMessage
                    : desktopLyricService.killDesktopLyric,
            icon: snapshot.connectionState == ConnectionState.done
                ? Icon(
                    desktopLyricService.isLocked ? Symbols.lock : Symbols.toast,
                    fill: snapshot.data == null ? 0 : 1,
                  )
                : const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  ),
            color: scheme.onSecondaryContainer,
          ),
        );
      },
    );
  }
}

class _NowPlayingVolDspSlider extends StatefulWidget {
  const _NowPlayingVolDspSlider();

  @override
  State<_NowPlayingVolDspSlider> createState() =>
      _NowPlayingVolDspSliderState();
}

class _NowPlayingVolDspSliderState extends State<_NowPlayingVolDspSlider> {
  final playbackService = PlayService.instance.playbackService;
  final dragVolDsp = ValueNotifier(
    AppPreference.instance.playbackPref.volumeDsp,
  );
  bool isDragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      menuChildren: [
        SliderTheme(
          data: const SliderThemeData(
            showValueIndicator: ShowValueIndicator.always,
          ),
          child: ValueListenableBuilder(
            valueListenable: dragVolDsp,
            builder: (context, dragVolDspValue, _) => Slider(
              thumbColor: scheme.primary,
              activeColor: scheme.primary,
              inactiveColor: scheme.outline,
              min: 0.0,
              max: 1.0,
              value: isDragging ? dragVolDspValue : playbackService.volumeDsp,
              label: "${(dragVolDspValue * 100).toInt()}",
              onChangeStart: (value) {
                isDragging = true;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChanged: (value) {
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
              onChangeEnd: (value) {
                isDragging = false;
                dragVolDsp.value = value;
                playbackService.setVolumeDsp(value);
              },
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: "音量",
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: const Icon(Symbols.volume_up),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _NowPlayingPlayModeSwitch extends StatelessWidget {
  const _NowPlayingPlayModeSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder(
      valueListenable: playbackService.playMode,
      builder: (context, playMode, _) {
        late IconData result;
        if (playMode == PlayMode.forward) {
          result = Symbols.repeat;
        } else if (playMode == PlayMode.loop) {
          result = Symbols.repeat_on;
        } else {
          result = Symbols.repeat_one_on;
        }

        return IconButton(
          tooltip: "播放模式；现在：${switch (playMode) {
            PlayMode.forward => "顺序播放",
            PlayMode.loop => "列表循环",
            PlayMode.singleLoop => "单曲循环",
          }}",
          onPressed: () {
            if (playMode == PlayMode.forward) {
              playbackService.setPlayMode(PlayMode.loop);
            } else if (playMode == PlayMode.loop) {
              playbackService.setPlayMode(PlayMode.singleLoop);
            } else {
              playbackService.setPlayMode(PlayMode.forward);
            }
          },
          icon: Icon(result),
          color: scheme.onSecondaryContainer,
        );
      },
    );
  }
}

class _NowPlayingShuffleSwitch extends StatelessWidget {
  const _NowPlayingShuffleSwitch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    return ValueListenableBuilder(
      valueListenable: playbackService.shuffle,
      builder: (context, shuffle, _) => IconButton(
        tooltip: "随机；现在：${shuffle ? "启用" : "禁用"}",
        onPressed: () {
          playbackService.useShuffle(!shuffle);
        },
        icon: Icon(shuffle ? Symbols.shuffle_on : Symbols.shuffle),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

/// previous audio, pause/resume, next audio
class _NowPlayingMainControls extends StatelessWidget {
  const _NowPlayingMainControls();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playbackService = PlayService.instance.playbackService;

    final preferences = AppearanceScope.of(context);
    final animate =
        preferences.animateControls && allowVisualMotion(context, preferences);
    Widget button(String tooltip, IconData icon, VoidCallback action) =>
        PlaybackPressFeedback(
            animate: animate,
            child: IconButton(
                tooltip: tooltip,
                onPressed: action,
                icon: Icon(icon),
                style: LargeFilledIconButtonStyle(
                    primary: false, scheme: scheme)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button('上一曲', Symbols.skip_previous, playbackService.lastAudio),
      const SizedBox(width: 16),
      StreamBuilder(
          stream: playbackService.playerStateStream,
          initialData: playbackService.playerState,
          builder: (context, snapshot) {
            final playing = snapshot.data == PlayerState.playing;
            return PlaybackPressFeedback(
                animate: animate,
                child: IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    onPressed: playing
                        ? playbackService.pause
                        : snapshot.data == PlayerState.completed
                            ? playbackService.playAgain
                            : playbackService.start,
                    icon: AnimatedPlaybackIcon(
                        playing: playing, animate: animate),
                    style: LargeFilledIconButtonStyle(
                        primary: true, scheme: scheme)));
          }),
      const SizedBox(width: 16),
      button('下一曲', Symbols.skip_next, playbackService.nextAudio),
    ]);
  }
}

/// Native seeking behavior with a decorative wave track.
class _NowPlayingSlider extends StatefulWidget {
  const _NowPlayingSlider();
  @override
  State<_NowPlayingSlider> createState() => _NowPlayingSliderState();
}

class _NowPlayingSliderState extends State<_NowPlayingSlider> {
  double? _dragPosition;
  String? _track;
  Audio? _waveAudio;
  Future<WaveformData?>? _waveform;
  String _time(double value) =>
      Duration(milliseconds: (value * 1000).round()).toStringHMMSS();
  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackService>();
    final preferences = AppearanceScope.of(context);
    final length =
        playback.length.isFinite && playback.length > 0 ? playback.length : 0.0;
    if (_track != playback.nowPlaying?.path) {
      _track = playback.nowPlaying?.path;
      _dragPosition = null;
    }
    final useWaveform = preferences.progress == ProgressStyle.waveform;
    final audio = playback.nowPlaying;
    if (useWaveform &&
        audio != null &&
        (!identical(_waveAudio, audio) || _waveform == null)) {
      _waveAudio = audio;
      _waveform = WaveformService.instance.load(audio.path);
    }
    return FutureBuilder<WaveformData?>(
        future: useWaveform ? _waveform : null,
        builder: (context, waveform) => StreamBuilder(
            stream: playback.playerStateStream,
            initialData: playback.playerState,
            builder: (context, state) => StreamBuilder(
                stream: playback.positionStream,
                initialData: playback.position,
                builder: (context, snapshot) {
                  final raw = _dragPosition ?? snapshot.data ?? 0.0;
                  final position = raw.isFinite ? raw.clamp(0.0, length) : 0.0;
                  return Column(children: [
                    if (preferences.spectrum == SpectrumStyle.bars)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                          child: SizedBox(
                              height: 28,
                              child: _NowPlayingSpectrum(
                                  playing: state.data == PlayerState.playing))),
                    WaveSeekBar(
                        value: position,
                        duration: length,
                        label: _time(position),
                        waveform: useWaveform &&
                                waveform.connectionState == ConnectionState.done
                            ? waveform.data?.peaks
                            : null,
                        playing: state.data == PlayerState.playing,
                        wave: preferences.progress == ProgressStyle.wave,
                        animate: allowVisualMotion(context, preferences),
                        amplitude: preferences.waveAmplitude,
                        gentle: preferences.motion == MotionLevel.gentle,
                        onChangeStart: (value) =>
                            setState(() => _dragPosition = value),
                        onChanged: (value) =>
                            setState(() => _dragPosition = value),
                        onChangeEnd: (value) {
                          playback.seek(value);
                          setState(() => _dragPosition = null);
                        }),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_time(position)),
                              if (useWaveform && audio != null)
                                Expanded(
                                    child: Center(
                                        child: waveform.connectionState ==
                                                ConnectionState.waiting
                                            ? const Text('正在后台分析波形…',
                                                style: TextStyle(fontSize: 12))
                                            : waveform.data != null
                                                ? const Tooltip(
                                                    message:
                                                        '整首歌曲的真实波形，分析结果已缓存',
                                                    child: Text('整曲波形',
                                                        style: TextStyle(
                                                            fontSize: 12)))
                                                : TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                        minimumSize: Size.zero,
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8)),
                                                    onPressed: () => setState(() => _waveform =
                                                        WaveformService.instance
                                                            .load(audio.path)),
                                                    icon: const Icon(Icons.refresh,
                                                        size: 14),
                                                    label: const Text('重试波形',
                                                        style: TextStyle(fontSize: 12))))),
                              Text(_time(length)),
                            ])),
                  ]);
                })));
  }
}

class _NowPlayingSpectrum extends StatelessWidget {
  const _NowPlayingSpectrum({required this.playing, this.ring = false});
  final bool playing, ring;
  @override
  Widget build(BuildContext context) {
    final preferences = AppearanceScope.of(context);
    final playback = PlayService.instance.playbackService;
    return AudioSpectrum(
        readSpectrum: playback.readSpectrum,
        playing: playing,
        trackKey: playback.nowPlaying?.path,
        ring: ring,
        animate: allowVisualMotion(context, preferences),
        gentle: preferences.motion == MotionLevel.gentle);
  }
}

class _NowPlayingInfo extends StatelessWidget {
  const _NowPlayingInfo();
  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackService>();
    final nowPlaying = playback.nowPlaying;
    final preferences = AppearanceScope.of(context);
    final artwork = context.dependOnInheritedWidgetOfExactType<_ArtworkData>()!;
    final animate = allowVisualMotion(context, preferences);
    final vinyl = preferences.artwork == ArtworkStyle.vinyl;
    final placeholder = ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: const Center(child: Icon(Icons.music_note_rounded, size: 64)));
    return Center(
        child: SizedBox(
            width: 440,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(children: [
                  Expanded(
                      child: PlayerArtworkHero(
                          cover: artwork.cover,
                          child: AnimatedSwitcher(
                              duration:
                                  animate ? AppMotion.artwork : Duration.zero,
                              child: StreamBuilder(
                                  stream: playback.playerStateStream,
                                  initialData: playback.playerState,
                                  key: ValueKey(
                                      '${artwork.trackKey}-${preferences.artwork.name}'),
                                  builder: (context, snapshot) {
                                    final playing =
                                        snapshot.data == PlayerState.playing;
                                    final ring = preferences.spectrum ==
                                        SpectrumStyle.ring;
                                    Widget image = vinyl
                                        ? VinylArtwork(
                                            cover: artwork.cover,
                                            playing: playing,
                                            animate: animate,
                                            secondsPerTurn:
                                                preferences.rotationSeconds)
                                        : Center(
                                            child: AspectRatio(
                                                aspectRatio: 1,
                                                child: RepaintBoundary(
                                                    child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                16),
                                                        child: artwork.cover ==
                                                                null
                                                            ? placeholder
                                                            : Image(
                                                                image: artwork
                                                                    .cover!,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder: (_,
                                                                        __,
                                                                        ___) =>
                                                                    placeholder)))));
                                    if (ring) {
                                      image = LayoutBuilder(
                                          builder: (context, constraints) =>
                                              Center(
                                                  child: AspectRatio(
                                                      aspectRatio: 1,
                                                      child: Stack(
                                                          fit: StackFit.expand,
                                                          children: [
                                                            Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        18),
                                                                child: vinyl
                                                                    ? VinylArtwork(
                                                                        cover: artwork
                                                                            .cover,
                                                                        playing:
                                                                            playing,
                                                                        animate:
                                                                            animate,
                                                                        secondsPerTurn:
                                                                            preferences
                                                                                .rotationSeconds)
                                                                    : ClipOval(
                                                                        child: artwork.cover ==
                                                                                null
                                                                            ? placeholder
                                                                            : Image(
                                                                                image: artwork.cover!,
                                                                                fit: BoxFit.cover,
                                                                                errorBuilder: (_, __, ___) => placeholder))),
                                                            _NowPlayingSpectrum(
                                                                playing:
                                                                    playing,
                                                                ring: true),
                                                          ]))));
                                    }
                                    return image;
                                  })))),
                  const SizedBox(height: 16),
                  Text(nowPlaying?.title ?? 'Coriander Music',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                      nowPlaying == null
                          ? 'Enjoy Music'
                          : '${nowPlaying.artist} · ${nowPlaying.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                ]))));
  }
}
