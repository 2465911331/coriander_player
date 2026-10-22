import 'package:coriander_player/app_design.dart';
import 'dart:math' as math;
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/scroll_aware_future_builder.dart';
import 'package:flutter/material.dart';

enum LibraryArtworkKind { song, album, artist, playlist, folder }

class LibraryViewScope extends InheritedWidget {
  const LibraryViewScope(
      {super.key, required this.cards, required super.child});
  final bool cards;
  static bool cardsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryViewScope>()?.cards ??
      false;
  @override
  bool updateShouldNotify(LibraryViewScope oldWidget) =>
      cards != oldWidget.cards;
}

class LibraryArtwork extends StatelessWidget {
  const LibraryArtwork(
      {super.key,
      required this.identity,
      required this.seed,
      this.load,
      this.kind = LibraryArtworkKind.song,
      this.circular = false});
  final Object identity;
  final String seed;
  final Future<ImageProvider?> Function()? load;
  final LibraryArtworkKind kind;
  final bool circular;
  @override
  Widget build(BuildContext context) {
    final placeholder = _ArtworkPlaceholder(seed: seed, kind: kind);
    final content = load == null
        ? placeholder
        : ScrollAwareFutureBuilder<ImageProvider?>(
            identity: identity,
            future: load!,
            builder: (context, snapshot) =>
                snapshot.connectionState != ConnectionState.done ||
                        snapshot.data == null
                    ? placeholder
                    : Image(
                        image: snapshot.data!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => placeholder));
    return ExcludeSemantics(
        child: circular
            ? ClipOval(child: content)
            : ClipRRect(
                borderRadius: BorderRadius.circular(12), child: content));
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.seed, required this.kind});
  final String seed;
  final LibraryArtworkKind kind;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var hash = 0;
    for (final rune in seed.runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
    final base = HSVColor.fromColor(scheme.primaryContainer);
    final tint = base.withHue((base.hue + hash % 85 - 42) % 360).toColor();
    return LayoutBuilder(builder: (context, bounds) {
      final size = math.min(bounds.maxWidth, bounds.maxHeight);
      return DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                tint,
                scheme.secondaryContainer,
                scheme.tertiaryContainer
              ])),
          child: Stack(fit: StackFit.expand, children: [
            Positioned(
                right: -size * .18,
                top: -size * .2,
                child: Container(
                    width: size * .9,
                    height: size * .9,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: .09),
                            width: size * .08)))),
            Center(
                child: Icon(
                    switch (kind) {
                      LibraryArtworkKind.song => Icons.music_note_rounded,
                      LibraryArtworkKind.album => Icons.album_outlined,
                      LibraryArtworkKind.artist => Icons.person_outline_rounded,
                      LibraryArtworkKind.playlist => Icons.queue_music_rounded,
                      LibraryArtworkKind.folder => Icons.folder_outlined,
                    },
                    size: size * .42,
                    color: scheme.onSecondaryContainer.withValues(alpha: .7))),
            if (size >= 90 && seed.trim().isNotEmpty)
              Positioned(
                  left: 12,
                  bottom: 10,
                  child: Text(seed.trim().characters.first,
                      style: TextStyle(
                          fontSize: size * .13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSecondaryContainer
                              .withValues(alpha: .45)))),
          ]));
    });
  }
}

class LibraryMediaCard extends StatefulWidget {
  const LibraryMediaCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.artwork,
      required this.onTap,
      this.onPlay,
      this.onSecondaryTapDown,
      this.playing = false,
      this.current = false,
      this.selected = false,
      this.selecting = false,
      this.badge,
      this.menu,
      this.playLabel});
  final String title, subtitle;
  final Widget artwork;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool playing, current, selected, selecting;
  final String? badge, playLabel;
  final Widget? menu;
  @override
  State<LibraryMediaCard> createState() => _LibraryMediaCardState();
}

