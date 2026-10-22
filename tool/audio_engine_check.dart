import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/audio_native.dart';
import 'package:coriander_player/src/bass/bass.dart' as b;
import 'package:coriander_player/src/bass/gapless_mixer.dart';
import 'package:coriander_player/src/bass/loudness_worker.dart';
import 'package:coriander_player/play_service/loudness_model.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<double> writeWave(
    String filename, int rate, double seconds, double Function(int) sample) {
  final frames = (rate * seconds).round();
  final bytes = ByteData(44 + frames * 4);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, frames * 4, Endian.little);
  final expected = <double>[];
  for (var i = 0; i < frames; i++) {
    final value = (sample(i) * 32767).round().clamp(-32768, 32767);
    for (var channel = 0; channel < 2; channel++) {
      bytes.setInt16(44 + i * 4 + channel * 2, value, Endian.little);
      expected.add(value / 32768);
    }
  }
  File(filename).writeAsBytesSync(bytes.buffer.asUint8List());
  return expected;
}

void main(List<String> args) {
  final directory = path.absolute(args[0]);
  final fixtures = Directory(path.absolute(args[1]))
    ..createSync(recursive: true);
  final library = DynamicLibrary.open(path.join(directory, 'BASS', 'bass.dll'));
  final mixLibrary =
      DynamicLibrary.open(path.join(directory, 'BASS', 'bassmix.dll'));
  final bass = b.Bass(library);
  final extras = BassExtras(library);
  final mix = BassMix(mixLibrary);
  check(bass.BASS_Init(0, 48000, 0, nullptr, nullptr) != 0,
      'No-output BASS init failed');
  final buffer = calloc<Float>(8192);
  List<double> render(List<GaplessTrack> tracks,
      {double offset = 0, double volume = 1}) {
    final mixer = GaplessMixer(bass, mix, extras, decodeOutput: true);
    try {
      mixer.setVolume(volume);
      for (var i = 0; i < tracks.length; i++) {
        mixer.append(tracks[i], offset: i == 0 ? offset : 0);
      }
      final output = <double>[];
      while (true) {
        final count = extras.data(mixer.handle, buffer.cast(), 8192 * 4);
        if (count == 0xffffffff || count == 0) break;
        output.addAll(buffer.asTypedList(count ~/ 4));
        mixer.poll();
      }
      return output;
    } finally {
      mixer.close();
    }
  }

  try {
    final a = path.join(fixtures.path, 'boundary-a.wav');
    final c = path.join(fixtures.path, 'boundary-b.wav');
    final aSamples = writeWave(
        a, 48000, .37, (i) => .2 * math.sin(2 * math.pi * 1000 * i / 48000));
    final bSamples = writeWave(c, 48000, .41,
        (i) => .2 * math.sin(2 * math.pi * 1000 * (i + 17760) / 48000));
    final rendered = render([GaplessTrack(a, 0), GaplessTrack(c, 1)]);
    final expected = [...aSamples, ...bSamples];
    check(rendered.length == expected.length,
        'Gapless output length differs: ${rendered.length} vs ${expected.length}');
    var maxError = 0.0;
    for (var i = 0; i < expected.length; i++) {
      maxError = math.max(maxError, (rendered[i] - expected[i]).abs());
    }
    check(maxError < 1e-6,
        'Inserted silence or modified boundary samples: $maxError');
    print(
        'PASS sample-exact seamless boundary: ${expected.length ~/ 2} frames; max error $maxError');
    final gained = render([GaplessTrack(a, 0, gain: 2)], volume: .5);
    check(gained.length == aSamples.length, 'Gain changed audio duration');
    for (var i = 0; i < gained.length; i++) {
      check((gained[i] - aSamples[i]).abs() < 1e-6,
          'Master volume and normalization gain were applied incorrectly');
    }
    print(
        'PASS normalization gain and master volume on actual decoded samples');
    final repeated =
        render([GaplessTrack(a, 0), GaplessTrack(c, 1), GaplessTrack(a, 0)]);
    check(repeated.length == aSamples.length * 2 + bSamples.length,
        'Repeated queue length differs');
    final seek = render([GaplessTrack(a, 0), GaplessTrack(c, 1)], offset: .1);
    check(seek.length == expected.length - 4800 * 2,
        'Seek offset duration differs');
    print('PASS repeat queue and seek into a track');
    final mixedA = path.join(fixtures.path, 'rate-a.wav');
    final mixedB = path.join(fixtures.path, 'rate-b.wav');
    writeWave(mixedA, 44100, .4, (_) => .25);
    writeWave(mixedB, 48000, .4, (_) => .5);
    final mixed = render([GaplessTrack(mixedA, 0), GaplessTrack(mixedB, 1)]);
    check((mixed.length - 76800).abs() <= 8,
        'Resampling added a gap or lost duration: ${mixed.length}');
    final boundary = 19200 * 2;
    check(mixed.sublist(boundary - 40, boundary + 40).every((v) => v > .1),
        'Silence around different-rate boundary');
    print('PASS continuous queue across 44.1 kHz and 48 kHz files');
  } finally {
    calloc.free(buffer);
    bass.BASS_Free();
    mixLibrary.close();
    library.close();
  }

  final quiet = path.join(fixtures.path, 'quiet.wav');
  final loud = path.join(fixtures.path, 'loud.wav');
  writeWave(
      quiet, 48000, 2, (i) => .1 * math.sin(2 * math.pi * 1000 * i / 48000));
  writeWave(
      loud, 48000, 2, (i) => .4 * math.sin(2 * math.pi * 1000 * i / 48000));
  final result = analyzeLoudness(directory, [quiet, loud]);
  check((result['errors'] as List).isEmpty, 'Analysis failed: $result');
  final tracks = result['tracks'] as Map;
  final q = LoudnessMeasurement.fromJson(tracks[quiet] as Map);
  final l = LoudnessMeasurement.fromJson(tracks[loud] as Map);
  final delta = l.lufs! - q.lufs!;
  check((delta - 12.0412).abs() < .1, 'Incorrect loudness difference: $delta');
  final equalized = (.1 * q.gain()) / (.4 * l.gain());
  check((equalized - 1).abs() < .02,
      'Normalization did not equalize the tones: $equalized');
  print(
      'PASS R128 native analysis: delta ${delta.toStringAsFixed(3)} dB, normalized amplitude ratio ${equalized.toStringAsFixed(4)}');
  print('ALL AUDIO ENGINE CHECKS PASSED');
}
