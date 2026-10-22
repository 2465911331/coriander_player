import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/play_service/waveform_cache.dart';
import 'package:coriander_player/play_service/waveform_model.dart';
import 'package:coriander_player/src/bass/analysis_queue.dart';
import 'package:coriander_player/src/bass/waveform_worker.dart';

class WaveformService {
  static final instance = WaveformService();
  late final _cache = WaveformCache(
      directory: () async =>
          path.join((await getAppDataDir()).path, 'waveform_cache'),
      analyze: _analyze);
  bool _closed = false;
  SendPort? _commands;
  Isolate? _worker;
  Completer<WaveformData>? _active;

  Future<WaveformData?> load(String file) =>
      _closed ? Future.value(null) : _cache.load(file);
  Future<WaveformData> _analyze(String file) =>
      AudioAnalysisQueue.instance.run(() async {
        if (_closed) throw StateError('Player is closing');
        final port = ReceivePort(), completion = Completer<WaveformData>();
        _active = completion;
        final subscription = port.listen((message) {
          if (completion.isCompleted) return;
          if (message is SendPort) {
            _commands = message;
            if (_closed) message.send('cancel');
            return;
          }
          final result =
              message is Map ? WaveformData.fromJson(message['result']) : null;
          if (result != null) {
            completion.complete(result);
          } else {
            completion.completeError(StateError('Waveform analysis failed'));
          }
        });
        try {
          _worker = await Isolate.spawn(runWaveformWorker,
              (port.sendPort, path.dirname(Platform.resolvedExecutable), file),
              onError: port.sendPort, onExit: port.sendPort);
          return await completion.future;
        } finally {
          _worker = null;
          _active = null;
          _commands = null;
          await subscription.cancel();
          port.close();
        }
      });
  Future<void> close() async {
    _closed = true;
    _commands?.send('cancel');
    final active = _active;
    if (active == null) return;
    try {
      await active.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      _worker?.kill(priority: Isolate.immediate);
      if (!active.isCompleted)
        active.completeError(StateError('Player is closing'));
    }
  }
}
