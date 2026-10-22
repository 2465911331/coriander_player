import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/utils.dart';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/playlist_editor_dialog.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  void newPlaylist(BuildContext context, {bool smart = false}) async {
    final created = await showDialog<Playlist>(
      context: context,
      builder: (context) => PlaylistEditorDialog(smart: smart),
    );
    if (created == null || !mounted) return;
    setState(() {
      PLAYLISTS.add(created);
      schedulePlaylistSave();
    });
  }

  void editPlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final edited = await showDialog<Playlist>(
      context: context,
      builder: (context) => PlaylistEditorDialog(initial: playlist),
    );
    if (edited == null || !mounted) return;
    setState(() {
      playlist.name = edited.name;
      playlist.smartRule = edited.smartRule;
      schedulePlaylistSave();
    });
  }

  void deletePlaylist(BuildContext context, Playlist item) {
    final index = PLAYLISTS.indexOf(item);
    if (index < 0) return;
    setState(() => PLAYLISTS.remove(item));
    schedulePlaylistSave();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('已删除歌单“${item.name}”，音乐文件保留'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                if (PLAYLISTS.contains(item)) return;
                PLAYLISTS.insert(index.clamp(0, PLAYLISTS.length), item);
                if (mounted) setState(() {});
                schedulePlaylistSave();
              })));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: AudioLibrary.revision,
        builder: (context, _, __) => _buildContent(context));
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return UniPage<Playlist>(
      useMediaCards: true,
      pref: AppPreference.instance.playlistsPagePref,
      title: "歌单",
      subtitle: "${PLAYLISTS.length} 个歌单",
      contentList: PLAYLISTS,
      contentBuilder: (context, item, i, multiSelectController) =>
          LibraryViewScope.cardsOf(context)
              ? LibraryMediaCard(
                  title: item.name,
                  subtitle: '${item.audios.length} 首乐曲',
                  badge: item.isSmart ? '智能歌单' : null,
                  artwork: _PlaylistArtwork(playlist: item),
                  onTap: () =>
                      context.push(app_paths.PLAYLIST_DETAIL_PAGE, extra: item),
                  playLabel: '播放歌单',
                  onPlay: item.audios.isEmpty
                      ? null
                      : () => PlayService.instance.playbackService
                          .play(0, item.audios.values.toList()),
                  menu: PopupMenuButton<String>(
                      tooltip: '更多',
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onSelected: (value) {
                        if (value == 'edit') {
                          editPlaylist(context, item);
                        } else {
                          deletePlaylist(context, item);
                        }
                      },
                      itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除'))
                          ]))
              : ListTile(
                  title: Text(
                    item.name,
                    softWrap: false,
                    maxLines: 1,
                  ),
                  subtitle: Text(
                    "${item.isSmart ? '智能歌单 · ' : ''}${item.audios.length} 首乐曲",
                    softWrap: false,
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: "编辑",
                        onPressed: () => editPlaylist(context, item),
                        icon: const Icon(Symbols.edit),
                      ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        tooltip: "删除",
                        onPressed: () => deletePlaylist(context, item),
                        color: scheme.error,
                        icon: const Icon(Symbols.delete),
                      ),
                    ],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  onTap: () => context.push(
                    app_paths.PLAYLIST_DETAIL_PAGE,
                    extra: item,
                  ),
                ),
      primaryAction: MenuAnchor(
          menuChildren: [
            MenuItemButton(
                onPressed: () => newPlaylist(context),
                child: const Text('普通歌单')),
            MenuItemButton(
                onPressed: () => newPlaylist(context, smart: true),
                child: const Text('智能歌单')),
          ],
          builder: (context, controller, _) => FilledButton.icon(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Symbols.add),
                label: const Text("新建歌单"),
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 40)),
                ),
              )),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "名称",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.name.localeCompareTo(b.name));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.name.localeCompareTo(a.name));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: "歌曲数量",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.audios.length.compareTo(b.audios.length));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.audios.length.compareTo(a.audios.length));
                break;
            }
          },
        ),
      ],
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist});
  final Playlist playlist;
  @override
  Widget build(BuildContext context) {
    final audios = playlist.audios.values.take(4).toList();
    Widget cover(Audio audio) => LibraryArtwork(
        identity: audio,
        seed: audio.album,
        kind: LibraryArtworkKind.playlist,
        load: () => audio.mediumCover);
    if (audios.isEmpty)
      return LibraryArtwork(
          identity: playlist,
          seed: playlist.name,
          kind: LibraryArtworkKind.playlist);
    if (audios.length < 4) return cover(audios.first);
    return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(children: [
          for (var row = 0; row < 2; row++)
            Expanded(
                child: Row(children: [
              for (var col = 0; col < 2; col++)
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: cover(audios[row * 2 + col])))
            ]))
        ]));
  }
}
