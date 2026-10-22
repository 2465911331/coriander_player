import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

enum ArtworkStyle { classic, vinyl }

enum ProgressStyle { line, wave, waveform }

enum SpectrumStyle { off, bars, ring }

enum MotionLevel { off, gentle, full }

class AppearancePreferences extends ChangeNotifier {
  ArtworkStyle artwork = ArtworkStyle.vinyl;
  ProgressStyle progress = ProgressStyle.wave;
  MotionLevel motion = MotionLevel.gentle;
  bool animateLibraryCards = true;
  bool libraryCardShadows = true;
  bool coverBackground = true;
  bool animateControls = true;
  bool savePower = true;
  double rotationSeconds = 24;
  double waveAmplitude = 5;
  double backgroundBlur = 28;
  double backgroundStrength = .35;
  SpectrumStyle spectrum = SpectrumStyle.bars;
  bool lyricFocus = true;
  bool lyricEdgeFade = true;
  bool lyricGlow = true;
  double inactiveLyricOpacity = .38;
  double lyricLineSpacing = 14;

  static T _enum<T extends Enum>(List<T> values, Object? value, T fallback) =>
      values.where((item) => item.name == value).firstOrNull ?? fallback;
  static double _number(
          Object? value, double fallback, double min, double max) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;

  void read(Object? json) {
    if (json is! Map) return;
    artwork = _enum(ArtworkStyle.values, json['artwork'], ArtworkStyle.vinyl);
    progress =
        _enum(ProgressStyle.values, json['progress'], ProgressStyle.wave);
    motion = _enum(MotionLevel.values, json['motion'], MotionLevel.gentle);
    animateLibraryCards = json['animateLibraryCards'] != false;
    libraryCardShadows = json['libraryCardShadows'] != false;
    coverBackground = json['coverBackground'] != false;
    animateControls = json['animateControls'] != false;
    savePower = json['savePower'] != false;
    rotationSeconds = _number(json['rotationSeconds'], 24, 12, 40);
    waveAmplitude = _number(json['waveAmplitude'], 5, 2, 9);
    backgroundBlur = _number(json['backgroundBlur'], 28, 8, 48);
    backgroundStrength = _number(json['backgroundStrength'], .35, .1, .6);
    spectrum =
        _enum(SpectrumStyle.values, json['spectrum'], SpectrumStyle.bars);
    lyricFocus = json['lyricFocus'] != false;
    lyricEdgeFade = json['lyricEdgeFade'] != false;
    lyricGlow = json['lyricGlow'] != false;
    inactiveLyricOpacity = _number(json['inactiveLyricOpacity'], .38, .18, .7);
    lyricLineSpacing = _number(json['lyricLineSpacing'], 14, 8, 24);
    notifyListeners();
  }

  Map<String, Object> toJson() => {
        'animateLibraryCards': animateLibraryCards,
        'libraryCardShadows': libraryCardShadows,
        'artwork': artwork.name,
        'progress': progress.name,
        'motion': motion.name,
        'coverBackground': coverBackground,
        'animateControls': animateControls,
        'savePower': savePower,
        'rotationSeconds': rotationSeconds,
        'waveAmplitude': waveAmplitude,
        'backgroundBlur': backgroundBlur,
        'backgroundStrength': backgroundStrength,
        'spectrum': spectrum.name,
        'lyricFocus': lyricFocus,
        'lyricEdgeFade': lyricEdgeFade,
        'lyricGlow': lyricGlow,
        'inactiveLyricOpacity': inactiveLyricOpacity,
        'lyricLineSpacing': lyricLineSpacing,
      };

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

class AppearanceScope extends InheritedNotifier<AppearancePreferences> {
  const AppearanceScope(
      {super.key,
      required AppearancePreferences preferences,
      required super.child})
      : super(notifier: preferences);
  static AppearancePreferences of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
  static AppearancePreferences? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}

bool allowVisualMotion(
        BuildContext context, AppearancePreferences preferences) =>
    preferences.motion != MotionLevel.off &&
    !MediaQuery.disableAnimationsOf(context) &&
    TickerMode.of(context);

/// Window visibility affects decoration only; audio and tray behavior are untouched.
class VisualActivity extends ValueNotifier<bool> with WindowListener {
  VisualActivity._() : super(true);
  static final instance = VisualActivity._();
  void attach() => windowManager.addListener(this);
  @override
  void onWindowMinimize() => value = false;
  @override
  void onWindowFocus() => value = true;
  @override
  void onWindowRestore() => value = true;
}
