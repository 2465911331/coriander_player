// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/audio_native.dart';
import 'package:coriander_player/src/bass/bass.dart' as b;
import 'package:coriander_player/src/bass/bass_wasapi.dart' as w;
import 'package:coriander_player/src/bass/spectrum_reader.dart';
import 'package:coriander_player/src/bass/waveform_worker.dart';

void check(bool valid, String message) {
  if (!valid) throw StateError(message);
}

void makeFixture(String file) {
  const frames = 48000 * 8;
  final bytes = ByteData(44 + frames * 4);
  void text(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, 48000, Endian.little);
  bytes.setUint32(28, 192000, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    final part = i ~/ 96000;
    final amplitude = [.05, .8, 0.0, .2][part],
        frequency = [440, 4000, 440, 8800][part];
    final sample =
        (math.sin(i / 48000 * 2 * math.pi * frequency) * amplitude * 32767)
            .round();
    // Opposite channels would cancel in mono; use only the right channel to
    // verify that waveform generation inspects every source channel.
    bytes.setInt16(44 + i * 4, 0, Endian.little);
    bytes.setInt16(46 + i * 4, sample, Endian.little);
  }
  File(file).writeAsBytesSync(bytes.buffer.asUint8List());
}

Future<void> main(List<String> arguments) async {
  final directory = path.absolute(arguments[0]),
      fixtures = Directory(path.absolute(arguments[1]));
  fixtures.createSync(recursive: true);
  final file = path.join(fixtures.path, 'envelope.wav');
  makeFixture(file);
  final waveform = await analyzeWaveform(directory, file);
  check(
      (waveform.duration - 8).abs() < .0001, 'Wrong decoded waveform duration');
  double average(int from, int to) =>
      waveform.peaks.sublist(from, to).reduce((a, b) => a + b) / (to - from);
  check(average(20, 280) > 13 && average(20, 280) < 18,
      'Quiet segment amplitude lost');
  check(average(320, 580) > 250, 'Loud segment amplitude lost');
  check(average(620, 880) == 0, 'Silence contains invented peaks');
  check(average(920, 1180) > 60 && average(920, 1180) < 68,
      'Relative waveform level is wrong');
  print(
      'PASS actual PCM waveform: 1200 columns, 8 seconds, quiet/loud/silent/medium sections, right channel preserved');
  var cancelled = false;
  try {
    await analyzeWaveform(directory, file, cancelled: () => true);
  } catch (_) {
    cancelled = true;
  }
  check(cancelled, 'Waveform cancellation was ignored');
  print('PASS waveform cancellation frees decoder');

  final library = DynamicLibrary.open(path.join(directory, 'BASS', 'bass.dll'));
  final bass = b.Bass(library),
      extras = BassExtras(library),
      reader = SpectrumReader();
  check(bass.BASS_Init(0, 48000, 0, nullptr, nullptr) != 0,
      'Cannot initialize no-output test device');
  int create({bool decode = true}) {
    final name = file.toNativeUtf16();
    try {
      return bass.BASS_StreamCreateFile(
          0,
          name.cast(),
          0,
          0,
          b.BASS_UNICODE |
              b.BASS_SAMPLE_FLOAT |
              (decode ? b.BASS_STREAM_DECODE : 0));
    } finally {
      calloc.free(name);
    }
  }

  var stream = create();
  try {
    check(stream != 0, 'Cannot open FFT test decoder');
    List<double> readAt(double seconds) {
      bass.BASS_ChannelSetPosition(stream,
          bass.BASS_ChannelSeconds2Bytes(stream, seconds), b.BASS_POS_BYTE);
      return reader.read(
          (buffer, flags) => extras.data(stream, buffer, flags), 48000);
    }

    final low = readAt(.5), high = readAt(2.5), silent = readAt(4.5);
    int peak(List<double> values) => values.indexOf(values.reduce(math.max));
    check(low.reduce(math.max) > .35 && high.reduce(math.max) > .7,
        'FFT magnitude not captured');
    check(peak(low) < peak(high), 'Frequency bands do not follow decoded tone');
    check(silent.every((value) => value == 0),
        'Silent FFT contains invented movement');
    print(
        'PASS native FFT: 440 Hz and 4 kHz occupy different bands; silence is zero');
  } finally {
    bass.BASS_StreamFree(stream);
  }

  stream = create(decode: false);
  try {
    check(bass.BASS_ChannelStart(stream) != 0,
        'Cannot start buffered no-output test channel');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final before = bass.BASS_ChannelBytes2Seconds(
        stream, bass.BASS_ChannelGetPosition(stream, b.BASS_POS_BYTE));
    final watch = Stopwatch()..start();
    for (var i = 0; i < 250; i++) {
      reader.read((buffer, flags) => extras.data(stream, buffer, flags), 48000);
    }
    final after = bass.BASS_ChannelBytes2Seconds(
        stream, bass.BASS_ChannelGetPosition(stream, b.BASS_POS_BYTE));
    check(after - before <= watch.elapsedMilliseconds / 1000 + .1,
        'FFT advanced buffered playback');
    print('PASS 250 FFT reads do not consume or skip buffered playback');
  } finally {
    bass.BASS_StreamFree(stream);
  }

  final wasapiLibrary =
      DynamicLibrary.open(path.join(directory, 'BASS', 'basswasapi.dll'));
  final wasapi = w.BassWasapi(wasapiLibrary);
  final getData = wasapiLibrary.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('BASS_WASAPI_GetData');
  stream = create();
  // Silent output while checking the real exclusive-device buffering path.
  bass.BASS_ChannelSetAttribute(stream, b.BASS_ATTRIB_VOLDSP, 0);
  final initialized = wasapi.BASS_WASAPI_Init(-1, 48000, 2, 1 | 16 | 4, .05, 0,
      Pointer<w.WASAPIPROC>.fromAddress(-1), Pointer<Void>.fromAddress(stream));
  try {
    if (initialized != 0) {
      check(wasapi.BASS_WASAPI_Start() != 0,
          'Cannot start exclusive test output');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = bass.BASS_ChannelBytes2Seconds(
          stream, bass.BASS_ChannelGetPosition(stream, b.BASS_POS_BYTE));
      final watch = Stopwatch()..start();
      for (var i = 0; i < 250; i++) {
        reader.read(getData, 48000);
      }
      final after = bass.BASS_ChannelBytes2Seconds(
          stream, bass.BASS_ChannelGetPosition(stream, b.BASS_POS_BYTE));
      check(after - before <= watch.elapsedMilliseconds / 1000 + .15,
          'Exclusive FFT consumed source PCM');
      print(
          'PASS exclusive WASAPI: 250 buffered FFT reads do not consume source PCM');
    } else {
      print(
          'SKIP exclusive-device check: device unavailable (${bass.BASS_ErrorGetCode()})');
    }
  } finally {
    if (initialized != 0) wasapi.BASS_WASAPI_Free();
    bass.BASS_StreamFree(stream);
    wasapiLibrary.close();
    reader.dispose();
    bass.BASS_Free();
    library.close();
  }
  print('ALL VISUAL AUDIO CHECKS PASSED');
}
