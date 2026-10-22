import 'package:coriander_player/storage/safe_json.dart';
import 'package:path/path.dart' as path;

/// Stores file identities, so restored queues use the latest library metadata.
class PlaybackSession {
  const PlaybackSession({
    required this.paths,
    required this.originalPaths,
    required this.index,
    required this.position,
    required this.shuffle,
    required this.playMode,
    required this.volume,
  });

  final List<String> paths;
  final List<String> originalPaths;
  final int index;
  final double position;
  final bool shuffle;
  final String playMode;
  final double volume;

  Map<String, Object> toJson() => {
        'version': 1,
        'paths': paths,
        'originalPaths': originalPaths,
        'index': index,
        'position': position,
        'shuffle': shuffle,
        'playMode': playMode,
        'volume': volume,
      };

  factory PlaybackSession.fromJson(Map value) {
    if (value['version'] != 1) {
      throw const FormatException('Unsupported playback session');
    }
    final paths = List<String>.from(value['paths'] as List);
    final index = value['index'] as int;
    final position = (value['position'] as num).toDouble();
    final volume = (value['volume'] as num).toDouble();
    if (paths.isEmpty ||
        index < 0 ||
        index >= paths.length ||
        !position.isFinite ||
        position < 0 ||
        !volume.isFinite ||
        volume < 0 ||
        volume > 1) {
      throw const FormatException('Invalid playback session');
    }
    return PlaybackSession(
      paths: paths,
      originalPaths: List<String>.from(value['originalPaths'] as List),
      index: index,
      position: position,
      shuffle: value['shuffle'] as bool,
      playMode: value['playMode'] as String,
      volume: volume,
    );
  }

  /// Missing files are skipped. If the current track disappeared, start the
  /// next surviving track at zero instead of applying an unrelated position.
  ResolvedPlaybackSession<T>? resolve<T>(T? Function(String) find) {
    final queue = <T>[];
    int? selected;
    var currentSurvived = false;
    for (var i = 0; i < paths.length; i++) {
      final audio = find(paths[i]);
      if (audio == null) continue;
      if (selected == null && i >= index) {
        selected = queue.length;
        currentSurvived = i == index;
      }
      queue.add(audio);
    }
    if (queue.isEmpty) return null;
    final original = originalPaths.map(find).whereType<T>().toList();
    for (final audio in queue) {
      if (!original.contains(audio)) original.add(audio);
    }
    return ResolvedPlaybackSession(
      queue,
      original,
      selected ?? 0,
      currentSurvived ? position : 0,
    );
  }
}

class ResolvedPlaybackSession<T> {
  const ResolvedPlaybackSession(
    this.queue,
    this.originalQueue,
    this.index,
    this.position,
  );
  final List<T> queue;
  final List<T> originalQueue;
  final int index;
  final double position;
}

class PlaybackSessionStore {
  PlaybackSessionStore(this.dataDirectory);
  final Future<String> Function() dataDirectory;

  Future<String> get _file async =>
      path.join(await dataDirectory(), 'playback_session.json');

  Future<PlaybackSession?> read() async {
    final json = await readJsonSafely(await _file, <String, Object>{}) as Map;
    return json.isEmpty ? null : PlaybackSession.fromJson(json);
  }

  Future<void> save(PlaybackSession session) async =>
      writeJsonSafely(await _file, session.toJson());

  Future<void> clear() async => writeJsonSafely(await _file, <String, Object>{});
}
