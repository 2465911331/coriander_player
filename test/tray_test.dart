import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:coriander_player/tray_service.dart';
import 'package:coriander_player/window_behavior.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late TrayService service;
  var exitCount = 0;
  var hideCount = 0;
  var failIcon = false;
  var minimized = false;
  setUp(() {
    calls = [];
    exitCount = 0;
    hideCount = 0;
    failIcon = false;
    minimized = false;
    for (final channel in ['window_manager', 'tray_manager']) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add('$channel:${call.method}');
        if (call.method == 'setIcon' && failIcon)
          throw PlatformException(code: 'missing_icon');
        if (call.method == 'isMinimized') return minimized;
        if (call.method == 'restore') minimized = false;
        return null;
      });
    }
    service = TrayService(onExit: () async {
      exitCount++;
    }, onHide: () async {
      hideCount++;
    });
  });
  tearDown(() {
    service.dispose();
    for (final channel in ['window_manager', 'tray_manager']) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });
  test('close hides without shutting down playback or destroying the window',
      () async {
    await service.init();
    await service.onWindowClose();
    expect(hideCount, 1);
    expect(exitCount, 0);
    expect(calls, contains('window_manager:hide'));
    expect(calls, isNot(contains('window_manager:destroy')));
  });
  test('restore handles a minimized window before focusing it', () async {
    await service.init();
    minimized = true;
    calls.clear();
    await service.showWindow();
    expect(minimized, isFalse);
    expect(calls, contains('window_manager:show'));
    expect(calls.last, 'window_manager:focus');
  });
  test('repeated exit cleans up once', () async {
    await service.init();
    await Future.wait([service.exitApp(), service.exitApp()]);
    expect(exitCount, 1);
    expect(calls.where((e) => e == 'window_manager:destroy').length, 1);
  });
  test('window remains recoverable while exit cleanup is pending', () async {
    service.dispose();
    final cleanup = Completer<void>();
    service = TrayService(onHide: () async {}, onExit: () => cleanup.future);
    await service.init();
    final exiting = service.exitApp();
    await Future<void>.delayed(Duration.zero);
    calls.clear();
    await service.onTrayIconMouseDown();
    expect(calls, contains('window_manager:show'));
    expect(calls, contains('window_manager:focus'));
    cleanup.complete();
    await exiting;
    calls.clear();
    await service.showWindow();
    expect(calls, isEmpty);
  });
  test('failed tray setup keeps a real exit path', () async {
    failIcon = true;
    await service.init();
    await service.onWindowClose();
    expect(exitCount, 1);
    expect(calls, isNot(contains('window_manager:hide')));
  });
  test('save failure keeps the window recoverable', () async {
    service = TrayService(
        onHide: () async {},
        onExit: () async {
          throw StateError('disk full');
        });
    await service.init();
    await service.exitApp();
    expect(calls, contains('window_manager:show'));
    expect(calls, isNot(contains('window_manager:destroy')));
  });
  test('transport menu dispatches the selected action only', () {
    final actions = <String>[];
    service = TrayService(
        onHide: () async {},
        onExit: () async {},
        onTogglePlayback: () => actions.add('play'),
        onPrevious: () => actions.add('previous'),
        onNext: () => actions.add('next'));
    service.onTrayMenuItemClick(MenuItem(key: 'play', label: 'play'));
    service.onTrayMenuItemClick(MenuItem(key: 'next', label: 'next'));
    service.onTrayMenuItemClick(MenuItem(key: 'previous', label: 'previous'));
    expect(actions, ['play', 'next', 'previous']);
  });
  test('direct exit closes on X without hiding', () async {
    service.dispose();
    service = TrayService(
        onHide: () async {
          hideCount++;
        },
        onExit: () async {
          exitCount++;
        },
        closeBehavior: () => CloseBehavior.exit);
    await service.init();
    await service.onWindowClose();
    expect(exitCount, 1);
    expect(hideCount, 0);
    expect(calls, contains('window_manager:destroy'));
  });
  test(
      'ask mode ignores repeated close requests and cancellation leaves app open',
      () async {
    service.dispose();
    final answer = Completer<CloseBehavior?>();
    var prompts = 0;
    service = TrayService(
        onHide: () async {
          hideCount++;
        },
        onExit: () async {
          exitCount++;
        },
        closeBehavior: () => CloseBehavior.ask,
        confirmClose: () {
          prompts++;
          return answer.future;
        });
    await service.init();
    final closing = service.onWindowClose();
    await service.onWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 1);
    answer.complete(null);
    await closing;
    expect(exitCount, 0);
    expect(hideCount, 0);
    expect(calls, isNot(contains('window_manager:destroy')));
  });
  test('ask mode honors hide and later exit choices', () async {
    service.dispose();
    var choice = CloseBehavior.hideToTray;
    service = TrayService(
        onHide: () async {
          hideCount++;
        },
        onExit: () async {
          exitCount++;
        },
        closeBehavior: () => CloseBehavior.ask,
        confirmClose: () async => choice);
    await service.init();
    await service.onWindowClose();
    expect(hideCount, 1);
    expect(exitCount, 0);
    choice = CloseBehavior.exit;
    await service.onWindowClose();
    expect(exitCount, 1);
  });
  test('tray exit bypasses ask mode', () async {
    service.dispose();
    service = TrayService(
        onHide: () async {},
        onExit: () async {
          exitCount++;
        },
        closeBehavior: () => CloseBehavior.ask,
        confirmClose: () async => throw StateError('must not ask'));
    await service.init();
    await service.exitApp();
    expect(exitCount, 1);
  });
  test('unknown or missing old-version close setting defaults to tray', () {
    expect(CloseBehavior.fromJson(null), CloseBehavior.hideToTray);
    expect(CloseBehavior.fromJson('future-value'), CloseBehavior.hideToTray);
    expect(CloseBehavior.fromJson('exit'), CloseBehavior.exit);
  });
}
