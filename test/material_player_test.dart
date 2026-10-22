import 'package:coriander_player/app_design.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/app_shell.dart';
import 'package:coriander_player/component/player_dock.dart';
import 'package:coriander_player/component/player_artwork_hero.dart';
import 'package:coriander_player/component/song_list_item.dart';
import 'package:coriander_player/component/library_search_box.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/library_search.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/playlists_page.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform extends Fake implements RustLibApi {
  @override
  SystemTheme crateApiSystemThemeSystemThemeGetSystemTheme() =>
      const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 80, 120, 100));
}

Widget host(Widget child,
        {double width = 540,
        double scale = 1,
        AppearancePreferences? preferences,
        bool reduced = false}) =>
    MaterialApp(
        theme:
            AppDesign.theme(ColorScheme.fromSeed(seedColor: Colors.teal), null),
        home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 720),
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduced),
            child: AppearanceScope(
                preferences: preferences ?? AppearancePreferences(),
                child: Scaffold(body: child))));

PlayerDock dock({VoidCallback? open, VoidCallback? next}) => PlayerDock(
    title: '很长很长的歌曲名称 Long song title',
    subtitle: '艺术家 · 专辑',
    artwork: const ColoredBox(color: Colors.teal),
    playing: false,
    animate: false,
    onOpen: open ?? () {},
    onPlay: () {},
    onPrevious: () {},
    onNext: next ?? () {},
    onQueue: () {});

void main() {
  setUpAll(() => RustLib.initMock(api: _Platform()));
  tearDownAll(RustLib.dispose);

  testWidgets('search shortcut works without clicking a control first',
      (tester) async {
    var searches = 0;
    await tester.pumpWidget(host(LibrarySearchShortcut(
        onSearch: () => searches++, child: const Text('音乐库'))));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(searches, 1);
  });

  for (final width in [540.0, 900.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('dock reserves content space at $width and font scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(host(
            PlayerWorkspace(
                page: const SizedBox.expand(key: ValueKey('content')),
                navigation: width >= 900 ? const SizedBox(width: 80) : null,
                panel: width >= 1400 ? const SizedBox(width: 300) : null,
                dock: dock()),
            width: width,
            scale: scale));
        expect(tester.getRect(find.byKey(const ValueKey('content'))).bottom,
            lessThanOrEqualTo(tester.getRect(find.byType(PlayerDock)).top));
        expect(find.byTooltip('下一首'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('next button does not also expand player', (tester) async {
    var next = 0, open = 0;
    await tester.pumpWidget(host(Align(
        alignment: Alignment.bottomCenter,
        child: dock(next: () => next++, open: () => open++))));
    await tester.tap(find.byTooltip('下一首'));
    expect(next, 1);
    expect(open, 0);
    await tester.tap(find.text('很长很长的歌曲名称 Long song title'));
    expect(open, 1);
  });

  testWidgets('content scroll survives queue and navigation layout changes',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget workspace(bool wide) => host(PlayerWorkspace(
        navigation: wide ? const SizedBox(width: 80) : null,
        panel: wide ? const SizedBox(width: 200) : null,
        page: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemExtent: 60,
            itemBuilder: (_, i) => Text('歌曲 $i')),
        dock: const SizedBox(height: 100)));
    await tester.pumpWidget(workspace(false));
    controller.jumpTo(600);
    await tester.pump();
    await tester.pumpWidget(workspace(true));
    await tester.pump();
    expect(controller.offset, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song row preserves current and selected states with large fonts',
      (tester) async {
    await tester.pumpWidget(host(
        SongListItem(
            title: '歌曲',
            subtitle: '艺术家和专辑',
            artwork: const ColoredBox(color: Colors.teal),
            current: true,
            playing: true,
            selecting: true,
            selected: true,
            onTap: () {}),
        scale: 2));
    expect(find.byTooltip('正在播放'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(SongListItem)).height,
        greaterThanOrEqualTo(96));
    expect(tester.takeException(), isNull);
  });

  for (final system in [true, false]) {
    testWidgets(
        'route movement disabled by ${system ? 'system' : 'user'} preference',
        (tester) async {
      final preferences = AppearancePreferences()
        ..motion = system ? MotionLevel.gentle : MotionLevel.off;
      await tester.pumpWidget(host(
          const AppPageTransition(
              animation: AlwaysStoppedAnimation(.4), child: Text('页面')),
          preferences: preferences,
          reduced: system));
      expect(find.byType(SlideTransition), findsNothing);
      expect(find.text('页面'), findsOneWidget);
    });
  }

  testWidgets('shared artwork tolerates reversing a route during flight',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
            body: Column(children: [
          const SizedBox(
              width: 52,
              height: 52,
              child: PlayerArtworkHero(child: ColoredBox(color: Colors.teal))),
          TextButton(
              onPressed: () => navigator.currentState!.push(
                  MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                          body: Center(
                              child: SizedBox(
                                  width: 300,
                                  height: 300,
                                  child: PlayerArtworkHero(
                                      child:
                                          ColoredBox(color: Colors.teal))))))),
              child: const Text('打开')),
        ]))));
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search presents suggestions and submits the trimmed query',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(host(LibrarySearchBox(
        onSubmitted: (value) => submitted = value,
        search: (query) => UnionSearchResult(query)
          ..artists.addAll([Artist(name: '雨声'), Artist(name: '雨后')]))));
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  雨  ');
    await tester.pumpAndSettle();
    expect(find.text('雨声'), findsOneWidget);
    await tester.tap(find.text('查看全部 2 项结果'));
    await tester.pumpAndSettle();
    expect(submitted, '雨');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty search and no matches have explicit states',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(LibrarySearchBox(
        onSubmitted: (_) {},
        search: (query) {
          calls++;
          return UnionSearchResult(query);
        })));
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    expect(find.text('输入歌曲、艺术家或专辑名称'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextField).last, '找不到');
    await tester.pumpAndSettle();
    expect(find.text('没有找到“找不到”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a playlist can be undone without losing its identity',
      (tester) async {
    final original = Playlist('测试歌单', {});
    PLAYLISTS = [original];
    playlistsLoaded = false; // No fixture file is touched by this UI test.
    AppPreference.instance.playlistsPagePref.contentView = ContentView.list;
    await tester.pumpWidget(host(const PlaylistsPage()));
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(PLAYLISTS, isEmpty);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(identical(PLAYLISTS.single, original), isTrue);
    expect(find.text('测试歌单'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
