import 'dart:math' as math;

class WaveformData {
  WaveformData(this.duration, List<int> peaks)
      : peaks = List.unmodifiable(peaks);
  static const columns = 1200;
  final double duration;
  final List<int> peaks;
  Map<String, Object> toJson() =>
      {'version': 1, 'duration': duration, 'peaks': peaks};
  static WaveformData? fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != 1 ||
        json['duration'] is! num ||
        json['peaks'] is! List) return null;
    final duration = (json['duration'] as num).toDouble(),
        peaks = json['peaks'] as List;
    if (!duration.isFinite ||
        duration <= 0 ||
        peaks.length != columns ||
        peaks.any((value) => value is! int || value < 0 || value > 255))
      return null;
    return WaveformData(duration, peaks.cast<int>());
  }
}

/// Streaming peak envelope: constant memory, max across channels, never drops
/// short transients. Values are scaled together so quiet sections stay quiet.
class WaveformAccumulator {
  WaveformAccumulator(this.totalFrames, this.channels,
      {this.columns = WaveformData.columns})
      : _peaks = List.filled(columns, 0.0) {
    if (totalFrames < 1 || channels < 1 || columns < 1)
      throw ArgumentError('Invalid audio dimensions');
  }
  final int totalFrames, channels, columns;
  final List<double> _peaks;
  int frames = 0;
  void add(List<double> samples, int sampleCount) {
    for (var index = 0; index + channels <= sampleCount; index += channels) {
      double peak = 0;
      for (var channel = 0; channel < channels; channel++) {
        final value = samples[index + channel];
        if (value.isFinite) peak = math.max(peak, value.abs());
      }
      final column = math.min(columns - 1, frames * columns ~/ totalFrames);
      _peaks[column] = math.max(_peaks[column], peak);
      frames++;
    }
  }

  List<int> finish() {
    final maximum = _peaks.fold(0.0, math.max);
    if (maximum == 0) return List.filled(columns, 0);
    return _peaks
        .map((value) => (value / maximum * 255).round().clamp(0, 255))
        .toList();
  }
}
