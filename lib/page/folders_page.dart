import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/library_refresh_button.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:coriander_player/app_paths.dart' as app_paths;

class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AudioLibrary.revision,
        builder: (context, _, __) => _buildContent(context),
      );

  Widget _buildContent(BuildContext context) {
    final contentList = List<AudioFolder>.from(AudioLibrary.instance.folders);
    return UniPage<AudioFolder>(
      useMediaCards: true,
      pref: AppPreference.instance.foldersPagePref,
      title: "文件夹",
      subtitle: "${contentList.length} 个文件夹",
      contentList: contentList,
      primaryAction: const LibraryRefreshButton(),
      contentBuilder: (context, item, i, multiSelectController) =>
          AudioFolderTile(audioFolder: item),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "路径",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.path.localeCompareTo(b.path));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.path.localeCompareTo(a.path));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.edit,
          name: "修改日期",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.modified.compareTo(b.modified));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.modified.compareTo(a.modified));
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

class AudioFolderTile extends StatelessWidget {
  final AudioFolder audioFolder;
  const AudioFolderTile({
    super.key,
    required this.audioFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (LibraryViewScope.cardsOf(context)) {
      return Tooltip(
          message: audioFolder.path,
          child: LibraryMediaCard(
              title: path.basename(audioFolder.path),
              subtitle: '${audioFolder.audios.length} 首歌曲',
              artwork: LibraryArtwork(
                  identity: audioFolder,
                  seed: audioFolder.path,
                  kind: LibraryArtworkKind.folder,
                  load: audioFolder.audios.isEmpty
                      ? null
                      : () => audioFolder.audios.first.mediumCover),
              onTap: () => context.push(app_paths.FOLDER_DETAIL_PAGE,
                  extra: audioFolder),
              playLabel: '播放文件夹',
              onPlay: audioFolder.audios.isEmpty
                  ? null
                  : () => PlayService.instance.playbackService
                      .play(0, List<Audio>.from(audioFolder.audios))));
    }
    return Tooltip(
      message: audioFolder.path,
      child: ListTile(
        title: Text(
          audioFolder.path,
          softWrap: false,
          maxLines: 1,
        ),
        subtitle: Text(
          "修改日期：${DateTime.fromMillisecondsSinceEpoch(audioFolder.modified * 1000).toString()}",
          softWrap: false,
          maxLines: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        onTap: () => context.push(
          app_paths.FOLDER_DETAIL_PAGE,
          extra: audioFolder,
        ),
      ),
    );
  }
}
