import 'library_search_box.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app_paths.dart' as paths;
import 'mini_now_playing.dart';
import 'side_nav.dart';
import 'title_bar.dart';
import 'playback_queue_panel.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.page});
  final Widget page;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 640;
    final scheme = Theme.of(context).colorScheme;
    return LibrarySearchShortcut(
        onSearch: () {
          if (!GoRouter.of(context)
              .routeInformationProvider
              .value
              .uri
              .path
              .startsWith(paths.SEARCH_PAGE)) {
            context.push(paths.SEARCH_PAGE);
          } else {
            LibrarySearchFocus.requests.value++;
          }
        },
        child: Scaffold(
            backgroundColor: scheme.surfaceContainer,
            appBar: const PreferredSize(
                preferredSize: Size.fromHeight(56), child: TitleBar()),
            drawer: compact ? const SideNav() : null,
            body: ValueListenableBuilder<bool>(
                valueListenable: AppPanels.queue,
                builder: (context, queue, _) => PlayerWorkspace(
                      navigation: compact ? null : const SideNav(),
                      page: ClipRRect(
                          borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18)),
                          child: page),
                      panel: queue &&
                              MediaQuery.sizeOf(context).width >=
                                  AppPanels.queueBreakpoint
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              child: SizedBox(
                                  width: 300,
                                  child: PlaybackQueuePanel(
                                      onClose: () =>
                                          AppPanels.queue.value = false)))
                          : null,
                      dock: const MiniNowPlaying(),
                    ))));
  }
}

/// Main content owns a separate dock region, so controls cannot cover a page.
class PlayerWorkspace extends StatelessWidget {
  const PlayerWorkspace(
      {super.key,
      required this.page,
      required this.dock,
      this.navigation,
      this.panel});
  final Widget page, dock;
  final Widget? navigation, panel;
  @override
  Widget build(BuildContext context) => Row(children: [
        if (navigation != null) navigation!,
        Expanded(
            key: const ValueKey('player-content'),
            child: Column(children: [
              Expanded(
                  child: Row(children: [
                Expanded(key: const ValueKey('page-content'), child: page),
                if (panel != null) panel!,
              ])),
              dock,
            ])),
      ]);
}
