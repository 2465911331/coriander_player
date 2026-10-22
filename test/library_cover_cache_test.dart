import 'dart:async';
import 'dart:typed_data';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pictures extends Fake implements RustLibApi {
  final calls = <String, int>{};
  Completer<Uint8List?>? pending;
  @override
  SystemTheme crateApiSystemThemeSystemThemeGetSystemTheme() =>
      const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 100, 100, 200));
  @override
  Future<Uint8List?> crateApiTagReaderGetPictureFromPath(
      {required String path, required int width, required int height}) {
    calls.update(path, (count) => count + 1, ifAbsent: () => 1);
    return pending?.future ?? Future.value(null);
  }
}

Audio song(String path) =>
    Audio(path, 'Artist', 'Album', 1, 120, 128, 8000, path, 0, 0, 'test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Pictures pictures;
  setUpAll(() {
    pictures = _Pictures();
    RustLib.initMock(api: pictures);
  });
  setUp(() {
    pictures.calls.clear();
    pictures.pending = null;
  });
  tearDownAll(RustLib.dispose);

  test('concurrent artwork requests share work and cache missing artwork',
      () async {
    pictures.pending = Completer<Uint8List?>();
    final audio = song('concurrent');
    final first = audio.mediumCover;
    final second = audio.mediumCover;
    expect(identical(first, second), isTrue);
    expect(pictures.calls['concurrent'], 1);
    pictures.pending!.complete(null);
    expect(await first, isNull);
    expect(await audio.mediumCover, isNull);
    expect(pictures.calls['concurrent'], 1);
  });

  test('large libraries evict old covers while keeping frequently used covers',
      () async {
    final frequent = song('frequent'), old = song('old');
    await frequent.mediumCover;
    await old.mediumCover;
    for (var i = 0; i < 250; i++) {
      await song('scrolled-$i').mediumCover;
      if (i % 20 == 0) await frequent.mediumCover;
    }
    await frequent.mediumCover;
    expect(pictures.calls['frequent'], 1);
    await old.mediumCover;
    expect(pictures.calls['old'], 2);
  });
}
