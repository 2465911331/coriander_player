import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class ArtistTile extends StatelessWidget {
  const ArtistTile({super.key, required this.artist});
  final Artist artist;
  @override
  Widget build(BuildContext context) {
    void open() => context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist);
    final cards = LibraryViewScope.cardsOf(context);
    final artwork = LibraryArtwork(
        identity: artist,
        seed: artist.name,
        kind: LibraryArtworkKind.artist,
        circular: true,
        load: artist.works.isEmpty
            ? null
            : () => cards
                ? artist.works.first.mediumCover
                : artist.works.first.cover);
    if (cards)
      return LibraryMediaCard(
          title: artist.name,
          subtitle: '${artist.works.length} 首歌曲',
          artwork: artwork,
          onTap: open,
          playLabel: '播放艺术家的歌曲',
          onPlay: artist.works.isEmpty
              ? null
              : () => PlayService.instance.playbackService
                  .play(0, List<Audio>.from(artist.works)));
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
                    Text(artist.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${artist.works.length} 首歌曲',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant))
                  ]))
            ])));
  }
}
