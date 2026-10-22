import 'dart:ui';
import 'package:flutter/material.dart';

class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop(
      {super.key,
      this.cover,
      required this.trackKey,
      this.enabled = true,
      this.animate = true,
      this.blur = 28,
      this.strength = .35});
  final ImageProvider? cover;
  final Object? trackKey;
  final bool enabled, animate;
  final double blur, strength;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
        child: IgnorePointer(
            child: ClipRect(
                child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
              scheme.secondaryContainer,
              scheme.surface,
              scheme.primaryContainer
            ]))),
        AnimatedSwitcher(
            duration: Duration(
                milliseconds:
                    animate && !MediaQuery.disableAnimationsOf(context)
                        ? 650
                        : 0),
            child: enabled && cover != null
                ? SizedBox.expand(
                    key: ValueKey(trackKey),
                    child: Opacity(
                        opacity: strength,
                        child: ImageFiltered(
                            imageFilter:
                                ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                            child: Transform.scale(
                                scale: 1.15,
                                child: Image(
                                    image: cover!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink())))))
                : const SizedBox.expand(key: ValueKey('no-cover'))),
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
              scheme.secondaryContainer.withValues(alpha: .1),
              scheme.secondaryContainer.withValues(alpha: .7)
            ]))),
      ],
    ))));
  }
}
