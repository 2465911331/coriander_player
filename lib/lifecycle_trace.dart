import 'dart:io';

/// Small local lifecycle log; contains stages, never music paths or metadata.
class LifecycleTrace {
  static File? _file;
  static void initialize(String directory) {
    _file = File('$directory/window-lifecycle.log');
    record('startup R3');
  }

  static void record(String stage) {
    try {
      final file = _file;
      if (file == null) return;
      if (file.existsSync() && file.lengthSync() > 65536) {
        file.writeAsStringSync('');
      }
      file.writeAsStringSync('${DateTime.now().toIso8601String()} $stage\n',
          mode: FileMode.append);
    } catch (_) {
      // Diagnostics must never prevent restoring or closing the application.
    }
  }
}
