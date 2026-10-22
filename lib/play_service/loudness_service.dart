import 'package:coriander_player/src/bass/analysis_queue.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/loudness_model.dart';
import 'package:coriander_player/src/bass/loudness_worker.dart';
import 'package:coriander_player/storage/safe_json.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

String loudnessAlbumKey(Audio audio) =>
    '${path.windows.dirname(audio.path).toLowerCase()}|${audio.album.trim().toLowerCase()}';

class LoudnessService extends ChangeNotifier {
  static final instance = LoudnessService();
  final Map<String, Map> _tracks = {};
  final Map<String, Map> _albums = {};
  final Map<String, List<Audio>> _groups = {};
  final Map<String, (DateTime, String)> _albumChecks = {};
  int _libraryRevision = -1;
  final Map<String, Future<void>> _pending = {};
  Future<void> _tail = Future.value();
  Timer? _saveTimer;
  Isolate? _worker;
  Completer<Map>? _activeJob;
  bool _closed = false;
  bool _dirty = false;
  bool isScanning = false;
  int completed = 0, total = 0, failed = 0;
  int _scanToken = 0;
  String status = '首次播放时自动分析，也可提前分析音乐库';
  bool get isBusy => isScanning || _pending.isNotEmpty;
  int get cachedCount => _tracks.length;
  Future<String> get _cachePath async =>
      path.join((await getAppDataDir()).path, 'loudness_cache.json');

  static String _identity(Audio audio) =>
      path.windows.normalize(audio.path).toLowerCase();
  static String _signature(Audio audio) {
    try {
      final stat = File(audio.path).statSync();
      return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return 'missing';
    }
  }

  static String _groupSignature(List<Audio> audios) {
    final signatures =
        audios.map((a) => '${_identity(a)}:${_signature(a)}').toList()..sort();
    return signatures.join('|');
  }

  Future<void> init() async {
    try {
      final cache = await readJsonSafely(await _cachePath, {}) as Map;
      if (cache['version'] != 1) return;
      _tracks.addAll(Map<String, Map>.from(cache['tracks'] as Map? ?? {}));
      _albums.addAll(Map<String, Map>.from(cache['albums'] as Map? ?? {}));
    } catch (error, stack) {
      LOGGER.e('Unable to read loudness cache: $error', stackTrace: stack);
    }
  }

  List<Audio> _album(Audio audio) {
    if (_libraryRevision != AudioLibrary.revision.value) {
      _groups.clear();
      _albumChecks.clear();
      for (final item in AudioLibrary.instance.audioCollection) {
        _groups.putIfAbsent(loudnessAlbumKey(item), () => []).add(item);
      }
      _libraryRevision = AudioLibrary.revision.value;
    }
    return _groups[loudnessAlbumKey(audio)] ?? [audio];
  }

  String _checkedAlbumSignature(Audio audio, List<Audio> group) {
    final key = loudnessAlbumKey(audio);
    final now = DateTime.now();
    final cached = _albumChecks[key];
    if (cached != null && now.difference(cached.$1).inMilliseconds < 1000)
      return cached.$2;
    final signature = _groupSignature(group);
    _albumChecks[key] = (now, signature);
    return signature;
  }

  double gainFor(Audio audio) {
    final mode = AppSettings.instance.normalizationMode;
    if (mode == NormalizationMode.off) return 1;
    try {
      Map? entry;
      if (mode == NormalizationMode.album) {
        final group = _album(audio);
        final album = _albums[loudnessAlbumKey(audio)];
        if (album?['signature'] == _checkedAlbumSignature(audio, group))
          entry = album;
      } else {
        final track = _tracks[_identity(audio)];
        if (track?['signature'] == _signature(audio)) entry = track;
      }
      return entry == null
          ? 1
          : LoudnessMeasurement.fromJson(entry['measurement'] as Map).gain();
    } catch (_) {
      return 1;
    }
  }

  Future<void> ensureFor(Audio audio) async {
    if (_closed ||
        AppSettings.instance.normalizationMode == NormalizationMode.off) return;
    final album =
        AppSettings.instance.normalizationMode == NormalizationMode.album;
    final group = album ? _album(audio) : [audio];
    if (group.isEmpty) return;
    await _enqueue(group, albumKey: album ? loudnessAlbumKey(audio) : null);
  }