class _LibraryMediaCardState extends State<LibraryMediaCard> {
  bool _hovered = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme,
        preferences = AppearanceScope.maybeOf(context);
    final animate = (preferences?.animateLibraryCards ?? true) &&
        (preferences == null || allowVisualMotion(context, preferences)) &&
        !MediaQuery.disableAnimationsOf(context);
    final active = _hovered || _focused;
    final showPlay = !widget.selecting &&
        (active || widget.current || MediaQuery.sizeOf(context).width < 700);
    final duration = animate ? AppMotion.fast : Duration.zero;
    final borderColor = widget.selected || widget.current
        ? scheme.primary.withValues(alpha: .65)
        : scheme.outlineVariant.withValues(alpha: active ? .65 : .3);
    final playButton = widget.onPlay == null
        ? const SizedBox.shrink()
        : ExcludeFocus(
            excluding: !showPlay,
            child: IgnorePointer(
                ignoring: !showPlay,
                child: AnimatedOpacity(
                    opacity: showPlay ? 1 : 0,
                    duration: duration,
                    child: IconButton.filled(
                        tooltip:
                            widget.playLabel ?? (widget.playing ? '暂停' : '播放'),
                        onPressed: widget.selecting ? null : widget.onPlay,
                        icon: Icon(widget.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded)))));
    return Tooltip(
        message: widget.title,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.curve,
          transform:
              Matrix4.translationValues(0, active && animate ? -4 : 0, 0),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: preferences?.libraryCardShadows == false
                  ? null
                  : [
                      BoxShadow(
                          color: Colors.black
                              .withValues(alpha: active ? .13 : .045),
                          blurRadius: active ? 18 : 8,
                          offset: Offset(0, active ? 7 : 2))
                    ]),
          child: Material(
              color: widget.selected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                      color: _focused ? scheme.primary : borderColor,
                      width: _focused ? 2 : 1)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onSecondaryTapDown: widget.onSecondaryTapDown,
                onHover: (value) => setState(() => _hovered = value),
                onFocusChange: (value) => setState(() => _focused = value),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Center(
                                  child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            widget.artwork,
                                            if (widget.badge != null)
                                              Positioned(
                                                  top: 6,
                                                  left: 6,
                                                  child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                          color: scheme.surface
                                                              .withValues(
                                                                  alpha: .9),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                  8)),
                                                      child: Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4),
                                                          child: Text(widget.badge!,
                                                              style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: scheme
                                                                      .onSurface))))),
                                            if (widget.selecting)
                                              Positioned(
                                                  top: 6,
                                                  right: 6,
                                                  child: Icon(
                                                      widget.selected
                                                          ? Icons.check_circle
                                                          : Icons
                                                              .radio_button_unchecked,
                                                      color: widget.selected
                                                          ? scheme.primary
                                                          : scheme.onSurface)),
                                            Positioned(
                                                right: 8,
                                                bottom: 8,
                                                child: playButton),
                                          ])))),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: Row(children: [
                                Expanded(
                                    child: Text(widget.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.fontSize,
                                            color: widget.current
                                                ? scheme.primary
                                                : scheme.onSurface))),
                                if (widget.menu != null)
                                  SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: widget.menu!)
                              ])),
                          const SizedBox(height: 4),
                          Text(widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ])),
              )),
        ));
  }
}

class LibrarySongRow extends StatefulWidget {
  const LibrarySongRow(
      {super.key,
      required this.child,
      required this.onTap,
      this.onSecondaryTapDown,
      this.selected = false,
      this.current = false});
  final Widget child;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool selected, current;
  @override
  State<LibrarySongRow> createState() => _LibrarySongRowState();
}

class _LibrarySongRowState extends State<LibrarySongRow> {
  bool _hovered = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
        color: widget.selected
            ? scheme.secondaryContainer
            : _hovered || widget.current
                ? scheme.surfaceContainerHighest.withValues(alpha: .65)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            borderRadius: BorderRadius.circular(12),
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            focusColor: scheme.primary.withValues(alpha: .15),
            child: DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: _focused
                        ? Border.all(color: scheme.primary, width: 2)
                        : null),
                child: widget.child)));
  }
}
