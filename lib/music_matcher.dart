import 'dart:convert';
import 'dart:math';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/krc.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/qrc.dart';
import 'package:coriander_player/utils.dart';
import 'package:music_api/music_api.dart';

enum ResultSource { qq, kugou, netease }

double _computeScore(Audio audio, String title, String artists, String album) {
  int maxScore = audio.title.length + audio.artist.length + audio.album.length;
  int score = 0;

  int minTitleLength = min(audio.title.length, title.length);
  for (int i = 0; i < minTitleLength; ++i) {
    if (audio.title[i] == title[i]) score += 1;
  }

  int minArtistLength = min(audio.artist.length, artists.length);
  for (int i = 0; i < minArtistLength; ++i) {
    if (audio.artist[i] == artists[i]) score += 1;
  }

  int minAlbumLength = min(audio.album.length, album.length);
  for (int i = 0; i < minAlbumLength; ++i) {
    if (audio.album[i] == album[i]) score += 1;
  }

  return maxScore == 0 ? 0 : score / maxScore;
}

class SongSearchResult {
  ResultSource source;
  String title;
  String artists;
  String album;
  double score;

  /// for qq result
  int? qqSongId;

  /// for netease result
  String? neteaseSongId;

  /// for kugou result
  String? kugouSongHash;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.qqSongId, this.neteaseSongId, this.kugouSongHash});

  @override
  String toString() {
    return json.encode({
      "source": source.toString(),
      "title": title,
      "artists": artists,
      "album": album,
      "score": score,
    });
  }

  static SongSearchResult fromQQSearchResult(Map itemSong, Audio audio) {
    final List singer = itemSong["singer"];
    final buffer = StringBuffer(singer.first["name"]);
    for (int i = 1; i < singer.length; ++i) {
      buffer.write("、${singer[i]["name"]}");
    }

    final title = itemSong["name"] ?? "";
    final album = itemSong["album"]["title"] ?? "";
    final artists = buffer.toString();

    return SongSearchResult(
      ResultSource.qq,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      qqSongId: itemSong["id"],
    );
  }

  static SongSearchResult fromNeteaseSearchResult(Map song, Audio audio) {
    final title = song["name"] ?? "";

    final List artistList = song["artists"];
    final buffer = StringBuffer(artistList.first["name"]);
    for (int i = 1; i < artistList.length; ++i) {
      buffer.write("、${artistList[i]["name"]}");
    }
    final artists = buffer.toString();

    final album = song["album"]["name"] ?? "";

    return SongSearchResult(
      ResultSource.netease,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      neteaseSongId: song["id"].toString(),
    );
  }

  static SongSearchResult fromKugouSearchResult(Map info, Audio audio) {
    final title = info["songname"];
    final album = info["album_name"];
    final artists = info["singername"];

    return SongSearchResult(
      ResultSource.kugou,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album),
      kugouSongHash: info["hash"],
    );
  }
}

Future<List<SongSearchResult>> uniSearch(Audio audio) async {
  final query = audio.title;
  Future<List<SongSearchResult>> safely(
      Future<List<SongSearchResult>> Function() fetch) async {
    try {
      return await fetch().timeout(const Duration(seconds: 8));
    } catch (error, stack) {
      LOGGER.e(error, stackTrace: stack);
      return [];
    }
  }

  final results = await Future.wait([
    safely(() async {
      final answer = (await KuGou.searchSong(keyword: query)).data;
      final items = answer['data']?['info'] as List? ?? [];
      return items
          .take(5)
          .map((item) => SongSearchResult.fromKugouSearchResult(item, audio))
          .toList();
    }),
    safely(() async {
      final answer = (await Netease.search(keyWord: query)).data;
      final items = answer['result']?['songs'] as List? ?? [];
      return items
          .take(5)
          .map((item) => SongSearchResult.fromNeteaseSearchResult(item, audio))
          .toList();
    }),
    safely(() async {
      final answer = (await QQ.search(keyWord: query)).data;
      final items =
          answer['req']?['data']?['body']?['item_song'] as List? ?? [];
      return items
          .take(5)
          .map((item) => SongSearchResult.fromQQSearchResult(item, audio))
          .toList();
    }),
  ]);
  final result = results.expand((items) => items).toList();
  result.sort((a, b) => b.score.compareTo(a.score));
  return result;
}

Future<Lrc?> _getNeteaseUnsyncLyric(String neteaseSongId) async {
  try {
    final answer = await Netease.lyric(id: neteaseSongId);
    final lrcText = answer.data["lrc"]["lyric"];
    if (lrcText is String) {
      final lrcTrans = answer.data["tlyric"]?["lyric"] as String? ?? "";
      return Lrc.fromLrcText(
        lrcText + lrcTrans,
        LrcSource.web,
        separator: "┃",
      );
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Qrc?> _getQQSyncLyric(int qqSongId) async {
  try {
    final answer = await QQ.songLyric3(songId: qqSongId);
    final qrcText = answer.data["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = answer.data["trans"];
      if (qrcTransRawStr is String) {
        return Qrc.fromQrcText(qrcText, qrcTransRawStr);
      }
      return Qrc.fromQrcText(qrcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer = await KuGou.krc(hash: kugouSongHash);
    final krcText = answer.data["lyric"];
    if (krcText is String) {
      return Krc.fromKrcText(krcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) async {
  Lyric? lyric;
  if (qqSongId != null) {
    lyric = (await _getQQSyncLyric(qqSongId)
        .timeout(const Duration(seconds: 8), onTimeout: () => null));
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash)
        .timeout(const Duration(seconds: 8), onTimeout: () => null));
  } else if (neteaseSongId != null) {
    lyric = await _getNeteaseUnsyncLyric(neteaseSongId)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
  }
  return lyric;
}

final _lyricCache = <String, Lyric>{};

Future<Lyric?> getMostMatchedLyric(Audio audio) async {
  final key = '${audio.path}|${audio.modified}|${audio.title}|${audio.artist}';
  if (_lyricCache.containsKey(key)) return _lyricCache[key];
  final candidates = await uniSearch(audio);
  for (final candidate in candidates.take(3)) {
    final lyric = await getOnlineLyric(
      qqSongId: candidate.qqSongId,
      kugouSongHash: candidate.kugouSongHash,
      neteaseSongId: candidate.neteaseSongId,
    );
    if (lyric != null && lyric.lines.isNotEmpty) {
      if (_lyricCache.length >= 64) _lyricCache.remove(_lyricCache.keys.first);
      _lyricCache[key] = lyric;
      return lyric;
    }
  }
  return null;
}
