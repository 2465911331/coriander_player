import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_design.dart';
import '../play_service/play_service.dart';
import '../page/now_playing_page/component/current_playlist_view.dart';

abstract final class AppPanels {
  static final queue = ValueNotifier(false);
  static const queueBreakpoint = 1120.0;
  static void toggleQueue(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= queueBreakpoint) {
      queue.value = !queue.value;
      return;
    }
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        sheetAnimationStyle: AnimationStyle(
            duration: AppMotion.duration(context),
            reverseDuration: AppMotion.duration(context)),
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (context) => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(context).pop(),
                },
                child: Focus(
                    autofocus: true,
                    child: SizedBox(
                        height: math.min(
                            640, MediaQuery.sizeOf(context).height * .75),
                        child: PlaybackQueuePanel(
                            onClose: () => Navigator.of(context).pop())))));
  }
}

class PlaybackQueuePanel extends StatelessWidget {
  const PlaybackQueuePanel({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(children: [
              Expanded(
                  child: ValueListenableBuilder(
                      valueListenable:
                          PlayService.instance.playbackService.playlist,
                      builder: (context, list, _) => Text(
                          '播放队列 · ${list.length}',
                          style: Theme.of(context).textTheme.titleMedium))),
              IconButton(
                  tooltip: '关闭播放队列',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded)),
            ])),
        const Expanded(child: CurrentPlaylistView(showHeader: false)),
      ]));
}
