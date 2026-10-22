import 'dart:io';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Runs against the packaged native library and isolated fixture songs.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected bundle directory and fixture song directory');
  }
  final library =
      File('${arguments[0]}/rust_lib_coriander_player.dll').absolute;
  await RustLib.init(externalLibrary: ExternalLibrary.open(library.path));
  try {
    for (var repeat = 0; repeat < 3; repeat++) {
      final embedded = await getPictureFromPath(
          path: File('${arguments[1]}/library-00.wav').absolute.path,
          width: 200,
          height: 200);
      if (embedded == null ||
          embedded.length < 24 ||
          embedded[0] != 137 ||
          embedded[1] != 80) {
        throw StateError('Embedded cover did not return a PNG image');
      }
      final missing = await getPictureFromPath(
          path: File('${arguments[1]}/library-05.wav').absolute.path,
          width: 200,
          height: 200);
      if (missing != null) {
        throw StateError('Missing artwork returned file icon or invalid bytes');
      }
    }
    stdout.writeln(
        'PASS: embedded covers decode; missing covers return null, never a file icon (3 rounds).');
  } finally {
    RustLib.dispose();
  }
}
