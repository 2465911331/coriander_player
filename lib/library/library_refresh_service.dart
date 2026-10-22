import 'dart:async';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/foundation.dart';

/// Updates the existing library without interrupting the playback queue.
class LibraryRefreshService extends ChangeNotifier {
  LibraryRefreshService({
    Future<String> Function()? dataDirectory,
    Stream<IndexActionState> Function(String)? scan,
    Future<void> Function(String)? reload,
  })  : _dataDirectory =
            dataDirectory ?? (() async => (await getAppDataDir()).path),
        _scan = scan ?? ((path) => updateIndex(indexPath: path)),
        _reload = reload ??
            ((path) => AudioLibrary.initFromIndex(
                throwOnError: true, dataDirectory: path));

  static final instance = LibraryRefreshService();
  final Future<String> Function() _dataDirectory;
  final Stream<IndexActionState> Function(String) _scan;
  final Future<void> Function(String) _reload;
  Future<void>? _pending;
  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  Future<void> refresh() {
    if (_pending != null) return _pending!;
    final completion = Completer<void>();
    _pending = completion.future;
    _refresh().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> _refresh() async {
    _isRefreshing = true;
    notifyListeners();
    try {
      final directory = await _dataDirectory();
      // Consume the entire scan, including errors, before reading its index.
      await for (final _ in _scan(directory)) {}
      await _reload(directory);
    } finally {
      _isRefreshing = false;
      _pending = null;
      notifyListeners();
    }
  }
}
