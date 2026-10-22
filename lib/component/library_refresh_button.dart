import 'package:coriander_player/library/library_refresh_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LibraryRefreshButton extends StatelessWidget {
  const LibraryRefreshButton({super.key, this.service});
  final LibraryRefreshService? service;

  @override
  Widget build(BuildContext context) {
    final refresh = service ?? LibraryRefreshService.instance;
    return ListenableBuilder(
      listenable: refresh,
      builder: (context, _) => Tooltip(
        message: '扫描音乐目录，显示新增或更新的歌曲',
        child: FilledButton.tonalIcon(
          key: const Key('refresh-library'),
          onPressed: refresh.isRefreshing
              ? null
              : () async {
                  try {
                    await refresh.refresh();
                    if (context.mounted) showTextOnSnackBar('音乐库刷新完成');
                  } catch (error, stack) {
                    LOGGER.e(error, stackTrace: stack);
                    if (context.mounted) {
                      showTextOnSnackBar('刷新失败，请检查音乐目录后重试');
                    }
                  }
                },
          icon: refresh.isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Symbols.refresh),
          label: Text(refresh.isRefreshing ? '刷新中…' : '刷新'),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 40)),
          ),
        ),
      ),
    );
  }
}
