import 'package:coriander_player/component/close_confirmation_dialog.dart';
import 'package:coriander_player/window_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in <String, CloseBehavior?>{
    '取消': null,
    '退出程序': CloseBehavior.exit,
    '隐藏到托盘': CloseBehavior.hideToTray,
  }.entries) {
    testWidgets('close confirmation: ${entry.key}', (tester) async {
      CloseBehavior? result;
      var completed = false;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<CloseBehavior>(
                        context: context,
                        builder: (_) => const CloseConfirmationDialog());
                    completed = true;
                  },
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, entry.value);
    });
  }
}
