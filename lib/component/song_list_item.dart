import 'package:flutter/material.dart';
import '../app_design.dart';
import 'library_card.dart';

class SongListItem extends StatelessWidget {
  const SongListItem(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.artwork,
      required this.onTap,
      this.onSecondaryTapDown,
      this.current = false,
      this.playing = false,
      this.selected = false,
      this.selecting = false,
      this.located = false,
      this.leading,
      this.action,
      this.duration});
  final String title, subtitle;
  final String? duration;
  final Widget artwork;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool current, playing, selected, selecting, located;
  final Widget? leading, action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    return Semantics(
        selected: selecting ? selected : null,
        child: LibrarySongRow(
            onTap: onTap,
            onSecondaryTapDown: onSecondaryTapDown,
            current: current || located,
            selected: selected,
            child: SizedBox(
                height: AppDesign.songExtent(context),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: LayoutBuilder(
                        builder: (context, bounds) => Row(children: [
                              if (selecting)
                                Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked,
                                        color: selected
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant)),
                              if (leading != null)
                                Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: leading!),
                              SizedBox(width: 48, height: 48, child: artwork),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                color: current || located
                                                    ? scheme.primary
                                                    : scheme.onSurface)),
                                    Text(subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall),
                                  ])),
                              if (current)
                                Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Tooltip(
                                        message: playing ? '正在播放' : '已暂停',
                                        child: Icon(
                                            playing
                                                ? Icons.graphic_eq_rounded
                                                : Icons
                                                    .pause_circle_outline_rounded,
                                            semanticLabel:
                                                playing ? '正在播放' : '已暂停',
                                            color: scheme.primary,
                                            size: 22))),
                              if (duration != null && bounds.maxWidth >= 420)
                                Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Text(duration!,
                                        style: theme.textTheme.bodySmall)),
                              if (action != null)
                                Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: action!),
                            ]))))));
  }
}
