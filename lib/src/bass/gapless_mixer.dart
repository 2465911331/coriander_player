import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:coriander_player/src/bass/bass.dart' as b;
import 'package:coriander_player/src/bass/audio_native.dart';

class GaplessTrack {
  const GaplessTrack(this.path, this.token, {this.gain = 1});
  final String path;
  final int token;
  final double gain;
}

class _Segment {
  _Segment(this.track, this.handle, this.start, this.duration, this.offset);
  GaplessTrack track;
  final int handle;
  final double start, duration, offset;
  double get end => start + duration - offset;
}

/// BASSmix queues native decoding channels in a continuous output stream.
/// Dart polls only for UI changes; it never schedules the audio transition.
class GaplessMixer {
  GaplessMixer(this.bass, this.mix, this.extras, {this.decodeOutput = false}) {
    handle = mix.create(
        48000,
        2,
        b.BASS_SAMPLE_FLOAT |
            0x8000 |
            0x10000 |
            (decodeOutput ? b.BASS_STREAM_DECODE : 0));
    if (handle == 0)
      throw StateError(
          'Cannot create continuous output (${bass.BASS_ErrorGetCode()})');
  }
  final b.Bass bass;
  final BassMix mix;
  final BassExtras extras;
  final bool decodeOutput;
  late final int handle;
  final _segments = <_Segment>[];
  int _current = 0;
  double _volume = 1;
  bool _closed = false;

  double get timelinePosition {
    final bytes = bass.BASS_ChannelGetPosition(handle, b.BASS_POS_BYTE);
    return bytes == 0xffffffffffffffff
        ? 0
        : bass.BASS_ChannelBytes2Seconds(handle, bytes);
  }

  _Segment get _active => _segments[_current];
  double get length => _segments.isEmpty ? 1 : _active.duration;
  double get position => _segments.isEmpty
      ? 0
      : (timelinePosition - _active.start + _active.offset)
          .clamp(0, _active.duration);
  int get token => _active.track.token;
  List<GaplessTrack> get pending =>
      _segments.skip(_current + 1).map((s) => s.track).toList();

  void append(GaplessTrack track, {double offset = 0}) {
    final name = track.path.toNativeUtf16();
    int source;
    try {
      source = bass.BASS_StreamCreateFile(
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
    if (source == 0)
      throw StateError('Cannot prepare track (${bass.BASS_ErrorGetCode()})');
    try {
      final duration = bass.BASS_ChannelBytes2Seconds(
          source, bass.BASS_ChannelGetLength(source, b.BASS_POS_BYTE));
      if (!duration.isFinite || duration <= 0)
        throw StateError('Track has no playable duration');
      final seek = offset.clamp(0, math.max(0, duration - 0.0001)).toDouble();
      if (seek > 0 &&
          bass.BASS_ChannelSetPosition(
                  source,
                  bass.BASS_ChannelSeconds2Bytes(source, seek),
                  b.BASS_POS_BYTE) ==
              0) {
        throw StateError('Cannot seek prepared track');
      }
      bass.BASS_ChannelSetAttribute(
          source, b.BASS_ATTRIB_VOLDSP, _volume * track.gain);
      // Downmix multi-channel files; no ramp-in at seamless boundaries.
      if (mix.add(handle, source, 0x400000 | 0x800000) == 0)
        throw StateError('Cannot queue prepared track');
      _segments.add(_Segment(track, source,
          _segments.isEmpty ? 0 : _segments.last.end, duration, seek));
    } catch (_) {
      bass.BASS_StreamFree(source);
      rethrow;
    }
  }

  /// Return the last audible transition if several very short tracks elapsed.
  int? poll() {
    if (_segments.isEmpty) return null;
    final heard = timelinePosition;
    int? changed;
    while (_current + 1 < _segments.length && heard + 0.00001 >= _active.end) {
      final previous = _active;
      _current++;
      changed = _active.track.token;
      bass.BASS_StreamFree(previous.handle);
    }
    // Keep memory bounded without changing the absolute output timeline.
    if (_current > 16) {
      _segments.removeRange(0, _current);
      _current = 0;
    }
    return changed;
  }

  void setVolume(double value) {
    _volume = value;
    for (final segment in _segments.skip(_current)) {
      bass.BASS_ChannelSetAttribute(
          segment.handle, b.BASS_ATTRIB_VOLDSP, value * segment.track.gain);
    }
  }

  void updateGains(double Function(GaplessTrack) gainFor) {
    for (final segment in _segments.skip(_current)) {
      final gain = gainFor(segment.track);
      segment.track =
          GaplessTrack(segment.track.path, segment.track.token, gain: gain);
      bass.BASS_ChannelSetAttribute(
          segment.handle, b.BASS_ATTRIB_VOLDSP, _volume * gain);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // Stop/free the output before the decoding sources it may be using.
    bass.BASS_StreamFree(handle);
    for (final segment in _segments.skip(_current)) {
      bass.BASS_StreamFree(segment.handle);
    }
    _segments.clear();
  }
}
