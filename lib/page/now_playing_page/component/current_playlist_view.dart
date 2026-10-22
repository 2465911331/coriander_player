import 'package:flutter/material.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/app_design.dart';
import 'package:coriander_player/component/song_list_item.dart';
import 'package:coriander_player/component/library_card.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView({super.key, this.showHeader = true});
  final bool showHeader;
  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  final playback = PlayService.instance.playbackService;
  final controller = ScrollController();
  void reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final offset = (playback.playlistIndex * AppDesign.songExtent(context))
          .clamp(0.0, controller.position.maxScrollExtent);
      if (AppMotion.enabled(context)) {
        controller.animateTo(offset,
            duration: AppMotion.page, curve: AppMotion.curve);
      } else {
        controller.jumpTo(offset);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    playback.addListener(reveal);
    reveal();
  }

  @override
  void dispose() {
    playback.removeListener(reveal);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
          listenable: Listenable.merge([playback, playback.playlist]),
          builder: (context, _) => StreamBuilder<PlayerState>(
              stream: playback.playerStateStream,
              initialData: playback.playerState,
              builder: (context, snapshot) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showHeader)
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                  '播放队列 · ${playback.playlist.value.length}',
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                        Expanded(
                            child: playback.playlist.value.isEmpty
                                ? const Center(child: Text('队列还是空的，先选择一首歌曲'))
                                : ListView.builder(
                                    key: const PageStorageKey('playback-queue'),
                                    controller: controller,
                                    padding: const EdgeInsets.all(8),
                                    itemExtent: AppDesign.songExtent(context),
                                    itemCount: playback.playlist.value.length,
                                    itemBuilder: (context, index) {
                                      final audio =
                                          playback.playlist.value[index];
                                      final current =
                                          playback.playlistIndex == index;
                                      return SongListItem(
                                          title: audio.title,
                                          subtitle: audio.artist,
                                          artwork: LibraryArtwork(
                                              identity: audio,
                                              seed: audio.album,
                                              load: () => audio.cover),
                                          current: current,
                                          playing: current &&
                                              snapshot.data ==
                                                  PlayerState.playing,
                                          onTap: () => playback
                                              .playIndexOfPlaylist(index));
                                    })),
                      ]))));
}
