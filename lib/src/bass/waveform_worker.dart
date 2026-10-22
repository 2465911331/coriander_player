import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/bass.dart' as b;
import 'package:coriander_player/src/bass/audio_native.dart';
import 'package:coriander_player/play_service/waveform_model.dart';

void runWaveformWorker((SendPort, String, String) request) async {
  final commands = ReceivePort();
  var cancelled = false;
  commands.listen((_) => cancelled = true);
  request.$1.send(commands.sendPort);
  try {
    final data = await analyzeWaveform(request.$2, request.$3,
        cancelled: () => cancelled);
    request.$1.send({'result': data.toJson()});
  } catch (error) {
    request.$1.send({'error': error.toString()});
  } finally {
    commands.close();
  }
}

Future<WaveformData> analyzeWaveform(String directory, String file,
    {bool Function()? cancelled}) async {
  final library = DynamicLibrary.open(path.join(directory, 'BASS', 'bass.dll'));
  final bass = b.Bass(library), extras = BassExtras(library);
  var initialized = false;
  var stream = 0;
  final info = calloc<BassChannelInfo>();
  Pointer<Float> buffer = nullptr;
  try {
    if (bass.BASS_Init(0, 48000, 0, nullptr, nullptr) != 0) {
      initialized = true;
    } else if (bass.BASS_ErrorGetCode() != b.BASS_ERROR_ALREADY) {
      throw StateError('Cannot initialize waveform decoder');
    }
    if (extras.setDevice(0) == 0)
      throw StateError('Cannot select waveform decoder');
    for (final plugin in [
      'bassape',
      'bassdsd',
      'bassflac',
      'bassmidi',
      'bassopus',
      'basswv'
    ]) {
      final name = path.join(directory, 'BASS', '$plugin.dll').toNativeUtf16();
      try {
        bass.BASS_PluginLoad(name.cast(), b.BASS_UNICODE);
      } finally {
        calloc.free(name);
      }
    }
    final name = file.toNativeUtf16();
    try {
      stream = bass.BASS_StreamCreateFile(
          0,
          name.cast(),
          0,
          0,
          b.BASS_UNICODE |
              b.BASS_SAMPLE_FLOAT |
              b.BASS_STREAM_DECODE |
              0x20000);
    } finally {
      calloc.free(name);
    }
    if (stream == 0 || extras.info(stream, info) == 0)
      throw StateError('Cannot decode waveform');
    final channels = info.ref.channels, frequency = info.ref.frequency;
    final bytes = bass.BASS_ChannelGetLength(stream, b.BASS_POS_BYTE);
    if (channels < 1 ||
        channels > 32 ||
        frequency < 1 ||
        bytes == 0xffffffffffffffff ||
        bytes < channels * 4) {
      throw StateError('Invalid waveform duration');
    }
    final accumulator = WaveformAccumulator(bytes ~/ (channels * 4), channels);
    buffer = calloc<Float>(8192 * channels);
    final samples = buffer.asTypedList(8192 * channels);
    var blocks = 0;
    while (true) {
      if (cancelled?.call() == true) throw StateError('Waveform cancelled');
      final read = extras.data(stream, buffer.cast(), samples.length * 4);
      if (read == 0 || read == 0xffffffff) {
        if (read == 0xffffffff && bass.BASS_ErrorGetCode() != 45)
          throw StateError('Waveform decode failed');
        break;
      }
      accumulator.add(samples, read ~/ 4);
      if (++blocks % 16 == 0)
        await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (accumulator.frames == 0) throw StateError('Empty waveform');
    return WaveformData(accumulator.frames / frequency, accumulator.finish());
  } finally {
    // An async isolate may resume on a different native thread. BASS's device
    // selection is thread-local: explicitly select 0 before freeing resources.
    extras.setDevice(0);
    if (stream != 0) bass.BASS_StreamFree(stream);
    if (initialized) bass.BASS_Free();
    if (buffer != nullptr) calloc.free(buffer);
    calloc.free(info);
    library.close();
  }
}
