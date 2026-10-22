import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'appearance.dart';

/// Product motion roles; shared by routes, panels and custom controls.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 170);
  static const page = Duration(milliseconds: 280);
  static const artwork = Duration(milliseconds: 350);
  static const curve = Curves.easeOutCubic;
  static bool enabled(BuildContext context) {
    final preferences = AppearanceScope.maybeOf(context);
    return !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context) &&
        (preferences == null || preferences.motion != MotionLevel.off);
  }

  static Duration duration(BuildContext context, [Duration value = page]) =>
      enabled(context) ? value : Duration.zero;
}

abstract final class AppDesign {
  static const cardRadius = 18.0;
  static double songExtent(BuildContext context) => math.max(
      64,
      MediaQuery.textScalerOf(context).scale(16) * 1.4 +
          MediaQuery.textScalerOf(context).scale(12) * 1.5 +
          20);

  static ThemeData theme(ColorScheme scheme, String? fontFamily) {
    final base = ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        brightness: scheme.brightness,
        fontFamily: fontFamily);
    final round =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius));
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        headlineLarge:
            base.textTheme.headlineLarge?.copyWith(fontSize: 28, height: 1.25),
        headlineMedium:
            base.textTheme.headlineMedium?.copyWith(fontSize: 24, height: 1.3),
        titleMedium: base.textTheme.titleMedium
            ?.copyWith(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
        bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
          color: scheme.surfaceContainerLow,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: round,
          clipBehavior: Clip.antiAlias),
      dialogTheme: DialogThemeData(
          backgroundColor: scheme.surfaceContainerHigh,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
      menuTheme: MenuThemeData(
          style: MenuStyle(
              backgroundColor:
                  WidgetStatePropertyAll(scheme.surfaceContainerHigh),
              shape: WidgetStatePropertyAll(round))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      dividerTheme:
          DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      hoverColor: scheme.onSurface.withValues(alpha: .08),
      focusColor: scheme.primary.withValues(alpha: .12),
      tooltipTheme:
          const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
    );
  }
}

class AppPageTransition extends StatelessWidget {
  const AppPageTransition(
      {super.key,
      required this.animation,
      required this.child,
      this.player = false});
  final Animation<double> animation;
  final Widget child;
  final bool player;
  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;
    final eased = animation.drive(CurveTween(curve: AppMotion.curve));
    return FadeTransition(
        opacity: eased,
        child: SlideTransition(
            position:
                Tween(begin: Offset(0, player ? .06 : .025), end: Offset.zero)
                    .animate(eased),
            child: child));
  }
}
