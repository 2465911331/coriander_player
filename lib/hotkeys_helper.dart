import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// Let focused dialogs and panels handle Escape before page navigation.
class PlayerEscapeShortcut extends StatelessWidget {
  const PlayerEscapeShortcut(
      {super.key, required this.onEscape, required this.child});
  final VoidCallback onEscape;
  final Widget child;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      }, child: Focus(autofocus: true, child: child));
}

class HotkeysHelper {
  static final Map<HotKey, void Function(HotKey)> _hotKeys = {
    HotKey(key: PhysicalKeyboardKey.space, scope: HotKeyScope.inapp): (_) {
      final playbackService = PlayService.instance.playbackService;
      final state = playbackService.playerState;
      if (state == PlayerState.playing) {
        playbackService.pause();
      } else if (state == PlayerState.completed) {
        playbackService.playAgain();
      } else {
        playbackService.start();
      }
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowLeft,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      PlayService.instance.playbackService.lastAudio();
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowRight,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      PlayService.instance.playbackService.nextAudio();
    },
  };

  static void registerHotKeys() {
    for (var item in _hotKeys.entries) {
      if (hotKeyManager.registeredHotKeyList
          .any((key) => key.identifier == item.key.identifier)) continue;
      hotKeyManager.register(
        item.key,
        keyDownHandler: item.value,
      );
    }
  }

  static Future<void> unregisterAll() => hotKeyManager.unregisterAll();

  static bool _editing = false;
  static Future<void> _focusUpdate = Future.value();
  static Future<void> onFocusChanges(bool focus) {
    _editing = focus;
    _focusUpdate = _focusUpdate.then((_) async {
      await unregisterAll();
      if (!_editing) registerHotKeys();
    });
    return _focusUpdate;
  }
}
