import 'package:path/path.dart' as path;

class SmartPlaylistRule {
  const SmartPlaylistRule(
      {this.artist = '',
      this.album = '',
      this.title = '',
      this.folder = '',
      this.formats = const [],
      this.minSeconds,
      this.maxSeconds,
      this.minBitrate,
      this.matchAll = true});
  final String artist, album, title, folder;
  final List<String> formats;
  final int? minSeconds, maxSeconds, minBitrate;
  final bool matchAll;

  bool matches(
      {required String songTitle,
      required String songArtist,
      required String songAlbum,
      required String filePath,
      required int seconds,
      int? bitrate}) {
    bool contains(String value, String query) =>
        value.toLowerCase().contains(query.trim().toLowerCase());
    final checks = <bool>[
      if (artist.trim().isNotEmpty) contains(songArtist, artist),
      if (album.trim().isNotEmpty) contains(songAlbum, album),
      if (title.trim().isNotEmpty) contains(songTitle, title),
      if (folder.trim().isNotEmpty)
        path.windows.normalize(filePath).toLowerCase().startsWith(
            '${path.windows.normalize(folder.trim()).toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '')}\\'),
      if (formats.isNotEmpty)
        formats
            .map((f) => f.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
            .contains(path.windows
                .extension(filePath)
                .toLowerCase()
                .replaceFirst('.', '')),
      if (minSeconds != null || maxSeconds != null)
        (minSeconds == null || seconds >= minSeconds!) &&
            (maxSeconds == null || seconds <= maxSeconds!),
      if (minBitrate != null) bitrate != null && bitrate >= minBitrate!,
    ];
    return checks.isEmpty ||
        (matchAll ? checks.every((v) => v) : checks.any((v) => v));
  }

  Map<String, Object?> toJson() => {
        'artist': artist,
        'album': album,
        'title': title,
        'folder': folder,
        'formats': formats,
        'minSeconds': minSeconds,
        'maxSeconds': maxSeconds,
        'minBitrate': minBitrate,
        'matchAll': matchAll
      };

  factory SmartPlaylistRule.fromJson(Map value) => SmartPlaylistRule(
      artist: value['artist'] as String? ?? '',
      album: value['album'] as String? ?? '',
      title: value['title'] as String? ?? '',
      folder: value['folder'] as String? ?? '',
      formats: List<String>.from(value['formats'] as List? ?? []),
      minSeconds: value['minSeconds'] as int?,
      maxSeconds: value['maxSeconds'] as int?,
      minBitrate: value['minBitrate'] as int?,
      matchAll: value['matchAll'] != false);
}
