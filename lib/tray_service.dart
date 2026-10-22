import 'package:flutter/foundation.dart';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/lifecycle_trace.dart';
import 'package:coriander_player/window_behavior.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Lives for the application lifetime, including welcome and indexing pages.
class TrayService with WindowListener, TrayListener {
  TrayService(
      {required this.onExit,
      required this.onHide,
      this.onTogglePlayback,
      this.onPrevious,
      this.onNext,
      this.closeBehavior,
      this.confirmClose});

  final AsyncCallback onExit;
  final AsyncCallback onHide;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueGetter<CloseBehavior>? closeBehavior;
  final Future<CloseBehavior?> Function()? confirmClose;
  bool _ready = false;
  bool _exiting = false;
  bool _destroying = false;
  bool _hiding = false;
  bool _handlingClose = false;

  Future<void> init() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    try {
      await trayManager.setIcon('app_icon.ico');
      await trayManager.setToolTip('Coriander Player');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem(key: 'play', label: '播放 / 暂停'),
        MenuItem(key: 'previous', label: '上一首'),
        MenuItem(key: 'next', label: '下一首'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ]));
      _ready = true;
    } catch (error, stack) {
      // If tray creation fails, close normally instead of hiding an
      // application that the user cannot restore.
      debugPrint('Failed to initialize system tray: $error\n$stack');
    }
  }

  @override
  Future<void> onWindowClose() async {
    if (_exiting || _hiding || _handlingClose) return;
    _handlingClose = true;
    try {
      if (!_ready) {
        await exitApp();
        return;
      }
      var behavior = closeBehavior?.call() ?? CloseBehavior.hideToTray;
      if (behavior == CloseBehavior.ask) {
        await showWindow();
        final choice = await confirmClose?.call();
        if (choice == null || choice == CloseBehavior.ask || _exiting) return;
        behavior = choice;
      }
      if (behavior == CloseBehavior.exit) {
        await exitApp();
        return;
      }
      _hiding = true;
      await onHide();
      if (!_exiting) {
        await windowManager.hide();
        VisualActivity.instance.value = false;
      }
    } catch (error, stack) {
      debugPrint('Failed to hide window: $error\n$stack');
    } finally {
      _hiding = false;
      _handlingClose = false;
    }
  }

  Future<void> showWindow() async {
    LifecycleTrace.record('show requested: exiting=$_exiting');
    if (_destroying) return;
    await windowManager.show();
    VisualActivity.instance.value = true;
    await windowManager.focus();
  }

  Future<void> exitApp() async {
    LifecycleTrace.record('exit requested: exiting=$_exiting');
    if (_exiting) return;
    _exiting = true;
    try {
      await onExit();
      LifecycleTrace.record('exit callback complete');
    } catch (error, stack) {
      LifecycleTrace.record('exit callback failed: ${error.runtimeType}');
      debugPrint('Failed to exit application: $error\n$stack');
      _exiting = false;
      await showWindow();
      return;
    }
    try {
      _destroying = true;
      await trayManager.destroy();
      LifecycleTrace.record('tray destroyed');
    } finally {
      dispose();
      // destroy bypasses the close-to-tray interception.
      await windowManager.destroy();
      LifecycleTrace.record('window destroy requested');
    }
  }

  @override
  Future<void> onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'exit':
        exitApp();
        break;
      case 'play':
        onTogglePlayback?.call();
        break;
      case 'previous':
        onPrevious?.call();
        break;
      case 'next':
        onNext?.call();
        break;
    }
  }

  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
