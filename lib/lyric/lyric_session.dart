import 'lyric.dart';

/// Only the newest request may publish lyrics. Position updates never await I/O.
class LyricSession {
  int _generation = 0;
  bool _disposed = false;
  Lyric? value;

  Future<Lyric?> load(Future<Lyric?> request, void Function() changed) async {
    final generation = ++_generation;
    value = null;
    final lyric = await request;
    if (_disposed || generation != _generation) return null;
    value = lyric;
    changed();
    return lyric;
  }

  int lineAt(Duration position) {
    final lines = value?.lines;
    if (lines == null || lines.isEmpty) return -1;
    int low = 0, high = lines.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (lines[middle].start <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  void dispose() {
    _disposed = true;
    _generation++;
    value = null;
  }
}
