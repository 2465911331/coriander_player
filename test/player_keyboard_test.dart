import 'package:coriander_player/hotkeys_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  tearDown(() async {
    for (final key in hotKeyManager.registeredHotKeyList.toList()) {
      await hotKeyManager.unregister(key);
    }
  });

  test('repeated focus registration cannot duplicate a playback hotkey', () {
    HotkeysHelper.registerHotKeys();
    HotkeysHelper.registerHotKeys();
    final keys = hotKeyManager.registeredHotKeyList;
    expect(keys.length, 3);
    expect(keys.map((key) => key.identifier).toSet().length, 3);
    expect(
        keys.any((key) => key.logicalKey == LogicalKeyboardKey.escape), false);
  });

  testWidgets('Escape closes a panel once and keeps its underlying page',
      (tester) async {
    HotkeysHelper.registerHotKeys();
    final navigator = GlobalKey<NavigatorState>();
    var pageEscapes = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => PlayerEscapeShortcut(
            onEscape: () {
              pageEscapes++;
              if (navigator.currentState!.canPop()) {
                navigator.currentState!.pop();
              }
            },
            child: child!),
        home: const Scaffold(body: Text('音乐库'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
                body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                () => Navigator.of(context).pop()
                          },
                          child: const Focus(
                              autofocus: true,
                              child:
                                  SizedBox(height: 300, child: Text('队列面板'))))),
              child: const Text('搜索结果'),
            ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索结果'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('队列面板'), findsNothing);
    expect(find.text('搜索结果'), findsOneWidget);
    expect(pageEscapes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('音乐库'), findsOneWidget);
    expect(pageEscapes, 1);
    expect(tester.takeException(), isNull);
  });
}
