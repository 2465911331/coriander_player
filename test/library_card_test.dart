import 'dart:async';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/library_card.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child,
        {double width = 1000,
        bool reduced = false,
        AppearancePreferences? preferences,
        double textScale = 1}) =>
    MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 800),
                disableAnimations: reduced,
                textScaler: TextScaler.linear(textScale)),
            child: AppearanceScope(
                preferences: preferences ?? AppearancePreferences(),
                child: Scaffold(
                    body: Center(
                        child: SizedBox(
                            width: 190, height: 280, child: child))))));

LibraryMediaCard card(
        {VoidCallback? tap,
        VoidCallback? play,
        bool selecting = false,
        bool selected = false,
        GestureTapDownCallback? secondary,
        Widget? menu}) =>
    LibraryMediaCard(
        title: '一首非常非常长的歌曲名称 Long song title',
        subtitle: '艺术家 · 专辑名称',
        artwork: const LibraryArtwork(identity: 'song', seed: '晚风'),
        onTap: tap ?? () {},
        onPlay: play ?? () {},
        selecting: selecting,
        selected: selected,
        onSecondaryTapDown: secondary,
        menu: menu);

void main() {
  test(
      'disabled card effects survive settings reload and older settings migrate',
      () {
    final preferences = AppearancePreferences()
      ..animateLibraryCards = false
      ..libraryCardShadows = false
      ..rotationSeconds = 32;
    final restored = AppearancePreferences()..read(preferences.toJson());
    expect(restored.animateLibraryCards, isFalse);
    expect(restored.libraryCardShadows, isFalse);
    expect(restored.rotationSeconds, 32);
    restored.read({'artwork': 'classic', 'motion': 'off'});
    expect(restored.animateLibraryCards, isTrue);
    expect(restored.libraryCardShadows, isTrue);
    expect(restored.artwork, ArtworkStyle.classic);
    expect(restored.motion, MotionLevel.off);
  });

  testWidgets('deferred artwork stops scheduling when the page is removed',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: ListView(physics: const _DeferArtworkPhysics(), children: [
      SizedBox(
          height: 100,
          child: ScrollAwareFutureBuilder<String>(
              identity: 'deferred',
              future: () async {
                loads++;
                return 'loaded';
              },
              builder: (_, snapshot) => Text(snapshot.data ?? 'waiting')))
    ])));
    await tester.pump();
    expect(loads, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(loads, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover reveals play and play does not open the card',
      (tester) async {
    var opens = 0, plays = 0;
    await tester
        .pumpWidget(host(card(tap: () => opens++, play: () => plays++)));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(LibraryMediaCard)));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(plays, 1);
    expect(opens, 0);
    await tester.tap(find.text('艺术家 · 专辑名称'));
    expect(opens, 1);
    await mouse.removePointer();
  });

  testWidgets('selection prevents playback and keeps selection tap',
      (tester) async {
    var opens = 0, plays = 0;
    await tester.pumpWidget(host(
        card(
            selecting: true,
            selected: true,
            tap: () => opens++,
            play: () => plays++),
        width: 500));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0);
    await tester.tap(find.text('艺术家 · 专辑名称'));
    expect(opens, 1);
    expect(plays, 0);
  });

  testWidgets('secondary click reaches the existing context menu',
      (tester) async {
    var secondary = 0, primary = 0;
    await tester.pumpWidget(
        host(card(secondary: (_) => secondary++, tap: () => primary++)));
    await tester.tap(find.byType(LibraryMediaCard),
        buttons: kSecondaryMouseButton);
    expect(secondary, 1);
    expect(primary, 0);
  });

  testWidgets('small windows expose play and long text fits with larger fonts',
      (tester) async {
    await tester.pumpWidget(host(card(menu: const Icon(Icons.more_vert)),
        width: 500, textScale: 1.5));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [true, false]) {
    testWidgets(
        'reduced motion or disabled preference prevents hover movement ($reduced)',
        (tester) async {
      final preferences = AppearancePreferences()
        ..animateLibraryCards = reduced;
      await tester
          .pumpWidget(host(card(), preferences: preferences, reduced: reduced));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(LibraryMediaCard)));
      await tester.pumpAndSettle();
      final container =
          tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(container.transform!.storage[13], 0);
      await mouse.removePointer();
    });
  }

  testWidgets('missing artwork is fetched once per identity including rebuilds',
      (tester) async {
    var loads = 0;
    Widget art(String id) => LibraryArtwork(
        identity: id,
        seed: id,
        load: () async {
          loads++;
          return null;
        });
    await tester.pumpWidget(host(art('a')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(art('a')));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.pumpWidget(host(art('b')));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late old resource completion cannot replace a recycled item',
      (tester) async {
    final old = Completer<String>(), next = Completer<String>();
    Widget resource(String id, Completer<String> future) =>
        host(ScrollAwareFutureBuilder<String>(
            identity: id,
            future: () => future.future,
            builder: (_, snapshot) => Text(snapshot.data ?? 'loading')));
    await tester.pumpWidget(resource('old', old));
    await tester.pumpWidget(resource('next', next));
    next.complete('new song');
    await tester.pumpAndSettle();
    old.complete('old song');
    await tester.pumpAndSettle();
    expect(find.text('new song'), findsOneWidget);
    expect(find.text('old song'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow grid can locate last song without division or scroll errors',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 220,
                child: UniPage<int>(
                    pref: PagePreference(
                        0, SortOrder.ascending, ContentView.table),
                    title: '音乐',
                    useMediaCards: true,
                    locateTo: 39,
                    contentList: List.generate(40, (i) => i),
                    contentBuilder: (context, item, _, __) => LibraryMediaCard(
                        title: '歌曲 $item',
                        subtitle: '测试',
                        artwork:
                            const LibraryArtwork(identity: 'a', seed: '测试'),
                        onTap: () {}),
                    enableShufflePlay: false,
                    enableSortMethod: false,
                    enableSortOrder: false,
                    enableContentViewSwitch: false)))));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 39'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DeferArtworkPhysics extends ScrollPhysics {
  const _DeferArtworkPhysics({super.parent});
  @override
  _DeferArtworkPhysics applyTo(ScrollPhysics? ancestor) =>
      _DeferArtworkPhysics(parent: buildParent(ancestor));
  @override
  bool recommendDeferredLoading(
          double velocity, ScrollMetrics metrics, BuildContext context) =>
      true;
}
