import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:coriander_player/app_paths.dart' as paths;
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/library_search.dart';
import 'package:coriander_player/component/library_search_box.dart';
export 'package:coriander_player/library/library_search.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('搜索音乐库',
                            style: Theme.of(context).textTheme.headlineLarge),
                        const SizedBox(height: 8),
                        Text('找到下一首想听的歌',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 24),
                        LibrarySearchBox(
                            autofocus: true,
                            onFocusChanged: HotkeysHelper.onFocusChanges,
                            onSubmitted: (query) => context.push(
                                paths.SEARCH_RESULT_PAGE,
                                extra: UnionSearchResult.search(query))),
                      ])))));
}
