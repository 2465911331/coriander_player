// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'package:coriander_player/storage/safe_json.dart';
import 'package:coriander_player/library/smart_playlist_rule.dart';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/utils.dart';

List<Playlist> PLAYLISTS = [];
bool playlistsLoaded = false;

Future<void> readPlaylists() async {
  if (playlistsLoaded) return;
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath = "$supportPath\\playlists.json";

    final playlistsJson =
        await readJsonSafely(playlistsPath, <Object>[]) as List;
    final parsed =
        playlistsJson.map((item) => Playlist.fromMap(item as Map)).toList();
    PLAYLISTS = parsed;
    playlistsLoaded = true;
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Timer? _playlistSaveTimer;

void schedulePlaylistSave() {
  _playlistSaveTimer?.cancel();
  _playlistSaveTimer = Timer(const Duration(milliseconds: 400), () async {
    try {
      await savePlaylists();
    } catch (error, stack) {
      LOGGER.e(error, stackTrace: stack);
      showTextOnSnackBar('歌单保存失败，请检查磁盘空间和权限');
    }
  });
}

Future<void> savePlaylists() async {
  _playlistSaveTimer?.cancel();
  if (!playlistsLoaded) return;
  final supportPath = (await getAppDataDir()).path;
  await writeJsonSafely('$supportPath/playlists.json',
      PLAYLISTS.map((item) => item.toMap()).toList());
}

class Playlist {
  String name;

  /// path, audio
  final Map<String, Audio> _manualAudios;
  SmartPlaylistRule? smartRule;
  int _revision = -1;
  SmartPlaylistRule? _cachedRule;
  Map<String, Audio> _matched = {};
  bool get isSmart => smartRule != null;

  Map<String, Audio> get audios {
    final rule = smartRule;
    if (rule == null) return _manualAudios;
    if (_revision != AudioLibrary.revision.value ||
        !identical(_cachedRule, rule)) {
      _matched = {
        for (final audio in AudioLibrary.instance.audioCollection)
          if (rule.matches(
              songTitle: audio.title,
              songArtist: audio.artist,
              songAlbum: audio.album,
              filePath: audio.path,
              seconds: audio.duration,
              bitrate: audio.bitrate))
            audio.path: audio,
      };
      _revision = AudioLibrary.revision.value;
      _cachedRule = rule;
    }
    return _matched;
  }

  Playlist(this.name, Map<String, Audio> audios, {this.smartRule})
      : _manualAudios = audios;

  Map toMap() {
    final List<Map> audioMaps = [];
    for (var item in _manualAudios.values) {
      audioMaps.add(item.toMap());
    }
    return {
      "name": name,
      "audios": audioMaps,
      if (smartRule != null) 'smartRule': smartRule!.toJson()
    };
  }

  factory Playlist.fromMap(Map map) {
    final Map<String, Audio> audios = {};
    final List audioMaps = map["audios"];
    for (var item in audioMaps) {
      final audio = Audio.fromMap(item);
      audios[audio.path] = audio;
    }
    return Playlist(map["name"], audios,
        smartRule: map['smartRule'] == null
            ? null
            : SmartPlaylistRule.fromJson(map['smartRule'] as Map));
  }
}
