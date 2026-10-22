import 'dart:math' as math;
import 'package:coriander_player/play_service/loudness_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'quiet and loud tracks reach the same integrated loudness when headroom allows',
      () {
    const quiet = LoudnessMeasurement(-26, .1);
    const loud = LoudnessMeasurement(-14, .4);
    double normalized(LoudnessMeasurement m) =>
        m.lufs! + 20 * math.log(m.gain()) / math.ln10;
    expect(normalized(quiet), closeTo(-18, .00001));
    expect(normalized(loud), closeTo(-18, .00001));
  });
  test('gain respects true-peak headroom and avoids unlimited amplification',
      () {
    const transient = LoudnessMeasurement(-28, .98);
    expect(transient.peak * transient.gain(),
        lessThanOrEqualTo(math.pow(10, -1 / 20) + 1e-9));
    expect(const LoudnessMeasurement(-60, .0001).gain(),
        closeTo(math.pow(10, 12 / 20), 1e-9));
  });
  test('silence and nonfinite signals stay at unity', () {
    expect(const LoudnessMeasurement(null, 0).gain(), 1);
    expect(const LoudnessMeasurement(double.negativeInfinity, 1).gain(), 1);
    expect(const LoudnessMeasurement(-20, double.nan).gain(), 1);
  });
  test('album mode uses one gain, preserving relative levels', () {
    final gain = const LoudnessMeasurement(-20, .5).gain();
    expect((.4 * gain) / (.1 * gain), closeTo(4, 1e-12));
  });
  test('measurement JSON round trips and rejects bad cache values', () {
    final loaded = LoudnessMeasurement.fromJson(
        const LoudnessMeasurement(-21.2, .8).toJson());
    expect(loaded.lufs, -21.2);
    expect(loaded.peak, .8);
    expect(() => LoudnessMeasurement.fromJson({'lufs': -20, 'peak': -1}),
        throwsFormatException);
    expect(NormalizationMode.fromJson('future'), NormalizationMode.off);
  });
}
