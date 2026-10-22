// ignore_for_file: constant_identifier_names

import 'package:coriander_player/src/bass/spectrum_reader.dart';

import 'dart:async';
import 'dart:io';
import 'package:coriander_player/src/bass/audio_native.dart';
import 'package:coriander_player/src/bass/gapless_mixer.dart';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/src/bass/bass_wasapi.dart' as BASS;
import 'package:coriander_player/utils.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/bass.dart' as BASS;
import 'dart:ffi' as ffi;

enum PlayerState {
  /// stop() has been called or the end of an audio has been reached
  stopped,

  /// start() has been called
  playing,

  /// pause() has been called
  paused,

  /// BASS_Pause() has been called or stopping unexpectedly (eg. a USB soundcard being disconnected).
  /// In either case, playback will be resumed by BASS_Start.
  pausedDevice,

  ///Playback of the stream has been stalled due to a lack of sample data.
  ///Playback will automatically resume once there is sufficient data to do so.
  stalled,

  /// the end of an audio has been reached
  completed,

  unknown,
}

const BASS_PLUGINS = [
  "BASS\\bassape.dll",
  "BASS\\bassdsd.dll",
  "BASS\\bassflac.dll",
  "BASS\\bassmidi.dll",
  "BASS\\bassopus.dll",
  "BASS\\basswv.dll"
];