  Future<void> _enqueue(List<Audio> audios, {String? albumKey}) {
    if (_closed) return Future.value();
    final signature = _groupSignature(audios);
    final trackSignatures = {
      for (final audio in audios) _identity(audio): _signature(audio)
    };
    if (albumKey != null && _albums[albumKey]?['signature'] == signature)
      return Future.value();
    if (albumKey == null &&
        audios
            .every((a) => _tracks[_identity(a)]?['signature'] == _signature(a)))
      return Future.value();
    final key = '${albumKey ?? 'track'}:$signature';
    final pending = _pending[key];
    if (pending != null) return pending;
    final operation = _tail.then((_) async {
      if (_closed) return;
      if (_groupSignature(audios) != signature) return;
      status = '正在分析音乐音量…';
      notifyListeners();
      try {
        final result = await _runWorker(audios.map((a) => a.path).toList());
        if (_closed) return;
        final tracks = result['tracks'] as Map;
        for (final audio in audios) {
          final measurement = tracks[audio.path];
          if (measurement != null &&
              _signature(audio) == trackSignatures[_identity(audio)]) {
            _tracks[_identity(audio)] = {
              'signature': trackSignatures[_identity(audio)],
              'measurement': measurement
            };
          }
        }
        final errors = result['errors'] as List;
        failed += errors.length;
        // An incomplete album is never used as though it were complete.
        if (albumKey != null &&
            _groupSignature(audios) == signature &&
            errors.isEmpty &&
            tracks.length == audios.length) {
          _albums[albumKey] = {
            'signature': signature,
            'measurement': result['album']
          };
          _albumChecks.remove(albumKey);
        }
        _dirty = true;
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 500), () async {
          try {
            await save();
          } catch (error) {
            LOGGER.e('Unable to save loudness cache: $error');
          }
        });
        status =
            errors.isEmpty ? '音量分析完成，已缓存 $_cachedText' : '部分歌曲无法分析，播放时保持原始音量';
      } catch (error, stack) {
        if (!_closed) {
          failed += audios.length;
          status = '音量分析失败，播放时保持原始音量';
          LOGGER.e(error, stackTrace: stack);
        }
      } finally {
        if (!_closed) notifyListeners();
      }
    });
    _pending[key] = operation;
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    operation.then((_) {
      _pending.remove(key);
      if (!_closed) notifyListeners();
    });
    return operation;
  }

  String get _cachedText => '${_tracks.length} 首歌曲';

  Future<Map> _runWorker(List<String> files) =>
      AudioAnalysisQueue.instance.run(() {
        if (_closed) throw StateError('Player is closing');
        return _runWorkerNow(files);
      });

  Future<Map> _runWorkerNow(List<String> files) async {
    final port = ReceivePort();
    final completion = Completer<Map>();
    _activeJob = completion;
    final subscription = port.listen((message) {
      if (completion.isCompleted) return;
      if (message is Map && message['result'] is Map)
        completion.complete(message['result'] as Map);
      else
        completion.completeError(StateError(message.toString()));
    });
    try {
      final worker = await Isolate.spawn(runLoudnessWorker,
          (port.sendPort, path.dirname(Platform.resolvedExecutable), files),
          onError: port.sendPort, onExit: port.sendPort);
      _worker = worker;
      if (_closed) {
        worker.kill(priority: Isolate.immediate);
        throw StateError('Player is closing');
      }
      return await completion.future;
    } finally {
      _worker?.kill(priority: Isolate.immediate);
      _worker = null;
      _activeJob = null;
      await subscription.cancel();
      port.close();
    }
  }

  Future<void> analyzeLibrary() async {
    if (_closed || isScanning) return;
    isScanning = true;
    completed = 0;
    failed = 0;
    final token = ++_scanToken;
    final groups = <String, List<Audio>>{};
    for (final audio in AudioLibrary.instance.audioCollection) {
      groups.putIfAbsent(loudnessAlbumKey(audio), () => []).add(audio);
    }
    total = AudioLibrary.instance.audioCollection.length;
    notifyListeners();
    try {
      for (final group in groups.entries) {
        if (_closed || token != _scanToken) break;
        await _enqueue(group.value, albumKey: group.key);
        completed += group.value.length;
        if (!_closed) notifyListeners();
      }
    } finally {
      isScanning = false;
      if (!_closed) {
        status =
            token != _scanToken ? '已停止分析' : '分析完成：$completed 首，无法分析 $failed 首';
        notifyListeners();
      }
    }
  }

  void stopScan() {
    _scanToken++;
    status = '当前专辑分析完后停止';
    notifyListeners();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    try {
      await writeJsonSafely(await _cachePath,
          {'version': 1, 'tracks': _tracks, 'albums': _albums});
    } catch (_) {
      _dirty = true;
      rethrow;
    }
  }

  Future<void> close() async {
    _closed = true;
    _scanToken++;
    _worker?.kill(priority: Isolate.immediate);
    final job = _activeJob;
    if (job != null && !job.isCompleted)
      job.completeError(StateError('Player is closing'));
    try {
      await save();
    } catch (error, stack) {
      LOGGER.e('Unable to flush loudness cache: $error', stackTrace: stack);
    }
  }
}
