import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/lyric_visuals.dart';
import 'package:coriander_player/src/bass/bass_player.dart';

import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricViewTile extends StatelessWidget {
  const LyricViewTile(
      {super.key, required this.line, required this.opacity, this.onTap});

  final LyricLine line;
  final double opacity;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final lyricViewController = context.watch<LyricViewController>();
    final preferences = AppearanceScope.of(context);
    final alignment = switch (lyricViewController.lyricTextAlign) {
      LyricTextAlign.left => Alignment.centerLeft,
      LyricTextAlign.center => Alignment.center,
      LyricTextAlign.right => Alignment.centerRight,
    };
    return Align(
        alignment: alignment,
        child: LyricLinePresentation(
            active: opacity == 1,
            inactiveOpacity: preferences.inactiveLyricOpacity,
            animate: allowVisualMotion(context, preferences),
            focus: preferences.lyricFocus,
            gentle: preferences.motion == MotionLevel.gentle,
            alignment: alignment,
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: line is SyncLyricLine
                    ? _SyncLineContent(
                        syncLine: line as SyncLyricLine,
                        isMainLine: opacity == 1)
                    : _LrcLineContent(
                        lrcLine: line as LrcLine, isMainLine: opacity == 1))));
  }
}

class _SyncLineContent extends StatelessWidget {
  const _SyncLineContent({required this.syncLine, required this.isMainLine});

  final SyncLyricLine syncLine;
  final bool isMainLine;

  @override
  Widget build(BuildContext context) {
    if (syncLine.words.isEmpty) {
      if (syncLine.length > const Duration(seconds: 5) && isMainLine) {
        return LyricTransitionTile(syncLine: syncLine);
      } else {
        return const SizedBox.shrink();
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    final lyricFontSize = lyricViewController.lyricFontSize;
    final translationFontSize = lyricViewController.translationFontSize;
    final alignment = lyricViewController.lyricTextAlign;

    if (!isMainLine) {
      if (syncLine.words.isEmpty) {
        return const SizedBox.shrink();
      }

      final List<Text> contents = [
        buildPrimaryText(
            context, syncLine.content, scheme, alignment, lyricFontSize),
      ];
      if (syncLine.translation != null) {
        contents.add(buildSecondaryText(
          syncLine.translation!,
          scheme,
          alignment,
          translationFontSize,
        ));
      }

      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: AppearanceScope.of(context).lyricLineSpacing),
        child: Column(
          crossAxisAlignment: switch (alignment) {
            LyricTextAlign.left => CrossAxisAlignment.start,
            LyricTextAlign.center => CrossAxisAlignment.center,
            LyricTextAlign.right => CrossAxisAlignment.end,
          },
          children: contents,
        ),
      );
    }

    final List<Widget> contents = [
      StreamBuilder(
        stream: PlayService.instance.playbackService.positionStream,
        initialData: PlayService.instance.playbackService.position,
        builder: (context, snapshot) {
          final posInMs = (snapshot.data ?? 0) * 1000;
          return RichText(
            textAlign: switch (alignment) {
              LyricTextAlign.left => TextAlign.left,
              LyricTextAlign.center => TextAlign.center,
              LyricTextAlign.right => TextAlign.right,
            },
            text: TextSpan(
              children: List.generate(
                syncLine.words.length,
                (i) {
                  final progress = lyricWordProgress(
                      posInMs,
                      syncLine.words[i].start.inMilliseconds,
                      syncLine.words[i].length.inMilliseconds);
                  return WidgetSpan(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: [
                            scheme.primary,
                            scheme.primary,
                            scheme.primary.withOpacity(0.10),
                            scheme.primary.withOpacity(0.10),
                          ],
                          stops: [0, progress, progress, 1],
                        ).createShader(bounds);
                      },
                      child: Text(
                        syncLine.words[i].content,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: lyricFontSize,
                          fontWeight: FontWeight.bold,
                          shadows: AppearanceScope.of(context).lyricGlow
                              ? [
                                  Shadow(
                                      color:
                                          scheme.primary.withValues(alpha: .3),
                                      blurRadius: 12)
                                ]
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      )
    ];
    if (syncLine.translation != null) {
      contents.add(buildSecondaryText(
        syncLine.translation!,
        scheme,
        alignment,
        translationFontSize,
      ));
    }
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: AppearanceScope.of(context).lyricLineSpacing),
      child: Column(
        crossAxisAlignment: switch (alignment) {
          LyricTextAlign.left => CrossAxisAlignment.start,
          LyricTextAlign.center => CrossAxisAlignment.center,
          LyricTextAlign.right => CrossAxisAlignment.end,
        },
        children: contents,
      ),
    );
  }

  Text buildPrimaryText(
    BuildContext context,
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(
        color: isMainLine ? scheme.primary : scheme.onSecondaryContainer,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: isMainLine && AppearanceScope.of(context).lyricGlow
            ? [
                Shadow(
                    color: scheme.primary.withValues(alpha: .3), blurRadius: 12)
              ]
            : null,
      ),
    );
  }

  Text buildSecondaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: fontSize),
    );
  }
}

