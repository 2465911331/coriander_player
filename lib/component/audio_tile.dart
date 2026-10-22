import 'package:coriander_player/component/song_list_item.dart';
import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 由[playlist]和[audioIndex]确定audio，而不是直接传入audio，
/// 这是为了实现点击列表项播放乐曲时指定该列表为播放列表。
/// 同时，播放乐曲时也是需要index和playlist来定位audio和设置播放列表。
class AudioTile extends StatelessWidget {
  const AudioTile({
    super.key,
    required this.audioIndex,
    required this.playlist,
    this.focus = false,
    this.leading,
    this.action,
    this.multiSelectController,
  });

  final int audioIndex;
  final List<Audio> playlist;
  final bool focus;
  final Widget? leading;
  final Widget? action;
  final MultiSelectController? multiSelectController;

  @override
  Widget build(BuildContext context) {
    final audio = playlist[audioIndex];

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        /// artists
        SubmenuButton(
          menuChildren: List.generate(
            audio.splitedArtists.length,
            (i) => MenuItemButton(
              onPressed: () {
                final Artist artist = AudioLibrary
                    .instance.artistCollection[audio.splitedArtists[i]]!;
                context.push(
                  app_paths.ARTIST_DETAIL_PAGE,
                  extra: artist,
                );
              },
              leadingIcon: const Icon(Symbols.artist),
              child: Text(audio.splitedArtists[i]),
            ),
          ),
          child: const Text("艺术家"),
        ),

        /// album
        MenuItemButton(
          onPressed: () {
            final Album album =
                AudioLibrary.instance.albumCollection[audio.album]!;
            context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
          },
          leadingIcon: const Icon(Symbols.album),
          child: Text(audio.album),
        ),

        /// 下一首播放
        MenuItemButton(
          onPressed: () {
            PlayService.instance.playbackService.addToNext(audio);
          },
          leadingIcon: const Icon(Symbols.plus_one),
          child: const Text("下一首播放"),
        ),

        /// 多选
        if (multiSelectController != null)
          MenuItemButton(
            onPressed: () {
              multiSelectController!.useMultiSelectView(true);
              multiSelectController!.select(audio);
            },
            leadingIcon: const Icon(Symbols.select),
            child: const Text("多选"),
          ),

        /// add to playlist
        SubmenuButton(
          menuChildren: List.generate(
            PLAYLISTS.length,
            (i) => MenuItemButton(
              onPressed: PLAYLISTS[i].isSmart
                  ? null
                  : () {
                      final added = PLAYLISTS[i].audios.containsKey(audio.path);
                      if (added) {
                        showTextOnSnackBar("歌曲“${audio.title}”已存在");
                        return;
                      }

                      PLAYLISTS[i].audios[audio.path] = audio;
                      schedulePlaylistSave();
                      showTextOnSnackBar(
                        "成功将“${audio.title}”添加到歌单“${PLAYLISTS[i].name}”",
                      );
                    },
              leadingIcon: const Icon(Symbols.queue_music),
              child: Text(
                  '${PLAYLISTS[i].name}${PLAYLISTS[i].isSmart ? '（自动匹配）' : ''}'),
            ),
          ),
          child: const Text("添加到歌单"),
        ),

        /// to detail page
        MenuItemButton(
          onPressed: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
          },
          leadingIcon: const Icon(Symbols.info),
          child: const Text("详细信息"),
        ),
      ],
      builder: (context, controller, _) {
        final playback = PlayService.instance.playbackService;
        void activate() {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          if (multiSelectController?.enableMultiSelectView == true) {
            if (multiSelectController!.selected.contains(audio)) {
              multiSelectController!.unselect(audio);
            } else {
              multiSelectController!.select(audio);
            }
          } else {
            playback.play(audioIndex, playlist);
          }
        }

        void secondary(TapDownDetails details) {
          if (multiSelectController?.enableMultiSelectView == true) return;
          controller.open(position: details.localPosition);
        }

        return ListenableBuilder(
            listenable: playback,
            builder: (context, _) => StreamBuilder<PlayerState>(
                stream: playback.playerStateStream,
                initialData: playback.playerState,
                builder: (context, snapshot) {
                  final current = playback.nowPlaying?.path == audio.path;
                  final playing =
                      current && snapshot.data == PlayerState.playing;
                  if (!LibraryViewScope.cardsOf(context)) {
                    return SongListItem(
                        title: audio.title,
                        subtitle: '${audio.artist} · ${audio.album}',
                        duration:
                            Duration(seconds: audio.duration).toStringHMMSS(),
                        artwork: LibraryArtwork(
                            identity: audio,
                            seed: audio.album,
                            load: () => audio.cover),
                        current: current,
                        playing: playing,
                        located: focus,
                        leading: leading,
                        action: action,
                        selected:
                            multiSelectController?.selected.contains(audio) ==
                                true,
                        selecting:
                            multiSelectController?.enableMultiSelectView ==
                                true,
                        onTap: activate,
                        onSecondaryTapDown: secondary);
                  }
                  return LibraryMediaCard(
                      title: audio.title,
                      subtitle:
                          '${audio.artist} · ${Duration(seconds: audio.duration).toStringHMMSS()}',
                      artwork: LibraryArtwork(
                          identity: audio,
                          seed: audio.album,
                          load: () => audio.mediumCover),
                      current: current,
                      playing: playing,
                      badge: current ? (playing ? '正在播放' : '已暂停') : null,
                      selected:
                          multiSelectController?.selected.contains(audio) ==
                              true,
                      selecting:
                          multiSelectController?.enableMultiSelectView == true,
                      onTap: activate,
                      onSecondaryTapDown: secondary,
                      onPlay: () {
                        if (!current) {
                          playback.play(audioIndex, playlist);
                        } else if (playing) {
                          playback.pause();
                        } else if (playback.length > 0 &&
                            playback.position >= playback.length - .01) {
                          playback.playAgain();
                        } else {
                          playback.start();
                        }
                      });
                }));
      },
    );
  }
}
