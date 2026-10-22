import 'dart:math' as math;

enum NormalizationMode {
  off('关闭'),
  track('单曲'),
  album('专辑');

  const NormalizationMode(this.label);
  final String label;
  static NormalizationMode fromJson(Object? value) =>
      values.firstWhere((mode) => mode.name == value, orElse: () => off);
}

class LoudnessMeasurement {
  const LoudnessMeasurement(this.lufs, this.peak);
  final double? lufs;
  final double peak;
  double gain({double target = -18}) {
    if (lufs == null || !lufs!.isFinite || !peak.isFinite || peak <= 0)
      return 1;
    // At most +12 dB boost, and retain 1 dB of true-peak headroom.
    final requested =
        math.pow(10, ((target - lufs!).clamp(-30, 12)) / 20).toDouble();
    return math.min(requested, math.pow(10, -1 / 20) / peak);
  }

  Map<String, Object?> toJson() => {'lufs': lufs, 'peak': peak};
  factory LoudnessMeasurement.fromJson(Map value) {
    final lufs = (value['lufs'] as num?)?.toDouble();
    final peak = (value['peak'] as num).toDouble();
    if ((lufs != null && !lufs.isFinite) || !peak.isFinite || peak < 0)
      throw const FormatException('Invalid loudness');
    return LoudnessMeasurement(lufs, peak);
  }
}