class _LrcLineContent extends StatelessWidget {
  const _LrcLineContent({required this.lrcLine, required this.isMainLine});

  final LrcLine lrcLine;
  final bool isMainLine;

  @override
  Widget build(BuildContext context) {
    if (lrcLine.isBlank) {
      if (lrcLine.length > const Duration(seconds: 5) && isMainLine) {
        return LyricTransitionTile(lrcLine: lrcLine);
      } else {
        return const SizedBox.shrink();
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    final lyricFontSize = lyricViewController.lyricFontSize;
    final translationFontSize = lyricViewController.translationFontSize;
    final alignment = lyricViewController.lyricTextAlign;

    final splited = lrcLine.content.split("┃");
    final List<Text> contents = [
      buildPrimaryText(
          context, splited.first, scheme, alignment, lyricFontSize),
    ];
    for (var i = 1; i < splited.length; i++) {
      contents.add(buildSecondaryText(
        splited[i],
        scheme,
        alignment,
        translationFontSize,
      ));
    }

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: AppearanceScope.of(context).lyricLineSpacing),
      child: Column(
        crossAxisAlignment: switch (alignment) {
          LyricTextAlign.left => CrossAxisAlignment.start,
          LyricTextAlign.center => CrossAxisAlignment.center,
          LyricTextAlign.right => CrossAxisAlignment.end,
        },
        children: contents,
      ),
    );
  }

  Text buildPrimaryText(
    BuildContext context,
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(
        color: isMainLine ? scheme.primary : scheme.onSecondaryContainer,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: isMainLine && AppearanceScope.of(context).lyricGlow
            ? [
                Shadow(
                    color: scheme.primary.withValues(alpha: .3), blurRadius: 12)
              ]
            : null,
      ),
    );
  }

  Text buildSecondaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: fontSize),
    );
  }
}

/// 歌词间奏表示
/// lrcLine 和 syncLine 必须有且只有一个不为空
class LyricTransitionTile extends StatelessWidget {
  final LrcLine? lrcLine;
  final SyncLyricLine? syncLine;
  const LyricTransitionTile({super.key, this.lrcLine, this.syncLine});
  @override
  Widget build(BuildContext context) {
    final playback = PlayService.instance.playbackService;
    final preferences = AppearanceScope.of(context);
    final start = lrcLine?.start ?? syncLine!.start;
    final length = lrcLine?.length ?? syncLine!.length;
    return StreamBuilder(
        stream: playback.playerStateStream,
        initialData: playback.playerState,
        builder: (context, state) => StreamBuilder(
            stream: playback.positionStream,
            initialData: playback.position,
            builder: (context, snapshot) => InterludeDots(
                progress: lyricWordProgress((snapshot.data ?? 0) * 1000,
                    start.inMilliseconds, length.inMilliseconds),
                playing: state.data == PlayerState.playing,
                animate: allowVisualMotion(context, preferences))));
  }
}
