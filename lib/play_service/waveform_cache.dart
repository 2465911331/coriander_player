import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:coriander_player/play_service/waveform_model.dart';
import 'package:coriander_player/storage/safe_json.dart';

typedef WaveformAnalyzer = Future<WaveformData> Function(String file);

class WaveformCache {
  WaveformCache({required this.directory, required this.analyze});
  final Future<String> Function() directory;
  final WaveformAnalyzer analyze;
  final _memory = <String, WaveformData>{};
  final _pending = <String, Future<WaveformData?>>{};
  static const maxFiles = 512;

  // Cache keys are deterministic; the full identity is checked on every hit.
  String _key(String identity) {
    var value = 0x4bf29ce484222325;
    for (final unit in utf8.encode(identity)) {
      value = ((value ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return value.toRadixString(16).padLeft(16, '0');
  }

  Future<String> _identity(String file) async {
    final stat = await File(file).stat();
    if (stat.type != FileSystemEntityType.file || stat.size < 1)
      throw FileSystemException('No audio file', file);
    return '${path.windows.normalize(File(file).absolute.path).toLowerCase()}|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
  }

  Future<WaveformData?> load(String file) async {
    try {
      final identity = await _identity(file);
      final known = _memory.remove(identity);
      if (known != null) {
        _memory[identity] = known;
        return known;
      }
      return await (_pending[identity] ??=
          _load(file, identity).whenComplete(() {
        _pending.remove(identity);
      }));
    } catch (_) {
      return null;
    }
  }

  Future<WaveformData?> _load(String file, String identity) async {
    String? root, cachedFile;
    Object? json;
    try {
      root = await directory();
      await Directory(root).create(recursive: true);
      cachedFile = path.join(root, '${_key(identity)}.json');
      json = await readJsonSafely(cachedFile, {});
    } catch (_) {/* An unreadable cache must not block a fresh analysis. */}
    var data = json is Map && json['identity'] == identity
        ? WaveformData.fromJson(json)
        : null;
    if (data == null) {
      data = await analyze(file);
      // A file replaced during decoding must never receive a valid cache entry.
      if (await _identity(file) != identity) return null;
      try {
        if (cachedFile != null && root != null) {
          await writeJsonSafely(
              cachedFile, {...data.toJson(), 'identity': identity});
          await _prune(root);
        }
      } catch (_) {/* The in-memory waveform remains usable. */}
    }
    _memory[identity] = data;
    while (_memory.length > 24) {
      _memory.remove(_memory.keys.first);
    }
    return data;
  }

  Future<void> _prune(String root) async {
    final generated = RegExp(r'^[0-9a-f]{16}\.json$');
    final entries = await Directory(root)
        .list()
        .where((item) =>
            item is File && generated.hasMatch(path.basename(item.path)))
        .toList();
    if (entries.length <= maxFiles) return;
    final files = <(FileSystemEntity, FileStat)>[];
    for (final file in entries) {
      files.add((file, await file.stat()));
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final item in files.take(files.length - maxFiles)) {
      try {
        await item.$1.delete();
      } catch (_) {/* Cache eviction is optional. */}
    }
  }
}
