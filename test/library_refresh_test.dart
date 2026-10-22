import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/component/library_refresh_button.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/library_refresh_service.dart';
import 'package:coriander_player/page/folders_page.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeated refresh requests share one scan and reload after completion',
      () async {
    final scan = StreamController<IndexActionState>();
    var scans = 0;
    var reloads = 0;
    final service = LibraryRefreshService(
      dataDirectory: () async => 'test-directory',
      scan: (path) {
        expect(path, 'test-directory');
        scans++;
        return scan.stream;
      },
      reload: (path) async {
        expect(path, 'test-directory');
        reloads++;
      },
    );
    final first = service.refresh();
    final second = service.refresh();
    expect(identical(first, second), isTrue);
    expect(service.isRefreshing, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(scans, 1);
    expect(reloads, 0);
    await scan.close();
    await first;
    expect(reloads, 1);
    expect(service.isRefreshing, isFalse);
    service.dispose();
  });

  test('scan errors preserve the current library and allow retry', () async {
    var scans = 0;
    var reloads = 0;
    final service = LibraryRefreshService(
      dataDirectory: () async => 'test-directory',
      scan: (_) => ++scans == 1
          ? Stream.error(const FileSystemException('unavailable'))
          : const Stream.empty(),
      reload: (_) async {
        reloads++;
      },
    );
    await expectLater(service.refresh(), throwsA(isA<FileSystemException>()));
    expect(reloads, 0);
    expect(service.isRefreshing, isFalse);
    await service.refresh();
    expect(reloads, 1);
    service.dispose();
  });

  test('reload failures surface instead of reporting a successful refresh',
      () async {
    final service = LibraryRefreshService(
      dataDirectory: () async => 'test-directory',
      scan: (_) => const Stream.empty(),
      reload: (_) async => throw const FormatException('invalid index'),
    );
    await expectLater(service.refresh(), throwsA(isA<FormatException>()));
    expect(service.isRefreshing, isFalse);
    service.dispose();
  });

  testWidgets(
      'refresh button disables duplicate clicks and recovers after scanning',
      (tester) async {
    final scan = StreamController<IndexActionState>();
    final service = LibraryRefreshService(
      dataDirectory: () async => 'test-directory',
      scan: (_) => scan.stream,
      reload: (_) async {},
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: LibraryRefreshButton(service: service),
    )));
    await tester.tap(find.byKey(const Key('refresh-library')));
    await tester.pump();
    expect(find.text('刷新中…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('refresh-library')))
            .onPressed,
        isNull);
    final closed = scan.close();
    await tester.pumpAndSettle();
    await closed;
    expect(find.text('刷新'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('refresh-library')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'open folder page updates after reloading the library; bad index preserves it',
      (tester) async {
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('coriander-library-test-')))!;
    final index = File('${directory.path}/index.json');
    Future<void> writeFolders(List<String> paths) =>
        index.writeAsString(json.encode({
          'version': 110,
          'folders': paths
              .map((path) => {
                    'path': path,
                    'modified': 1,
                    'latest': 1,
                    'audios': [],
                  })
              .toList(),
        }));
    try {
      await tester.runAsync(() async {
        await writeFolders(['C:/music/first']);
        await AudioLibrary.initFromIndex(
            dataDirectory: directory.path, throwOnError: true);
      });
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: FoldersPage())));
      expect(find.text('1 个文件夹'), findsOneWidget);
      await tester.runAsync(() async {
        await writeFolders(['C:/music/first', 'C:/music/new']);
        await AudioLibrary.initFromIndex(
            dataDirectory: directory.path, throwOnError: true);
      });
      await tester.pumpAndSettle();
      expect(find.text('2 个文件夹'), findsOneWidget);
      expect(find.text('C:/music/new'), findsOneWidget);
      final previous = AudioLibrary.instance;
      final revision = AudioLibrary.revision.value;
      await tester.runAsync(() async {
        await index.writeAsString('{broken');
        await expectLater(
            AudioLibrary.initFromIndex(
              dataDirectory: directory.path,
              throwOnError: true,
            ),
            throwsA(isA<FormatException>()));
      });
      expect(identical(AudioLibrary.instance, previous), isTrue);
      expect(AudioLibrary.revision.value, revision);
      expect(find.text('2 个文件夹'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
}
