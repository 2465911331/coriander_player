import 'dart:ffi';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';

const fft2048 = 0x80000003;
const fftRemoveDc = 0x40;

/// Logarithmic frequency bands, scaled from -70 dB to 0 dB.
List<double> spectrumBands(List<double> fft, double sampleRate,
    {int count = 40}) {
  if (fft.length < 2 || !sampleRate.isFinite || sampleRate <= 0 || count < 1) {
    return List.filled(math.max(count, 0), 0);
  }
  final upper = math.min(18000.0, sampleRate / 2);
  final lower = math.min(30.0, upper / 2);
  final fftSize = fft.length * 2;
  return List.generate(count, (index) {
    final from =
        (lower * math.pow(upper / lower, index / count) * fftSize / sampleRate)
            .floor()
            .clamp(1, fft.length - 1);
    final to = (lower *
            math.pow(upper / lower, (index + 1) / count) *
            fftSize /
            sampleRate)
        .ceil()
        .clamp(from + 1, fft.length);
    double peak = 0;
    for (var bin = from; bin < to; bin++) {
      if (fft[bin].isFinite) peak = math.max(peak, fft[bin].abs());
    }
    if (peak <= .0000001) return 0.0;
    return ((20 * math.log(peak) / math.ln10 + 70) / 70).clamp(0.0, 1.0);
  });
}

class SpectrumReader {
  final _buffer = calloc<Float>(1024);
  bool _closed = false;
  List<double> read(
      int Function(Pointer<Void>, int) readData, double frequency) {
    if (_closed) return const [];
    final bytes = readData(_buffer.cast(), fft2048 | fftRemoveDc);
    if (bytes == 0xffffffff || bytes == 0) return List.filled(40, 0);
    return spectrumBands(_buffer.asTypedList(1024), frequency);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    calloc.free(_buffer);
  }
}
