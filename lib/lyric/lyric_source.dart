import 'dart:async';
import 'package:coriander_player/storage/safe_json.dart';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';

enum LyricSourceType {
  qq("qq"),
  kugou("kugou"),
  netease("netease"),
  local("local");

  final String name;
  const LyricSourceType(this.name);
}

/// 默认歌词来源
class LyricSource {
  LyricSourceType source;
  int? qqSongId;
  String? kugouSongHash;
  String? neteaseSongId;

  LyricSource(this.source,
      {this.qqSongId, this.kugouSongHash, this.neteaseSongId});

  static LyricSource fromMap(Map map) {
    if (map["source"] == "qq") {
      return LyricSource(LyricSourceType.qq, qqSongId: map["id"]);
    } else if (map["source"] == "kugou") {
      return LyricSource(LyricSourceType.kugou, kugouSongHash: map["id"]);
    } else if (map["source"] == "netease") {
      return LyricSource(LyricSourceType.netease, neteaseSongId: map["id"]);
    } else {
      return LyricSource(LyricSourceType.local);
    }
  }

  Map toMap() {
    switch (source) {
      case LyricSourceType.qq:
        return {"source": source.name, "id": qqSongId};
      case LyricSourceType.kugou:
        return {"source": source.name, "id": kugouSongHash};
      case LyricSourceType.netease:
        return {"source": source.name, "id": neteaseSongId};
      case LyricSourceType.local:
        return {"source": source.name, "id": null};
    }
  }
}

Map<String, LyricSource> LYRIC_SOURCES = {};
bool lyricSourcesLoaded = false;

Future<void> readLyricSources() async {
  if (lyricSourcesLoaded) return;
  try {
    final supportPath = (await getAppDataDir()).path;
    final lyricSourcePath = "$supportPath\\lyric_source.json";

    final lyricSourceJson =
        await readJsonSafely(lyricSourcePath, <String, Object>{}) as Map;
    final parsed = <String, LyricSource>{};
    for (final item in lyricSourceJson.entries) {
      parsed[item.key as String] = LyricSource.fromMap(item.value as Map);
    }
    LYRIC_SOURCES = parsed;
    lyricSourcesLoaded = true;
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Timer? _lyricSaveTimer;

void scheduleLyricSourceSave() {
  _lyricSaveTimer?.cancel();
  _lyricSaveTimer = Timer(const Duration(milliseconds: 400), () async {
    try {
      await saveLyricSources();
    } catch (error, stack) {
      LOGGER.e(error, stackTrace: stack);
      showTextOnSnackBar('歌词选择保存失败，请检查磁盘空间和权限');
    }
  });
}

Future<void> saveLyricSources() async {
  _lyricSaveTimer?.cancel();
  if (!lyricSourcesLoaded) return;
  final supportPath = (await getAppDataDir()).path;
  await writeJsonSafely('$supportPath/lyric_source.json',
      LYRIC_SOURCES.map((key, value) => MapEntry(key, value.toMap())));
}
