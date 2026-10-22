import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/bass.dart' as b;
import 'package:coriander_player/src/bass/audio_native.dart';

class Ebur128 {
  Ebur128(DynamicLibrary library) {
    init = library.lookupFunction<Pointer<Void> Function(Uint32, Uint32, Int32),
        Pointer<Void> Function(int, int, int)>('ebur128_init');
    destroy = library.lookupFunction<Void Function(Pointer<Pointer<Void>>),
        void Function(Pointer<Pointer<Void>>)>('ebur128_destroy');
    add = library.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Float>, Size),
        int Function(
            Pointer<Void>, Pointer<Float>, int)>('ebur128_add_frames_float');
    loudness = library.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Double>),
        int Function(
            Pointer<Void>, Pointer<Double>)>('ebur128_loudness_global');
    multiple = library.lookupFunction<
        Int32 Function(Pointer<Pointer<Void>>, Size, Pointer<Double>),
        int Function(Pointer<Pointer<Void>>, int,
            Pointer<Double>)>('ebur128_loudness_global_multiple');
    peak = library.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Double>),
        int Function(Pointer<Void>, int, Pointer<Double>)>('ebur128_true_peak');
  }
  late final Pointer<Void> Function(int, int, int) init;
  late final void Function(Pointer<Pointer<Void>>) destroy;
  late final int Function(Pointer<Void>, Pointer<Float>, int) add;
  late final int Function(Pointer<Void>, Pointer<Double>) loudness;
  late final int Function(Pointer<Pointer<Void>>, int, Pointer<Double>)
      multiple;
  late final int Function(Pointer<Void>, int, Pointer<Double>) peak;
}

/// This worker touches decoding channels on BASS's no-output device only.
/// Audio decoding and R128 analysis never run on Flutter's UI isolate.
void runLoudnessWorker((SendPort, String, List<String>) request) {
  try {
    request.$1.send({'result': analyzeLoudness(request.$2, request.$3)});
  } catch (error) {
    request.$1.send({'error': error.toString()});
  }
}

Map<String, Object?> analyzeLoudness(String directory, List<String> files) {
  final library = DynamicLibrary.open(path.join(directory, 'BASS', 'bass.dll'));
  final eburLibrary =
      DynamicLibrary.open(path.join(directory, 'coriander_loudness.dll'));
  final bass = b.Bass(library);
  final extra = BassExtras(library);
  final ebur = Ebur128(eburLibrary);
  // The no-output device belongs to this worker. Playback uses device 1.
  if (bass.BASS_Init(0, 48000, 0, nullptr, nullptr) == 0 &&
      bass.BASS_ErrorGetCode() != b.BASS_ERROR_ALREADY) {
    throw StateError('Cannot initialize analysis decoder');
  }
  final states = <Pointer<Void>>[];
  if (extra.setDevice(0) == 0)
    throw StateError('Cannot select no-output decoder');
  final info = calloc<BassChannelInfo>();
  final buffer = calloc<Float>(16384 * 8);
  final value = calloc<Double>();
  final holder = calloc<Pointer<Void>>();
  final tracks = <String, Object?>{};
  final errors = <String>[];
  var albumPeak = 0.0;
  try {
    // Load codecs in standalone tests too; repeated loads return ALREADY.
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
    for (final file in files) {
      final name = file.toNativeUtf16();
      int stream;
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
      if (stream == 0) {
        errors.add(file);
        continue;
      }
      Pointer<Void> state = nullptr;
      try {
        if (extra.info(stream, info) == 0 ||
            info.ref.channels < 1 ||
            info.ref.channels > 8)
          throw StateError('Unsupported channel layout');
        final channels = info.ref.channels;
        // Integrated loudness + true peak + bounded histogram storage.
        state = ebur.init(channels, info.ref.frequency, 1 | 4 | 16 | 32 | 64);
        if (state == nullptr)
          throw StateError('Cannot allocate loudness state');
        while (true) {
          final bytes = extra.data(stream, buffer.cast(), 16384 * channels * 4);
          if (bytes == 0xffffffff || bytes == 0) {
            if (bytes == 0xffffffff && bass.BASS_ErrorGetCode() != 45)
              throw StateError('Audio decode failed');
            break;
          }
          if (ebur.add(state, buffer, bytes ~/ (channels * 4)) != 0)
            throw StateError('Loudness analysis failed');
        }
        if (ebur.loudness(state, value) != 0)
          throw StateError('No loudness result');
        final lufs = value.value.isFinite ? value.value : null;
        var peak = 0.0;
        for (var channel = 0; channel < channels; channel++) {
          if (ebur.peak(state, channel, value) != 0)
            throw StateError('No peak result');
          peak = math.max(peak, value.value);
        }
        tracks[file] = {'lufs': lufs, 'peak': peak};
        albumPeak = math.max(albumPeak, peak);
        states.add(state);
        state = nullptr;
      } catch (_) {
        errors.add(file);
      } finally {
        bass.BASS_StreamFree(stream);
        if (state != nullptr) {
          holder.value = state;
          ebur.destroy(holder);
        }
      }
    }
    double? albumLufs;
    final pointers = calloc<Pointer<Void>>(math.max(1, states.length));
    try {
      for (var i = 0; i < states.length; i++) {
        pointers[i] = states[i];
      }
      if (states.isNotEmpty &&
          ebur.multiple(pointers, states.length, value) == 0 &&
          value.value.isFinite) albumLufs = value.value;
    } finally {
      calloc.free(pointers);
    }
    return {
      'tracks': tracks,
      'album': {'lufs': albumLufs, 'peak': albumPeak},
      'errors': errors
    };
  } finally {
    for (final state in states) {
      holder.value = state;
      ebur.destroy(holder);
    }
    calloc.free(holder);
    calloc.free(info);
    calloc.free(buffer);
    calloc.free(value);
    bass.BASS_Free();
    eburLibrary.close();
    library.close();
  }
}