class BassPlayer {
  late final ffi.DynamicLibrary _bassLib;
  late final ffi.DynamicLibrary _bassWasapiLib;
  late final BASS.Bass _bass;
  late final BASS.BassWasapi _bassWasapi;
  late final BassExtras _extras;
  ffi.DynamicLibrary? _mixLib;
  BassMix? _mix;
  GaplessMixer? _gapless;
  SpectrumReader? _spectrumReader;
  final _spectrumInfo = ffi.calloc<BassChannelInfo>();
  late final _wasapiData = _bassWasapiLib.lookupFunction<
      ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, int)>('BASS_WASAPI_GetData');

  List<double> readSpectrum() {
    final handle = _fstream;
    if (handle == null || playerState != PlayerState.playing) return const [];
    if (_extras.info(handle, _spectrumInfo) == 0) return const [];
    final reader = _spectrumReader ??= SpectrumReader();
    // A decoding source must never be read for visualization: that would
    // consume audible PCM. Exclusive output exposes a separate buffered tap.
    return reader.read(
        wasapiExclusive
            ? _wasapiData
            : (buffer, flags) => _extras.data(handle, buffer, flags),
        _spectrumInfo.ref.frequency.toDouble());
  }

  bool gaplessEnabled = true;
  double _userVolume = 1;
  double _normalizationGain = 1;
  final _trackTransitions = StreamController<int>.broadcast();
  Stream<int> get trackTransitions => _trackTransitions.stream;
  bool get usingGapless => _gapless != null;

  String? _fPath;
  int? _fstream;

  /// 是否启用 wasapi 独占模式
  bool wasapiExclusive = false;

  Timer? _positionUpdater;
  final _positionStreamController = StreamController<double>.broadcast();
  final _playerStateStreamController =
      StreamController<PlayerState>.broadcast();

  /// audio's length in seconds
  double get length =>
      _gapless?.length ??
      (_fstream == null
          ? 1.0
          : _bass.BASS_ChannelBytes2Seconds(_fstream!,
              _bass.BASS_ChannelGetLength(_fstream!, BASS.BASS_POS_BYTE)));

  /// current position in seconds
  double get position =>
      _gapless?.position ??
      (_fstream == null
          ? 0.0
          : _bass.BASS_ChannelBytes2Seconds(_fstream!,
              _bass.BASS_ChannelGetPosition(_fstream!, BASS.BASS_POS_BYTE)));

  PlayerState get playerState {
    if (_fstream == null) {
      return PlayerState.unknown;
    }

    switch (_bass.BASS_ChannelIsActive(_fstream!)) {
      case BASS.BASS_ACTIVE_STOPPED:
        return PlayerState.stopped;
      case BASS.BASS_ACTIVE_PLAYING:
        if (wasapiExclusive) {
          /// wasapi exclusive's channel is a decoding channel,
          /// will be BASS_ACTIVE_PLAYING as long as there is still data to decode.
          /// So here we check BASS_WASAPI_IsStarted to
          /// judge between BASS_ACTIVE_PLAYING and BASS_ACTIVE_PAUSED
          return _bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE
              ? PlayerState.playing
              : PlayerState.paused;
        }
        return PlayerState.playing;
      case BASS.BASS_ACTIVE_PAUSED:
        return PlayerState.paused;
      case BASS.BASS_ACTIVE_PAUSED_DEVICE:
        return PlayerState.pausedDevice;
      case BASS.BASS_ACTIVE_STALLED:
        return PlayerState.stalled;
      default:
        return PlayerState.unknown;
    }
  }

  double get volumeDsp {
    return _userVolume;
  }

  /// update every 33ms
  Stream<double> get positionStream => _positionStreamController.stream;

  Stream<PlayerState> get playerStateStream =>
      _playerStateStreamController.stream;

  Timer _getPositionUpdater() {
    return Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        final transition = _gapless?.poll();
        if (transition != null) {
          _trackTransitions.add(transition);
        }
        _positionStreamController.add(position);

        /// check if the channel has completed
        if (playerState == PlayerState.stopped) {
          timer.cancel();
          _playerStateStreamController.add(PlayerState.completed);
        }
      },
    );
  }

  void _bassInit() {
    if (_bass.BASS_Init(
            1, 48000, BASS.BASS_DEVICE_REINIT, ffi.nullptr, ffi.nullptr) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_DEVICE:
          throw const FormatException("device is invalid.");
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The BASS_DEVICE_REINIT flag cannot be used when device is -1. Use the real device number instead.");
        case BASS.BASS_ERROR_ALREADY:
          throw const FormatException(
              "The device has already been initialized. The BASS_DEVICE_REINIT flag can be used to request reinitialization.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException("win is not a valid window handle.");
        case BASS.BASS_ERROR_DRIVER:
          throw const FormatException("There is no available device driver.");
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "Something else has exclusive use of the device.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException(
              "The specified format is not supported by the device. Try changing the freq parameter.");
        case BASS.BASS_ERROR_MEM:
          throw const FormatException("There is insufficient memory.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException(
              "Some other mystery problem! Maybe Something else has exclusive use of the device.");
      }
    }
  }

  void _startDevice() {
    if (_bass.BASS_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _startDevice();
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The app's audio has been interrupted and cannot be resumed yet. (iOS only)");
        case BASS.BASS_ERROR_REINIT:
          throw const FormatException(
              "The device is currently being reinitialized or needs to be.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException(
              "Some other mystery problem! Maybe Something else has exclusive use of the device.");
      }
    }
  }

  /// load bass.dll from the exe's path\\BASS
  /// ensure that there's bass.dll at path of .exe\\BASS
  /// leave the device's output freq as it is
  BassPlayer() {
    final bassLibPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "bass.dll",
    );
    _bassLib = ffi.DynamicLibrary.open(bassLibPath);
    _bass = BASS.Bass(_bassLib);
    _extras = BassExtras(_bassLib);
    try {
      _mixLib = ffi.DynamicLibrary.open(path.join(
          path.dirname(Platform.resolvedExecutable), 'BASS', 'bassmix.dll'));
      _mix = BassMix(_mixLib!);
    } catch (error) {
      LOGGER.e('Continuous output is unavailable: $error');
    }

    final bassWasapiLibPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "basswasapi.dll",
    );
    _bassWasapiLib = ffi.DynamicLibrary.open(bassWasapiLibPath);
    _bassWasapi = BASS.BassWasapi(_bassWasapiLib);

    // load add-ons to avoid using os codec or support more format
    for (final plugin in BASS_PLUGINS) {
      final pluginPathP = plugin.toNativeUtf16() as ffi.Pointer<ffi.Char>;
      final hplugin = _bass.BASS_PluginLoad(pluginPathP, BASS.BASS_UNICODE);
      ffi.malloc.free(pluginPathP);

      if (hplugin == 0) {
        switch (_bass.BASS_ErrorGetCode()) {
          case BASS.BASS_ERROR_FILEOPEN:
            throw const FormatException("The file could not be opened.");
          case BASS.BASS_ERROR_FILEFORM:
            throw const FormatException("The file is not a plugin.");
          case BASS.BASS_ERROR_VERSION:
            throw const FormatException(
                "The plugin requires a different BASS version.");
          case BASS.BASS_ERROR_ALREADY:
            throw const FormatException("The plugin is already loaded.");
        }
      }
    }

    try {
      _bassInit();
    } catch (err) {
      LOGGER.e("[bass init] $err");
    }
  }

  /// true: 操作成功；false: 操作失败
  bool useExclusiveMode(bool exclusive) {
    final prevState = wasapiExclusive;
    try {
      final lastPos = position;
      final wasPlaying = playerState == PlayerState.playing;
      final gain = _normalizationGain;
      final token = _gapless?.token ?? 0;
      if (prevState) {
        _bassWasapi.BASS_WASAPI_Free();
        _bassInit();
      }
      wasapiExclusive = exclusive;
      if (_fstream != null && _fPath != null) {
        setSource(_fPath!, token: token, normalizationGain: gain);
        setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
        seek(lastPos);
        if (wasPlaying) start();
      }
      return true;
    } catch (err) {
      LOGGER.e("[use exclusive mode] $err");
      showTextOnSnackBar(err.toString());
    }
    wasapiExclusive = prevState;
    return false;
  }

  /// if setSource has been called once,
  /// it will pause current channel and free current stream.
  void setSource(String path, {int token = 0, double normalizationGain = 1}) {
    if (_fstream != null) {
      _positionUpdater?.cancel();
      freeFStream();
    }
    _normalizationGain = normalizationGain;
    if (gaplessEnabled && !wasapiExclusive && _mix != null) {
      final mixer = GaplessMixer(_bass, _mix!, _extras);
      try {
        mixer.setVolume(_userVolume);
        mixer.append(GaplessTrack(path, token, gain: normalizationGain));
        _gapless = mixer;
        _fstream = mixer.handle;
        _fPath = path;
        return;
      } catch (_) {
        mixer.close();
        rethrow;
      }
    }
    final pathPointer = path.toNativeUtf16() as ffi.Pointer<ffi.Void>;

    /// 设置 flags 为 BASS_UNICODE 才可以找到文件。
    const flags =
        BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT | BASS.BASS_ASYNCFILE;
    const exclusiveFlags = flags | BASS.BASS_STREAM_DECODE;
    late final int handle;
    try {
      handle = _bass.BASS_StreamCreateFile(
        BASS.FALSE,
        pathPointer,
        0,
        0,
        wasapiExclusive ? exclusiveFlags : flags,
      );
    } finally {
      ffi.malloc.free(pathPointer);
    }

    if (handle != 0) {
      _fstream = handle;
      _fPath = path;
    } else {
      _fstream = null;
      _fPath = null;
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          setSource(path);
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The BASS_STREAM_AUTOFREE flag cannot be combined with the BASS_STREAM_DECODE flag.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException(
              "The length must be specified when streaming from memory.");
        case BASS.BASS_ERROR_FILEOPEN:
          throw const FormatException("The file could not be opened.");
        case BASS.BASS_ERROR_FILEFORM:
          throw const FormatException(
              "The file's format is not recognised/supported.");
        case BASS.BASS_ERROR_NOTAUDIO:
          throw const FormatException(
              "The file does not contain audio, or it also contains video and videos are disabled.");
        case BASS.BASS_ERROR_CODEC:
          throw const FormatException(
              "The file uses a codec that is not available/supported. This can apply to WAV and AIFF files.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException("The sample format is not supported.");
        case BASS.BASS_ERROR_SPEAKER:
          throw const FormatException(
              "The specified SPEAKER flags are invalid.");
        case BASS.BASS_ERROR_MEM:
          throw const FormatException("There is insufficient memory.");
        case BASS.BASS_ERROR_NO3D:
          throw const FormatException("Could not initialize 3D support.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  /// [BASS_ATTRIB_VOLDSP] attribute does have direct effect on decoding/recording channels.
  void setVolumeDsp(double volume) {
    _userVolume = volume;
    if (_gapless != null) {
      _gapless!.setVolume(volume);
      return;
    }
    if (_fstream == null) return;

    if (_bass.BASS_ChannelSetAttribute(
          _fstream!,
          BASS.BASS_ATTRIB_VOLDSP,
          volume * _normalizationGain,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_ILLTYPE:
          throw const FormatException("attrib is not valid.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException("value is not valid.");
      }
    }
  }

  void updateNormalization(double gain, double Function(GaplessTrack) gainFor) {
    _normalizationGain = gain;
    if (_gapless != null) {
      _gapless!.updateGains(gainFor);
    } else {
      setVolumeDsp(_userVolume);
    }
  }

  void prepareNext(List<GaplessTrack> tracks) {
    final mixer = _gapless;
    if (mixer == null) return;
    final pending = mixer.pending;
    final common = pending.length <= tracks.length &&
        List.generate(
            pending.length,
            (i) =>
                pending[i].path == tracks[i].path &&
                pending[i].token == tracks[i].token).every((v) => v);
    if (!common) {
      // A user queue edit may invalidate already-buffered audio. Rebuild from
      // the audible position, preserving pause state, rather than playing an
      // obsolete next song from that buffer.
      final wasPlaying = playerState == PlayerState.playing;
      final position = this.position;
      final token = mixer.token;
      final currentPath = _fPath!;
      setSource(currentPath,
          token: token, normalizationGain: _normalizationGain);
      seek(position);
      for (final track in tracks) {
        _gapless!.append(track);
      }
      if (wasPlaying) start();
      return;
    }
    for (final track in tracks.skip(pending.length)) {
      mixer.append(track);
    }
  }

  void acknowledgeTransition(String filePath) {
    _fPath = filePath;
  }

  void _bassWasapiInit() {
    if (_bassWasapi.BASS_WASAPI_Init(
          -1,
          0,
          0,
          BASS.BASS_WASAPI_EXCLUSIVE | BASS.BASS_WASAPI_EVENT | 4,
          0.05,
          0,
          ffi.Pointer<BASS.WASAPIPROC>.fromAddress(-1),
          ffi.Pointer<ffi.Void>.fromAddress(_fstream!),
        ) ==
        BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_WASAPI:
          throw const FormatException("WASAPI is not available.");
        case BASS.BASS_ERROR_DEVICE:
          throw const FormatException("device is invalid.");
        case BASS.BASS_ERROR_ALREADY:
          _bassWasapi.BASS_WASAPI_Free();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Exclusive mode and/or event-driven buffering is unavailable on the device, or WASAPIPROC_PUSH is unavailable on input devices and when using event-driven buffering.");
        case BASS.BASS_ERROR_DRIVER:
          throw const FormatException("The driver could not be initialized.");
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException(
              "The BASS channel handle in user is invalid, or not of the required type.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException(
              "The specified format (or that of the BASS channel) is not supported by the device. If the BASS_WASAPI_AUTOFORMAT flag was specified, no other format could be found either.");
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is already in use, eg. another process may have initialized it in exclusive mode.");
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_WASAPI_BUFFER:
          throw const FormatException(
              "buffer is too large or small (exclusive mode only).");
        case BASS.BASS_ERROR_WASAPI_CATEGORY:
          throw const FormatException(
              "The category/raw mode could not be set.");
        case BASS.BASS_ERROR_WASAPI_DENIED:
          throw const FormatException(
              "Access to the device is denied. This could be due to privacy settings.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  void _start_wasapiExclusive() {
    _bassWasapiInit();

    if (_bassWasapi.BASS_WASAPI_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassWasapiInit();
          return _start_wasapiExclusive();
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
    _playerStateStreamController.add(playerState);
    _positionUpdater?.cancel();
    _positionUpdater = _getPositionUpdater();
  }

  /// start/resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void start() {
    if (_fstream == null) return;

    if (wasapiExclusive) {
      return _start_wasapiExclusive();
    }
    if (_bass.BASS_ChannelStart(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played.");
        case BASS.BASS_ERROR_START:
          _startDevice();
          return start();
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater?.cancel();
    _positionUpdater = _getPositionUpdater();
  }

  void _pause_wasapiExclusive() {
    if (_bassWasapi.BASS_WASAPI_Stop(BASS.FALSE) == BASS.TRUE) {
      _playerStateStreamController.add(playerState);
      _positionUpdater?.cancel();
    }
  }

  /// pause channel, call [start] to resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void pause() {
    if (_fstream == null) return;

    if (wasapiExclusive) {
      return _pause_wasapiExclusive();
    }

    if (_bass.BASS_ChannelPause(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played or paused.");
        case BASS.BASS_ERROR_NOPLAY:
          throw const FormatException("The channel is not playing.");
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater?.cancel();
  }

  /// set channel's position to given [position]
  /// don't check if the position is valid.
  ///
  /// do nothing if [setSource] hasn't been called
  void seek(double position) {
    if (_fstream == null) return;
    if (_gapless != null) {
      final old = _gapless!;
      final token = old.token;
      final pending = old.pending;
      final wasPlaying = playerState == PlayerState.playing;
      final currentPath = _fPath!;
      final gain = _normalizationGain;
      _positionUpdater?.cancel();
      old.close();
      _gapless = null;
      _fstream = null;
      final mixer = GaplessMixer(_bass, _mix!, _extras);
      try {
        mixer.setVolume(_userVolume);
        mixer.append(GaplessTrack(currentPath, token, gain: gain),
            offset: position);
        for (final track in pending) {
          mixer.append(track);
        }
        _gapless = mixer;
        _fstream = mixer.handle;
        if (wasPlaying) start();
      } catch (_) {
        mixer.close();
        rethrow;
      }
      return;
    }

    if (_bass.BASS_ChannelSetPosition(
          _fstream!,
          _bass.BASS_ChannelSeconds2Bytes(_fstream!, position),
          BASS.BASS_POS_BYTE,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_NOTFILE:
          throw const FormatException("The stream is not a file stream.");
        case BASS.BASS_ERROR_POSITION:
          throw const FormatException(
              "The requested position is invalid, eg. it is beyond the end or the download has not yet reached it.");
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The requested mode is not available. Invalid flags are ignored and do not result in this error.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  /// It is not necessary to individually free the samples/streams/musics
  /// as these are all automatically freed after [setSource] or [free] is called.
  ///
  /// do nothing if [setSource] hasn't been called
  void freeFStream() {
    if (_fstream == null) return;
    if (_gapless != null) {
      _gapless!.close();
      _gapless = null;
      _fstream = null;
      return;
    }

    if (_bass.BASS_StreamFree(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          LOGGER.w("StreamFree is called on a invalid handle.");
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Device streams (STREAMPROC_DEVICE) cannot be freed.");
      }
    }
    _fstream = null;
  }

  /// Frees all resources used by the output device,
  /// including all its samples, streams and MOD musics.
  ///
  /// Also free the bass.dll.
  void free() {
    _positionUpdater?.cancel();
    _gapless?.close();
    _gapless = null;
    if (wasapiExclusive) {
      _bassWasapi.BASS_WASAPI_Free();
    }

    if (_bass.BASS_Free() == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          LOGGER.w("BASS_Free is called before BASS_Init complete normally.");
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is currently being reinitialized.");
      }
    }

    _spectrumReader?.dispose();
    ffi.calloc.free(_spectrumInfo);
    _bassWasapiLib.close();
    _mixLib?.close();
    _bassLib.close();

    _positionUpdater?.cancel();
    _playerStateStreamController.close();
    _positionStreamController.close();
    _trackTransitions.close();
  }
}
