import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.album});
  final Album album;
  @override
  Widget build(BuildContext context) {
    void open() => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
    final cards = LibraryViewScope.cardsOf(context);
    final artwork = LibraryArtwork(
        identity: album,
        seed: album.name,
        kind: LibraryArtworkKind.album,
        circular: false,
        load: album.works.isEmpty
            ? null
            : () => cards
                ? album.works.first.mediumCover
                : album.works.first.cover);
    if (cards)
      return LibraryMediaCard(
          title: album.name,
          subtitle: '${album.works.length} 首歌曲',
          artwork: artwork,
          onTap: open,
          playLabel: '播放专辑',
          onPlay: album.works.isEmpty
              ? null
              : () => PlayService.instance.playbackService
                  .play(0, List<Audio>.from(album.works)));
    return LibrarySongRow(
        onTap: open,
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              SizedBox(width: 48, height: 48, child: artwork),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(album.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${album.works.length} 首歌曲',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant))
                  ]))
            ])));
  }
}
