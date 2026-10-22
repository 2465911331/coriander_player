import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../app_paths.dart' as paths;
import '../library/library_search.dart';

abstract final class LibrarySearchFocus {
  static final requests = ValueNotifier(0);
}

class LibrarySearchShortcut extends StatelessWidget {
  const LibrarySearchShortcut(
      {super.key, required this.onSearch, required this.child});
  final VoidCallback onSearch;
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): onSearch,
      }, child: Focus(autofocus: true, child: child));
}

class LibrarySearchBox extends StatefulWidget {
  const LibrarySearchBox(
      {super.key,
      required this.onSubmitted,
      this.initialQuery = '',
      this.autofocus = false,
      this.onFocusChanged,
      this.search});
  final String initialQuery;
  final bool autofocus;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final UnionSearchResult Function(String)? search;
  @override
  State<LibrarySearchBox> createState() => _LibrarySearchBoxState();
}

class _LibrarySearchBoxState extends State<LibrarySearchBox> {
  late final controller = SearchController()..text = widget.initialQuery;
  final focus = FocusNode();
  bool open = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
    LibrarySearchFocus.requests.addListener(_requestFocus);
  }

  void _requestFocus() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      focus.requestFocus();
      controller.selection =
          TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    }
  }

  void _focusChanged() => widget.onFocusChanged?.call(open || focus.hasFocus);
  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    if (controller.isOpen) controller.closeView(query);
    focus.unfocus();
    widget.onSubmitted(query);
  }

  void _visit(String path, Object extra) {
    controller.closeView(controller.text);
    focus.unfocus();
    context.push(path, extra: extra);
  }

  @override
  void dispose() {
    LibrarySearchFocus.requests.removeListener(_requestFocus);
    focus.removeListener(_focusChanged);
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchAnchor(
      searchController: controller,
      isFullScreen: MediaQuery.sizeOf(context).width < 600,
      viewHintText: '搜索歌曲、艺术家、专辑',
      viewOnSubmitted: _submit,
      viewOnOpen: () {
        open = true;
        _focusChanged();
      },
      viewOnClose: () {
        open = false;
        _focusChanged();
      },
      viewTrailing: [
        IconButton(
            tooltip: '清空搜索',
            onPressed: controller.clear,
            icon: const Icon(Icons.close_rounded))
      ],
      builder: (context, controller) => Hero(
          tag: 'coriander-library-search',
          child: Material(
              type: MaterialType.transparency,
              child: SearchBar(
                  controller: controller,
                  focusNode: focus,
                  autoFocus: widget.autofocus,
                  hintText: '搜索歌曲、艺术家、专辑',
                  leading: const Icon(Icons.search_rounded),
                  onTap: controller.openView,
                  onChanged: (_) => controller.openView(),
                  onSubmitted: _submit,
                  trailing: [
                    IconButton(
                        tooltip: '开始搜索',
                        onPressed: () => _submit(controller.text),
                        icon: const Icon(Icons.arrow_forward_rounded))
                  ]))),
      suggestionsBuilder: (context, controller) {
        final query = controller.text.trim();
        if (query.isEmpty) {
          return [
            const ListTile(
                title: Text('输入歌曲、艺术家或专辑名称'), subtitle: Text('回车查看全部结果'))
          ];
        }
        final result = (widget.search ?? UnionSearchResult.search)(query);
        final count =
            result.audios.length + result.artists.length + result.album.length;
        if (count == 0) {
          return [
            ListTile(
                leading: const Icon(Icons.search_off_rounded),
                title: Text('没有找到“$query”', maxLines: 2),
                subtitle: const Text('试试更短的关键词，或刷新音乐库'))
          ];
        }
        return [
          ListTile(
              leading: const Icon(Icons.manage_search_rounded),
              title: Text('查看全部 $count 项结果'),
              onTap: () => _submit(query)),
          for (final audio in result.audios.take(5))
            ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: Text(audio.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(audio.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _visit(paths.AUDIOS_PAGE, audio)),
          for (final artist in result.artists.take(3))
            ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(artist.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('艺术家'),
                onTap: () => _visit(paths.ARTIST_DETAIL_PAGE, artist)),
          for (final album in result.album.take(3))
            ListTile(
                leading: const Icon(Icons.album_outlined),
                title: Text(album.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('专辑'),
                onTap: () => _visit(paths.ALBUM_DETAIL_PAGE, album)),
        ];
      });
}
