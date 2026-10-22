import 'package:coriander_player/window_behavior.dart';
import 'package:flutter/material.dart';

class CloseConfirmationDialog extends StatelessWidget {
  const CloseConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('关闭播放器'),
        content: const Text('隐藏到托盘后，音乐将继续播放。你也可以直接退出程序。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, CloseBehavior.exit),
            child: const Text('退出程序'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, CloseBehavior.hideToTray),
            child: const Text('隐藏到托盘'),
          ),
        ],
      );
}
