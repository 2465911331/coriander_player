import 'dart:convert';
import 'dart:io';

final Map<String, Future<void>> _writes = {};

/// Serializes writes per file. The flushed replacement lives on the same volume.
Future<void> writeJsonSafely(String path, Object value) {
  final contents = json.encode(value);
  final previous = _writes[path] ?? Future<void>.value();
  final operation = previous.then((_) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await file.exists()) {
      // Never replace a good backup with a corrupt original.
      try {
        final oldContents = await file.readAsString();
        json.decode(oldContents);
        final backup = File('$path.bak.tmp');
        await backup.writeAsString(oldContents, flush: true);
        await backup.rename('$path.bak');
      } on FormatException {
        // A previous read may have recovered from the backup.
      }
    }
    await temporary.rename(path);
  });
  // A failed operation must not poison the next save.
  final tail =
      operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  _writes[path] = tail;
  tail.then((_) {
    if (identical(_writes[path], tail)) _writes.remove(path);
  });
  return operation;
}

Future<Object?> readJsonSafely(String path, Object empty) async {
  final file = File(path);
  final backup = File('$path.bak');
  if (!await file.exists() && !await backup.exists()) return empty;
  try {
    return json.decode(await file.readAsString());
  } on FileSystemException {
    if (!await backup.exists()) rethrow;
  } on FormatException {
    if (!await backup.exists()) rethrow;
  }
  return json.decode(await backup.readAsString());
}
