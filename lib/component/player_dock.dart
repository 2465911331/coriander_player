import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app_paths.dart' as paths;
import '../appearance.dart';
import '../app_settings.dart';
import '../play_service/play_service.dart';
import '../src/bass/bass_player.dart';
import 'library_card.dart';
import 'playback_visuals.dart';
import 'player_artwork_hero.dart';
import 'playback_queue_panel.dart';

/// Pure presentation separated from the native player for layout/input testing.
class PlayerDock extends StatelessWidget {
  const PlayerDock(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.artwork,
      required this.playing,
      required this.onOpen,
      required this.onPlay,
      required this.onPrevious,
      required this.onNext,
      required this.onQueue,
      this.animate = true,
      this.progress});
  final String title, subtitle;
  final Widget artwork;
  final bool playing, animate;
  final VoidCallback onOpen, onQueue;
  final VoidCallback? onPlay, onPrevious, onNext;
  final Widget? progress;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Material(
                    color: scheme.surfaceContainerHigh,
                    elevation: 2,
                    shadowColor: scheme.shadow,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                                child: InkWell(
                                    onTap: onOpen,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Row(children: [
                                          SizedBox(
                                              width: 52,
                                              height: 52,
                                              child: artwork),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.titleMedium),
                                                Text(subtitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall)
                                              ])),
                                        ])))),
                            IconButton(
                                tooltip: '上一首',
                                onPressed: onPrevious,
                                icon: const Icon(Icons.skip_previous_rounded)),
                            PlaybackPressFeedback(
                                animate: animate,
                                child: IconButton.filled(
                                    tooltip: playing ? '暂停' : '播放',
                                    onPressed: onPlay,
                                    icon: AnimatedPlaybackIcon(
                                        playing: playing, animate: animate))),
                            IconButton(
                                tooltip: '下一首',
                                onPressed: onNext,
                                icon: const Icon(Icons.skip_next_rounded)),
                            IconButton(
                                tooltip: '播放队列',
                                onPressed: onQueue,
                                icon: const Icon(Icons.queue_music_rounded)),
                          ])),
                      if (progress != null) progress!,
                    ])))));
  }
}

class MiniNowPlaying extends StatelessWidget {
  const MiniNowPlaying({super.key});
  @override
  Widget build(BuildContext context) {
    final playback = PlayService.instance.playbackService;
    return ListenableBuilder(
        listenable: playback,
        builder: (context, _) => StreamBuilder<PlayerState>(
            stream: playback.playerStateStream,
            initialData: playback.playerState,
            builder: (context, snapshot) {
              final audio = playback.nowPlaying;
              final playing = snapshot.data == PlayerState.playing;
              final preferences = AppSettings.instance.appearance;
              return ListenableBuilder(
                  listenable: preferences,
                  builder: (context, _) => PlayerDock(
                        title: audio?.title ?? '选择一首歌曲',
                        subtitle: audio == null
                            ? '开始聆听你的本地音乐'
                            : '${audio.artist} · ${audio.album}',
                        playing: playing,
                        animate: preferences.animateControls &&
                            allowVisualMotion(context, preferences),
                        artwork: FutureBuilder<ImageProvider?>(
                            future: audio?.mediumCover,
                            builder: (context, image) => PlayerArtworkHero(
                                cover: image.connectionState ==
                                        ConnectionState.done
                                    ? image.data
                                    : null,
                                child: LibraryArtwork(
                                    identity: audio ?? 'empty-player',
                                    seed: audio?.album ?? '音乐',
                                    load: audio == null
                                        ? null
                                        : () => audio.mediumCover))),
                        onOpen: () => context.push(paths.NOW_PLAYING_PAGE),
                        onPlay: audio == null
                            ? null
                            : () {
                                if (playing) {
                                  playback.pause();
                                } else if (playback.length > 0 &&
                                    playback.position >=
                                        playback.length - .01) {
                                  playback.playAgain();
                                } else {
                                  playback.start();
                                }
                              },
                        onPrevious: audio == null ? null : playback.lastAudio,
                        onNext: audio == null ? null : playback.nextAudio,
                        onQueue: () => AppPanels.toggleQueue(context),
                        progress: StreamBuilder<double>(
                            stream: playback.positionStream,
                            initialData: playback.position,
                            builder: (context, progress) => ExcludeSemantics(
                                child: LinearProgressIndicator(
                                    minHeight: 3,
                                    value: playback.length > 0
                                        ? ((progress.data ?? 0) /
                                                playback.length)
                                            .clamp(0.0, 1.0)
                                        : 0,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest))),
                      ));
            }));
  }
}
