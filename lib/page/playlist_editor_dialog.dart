import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/library/smart_playlist_rule.dart';
import 'package:flutter/material.dart';

class PlaylistEditorDialog extends StatefulWidget {
  const PlaylistEditorDialog({super.key, this.initial, this.smart = false});
  final Playlist? initial;
  final bool smart;
  @override
  State<PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<PlaylistEditorDialog> {
  final form = GlobalKey<FormState>();
  late final fields = [
    widget.initial?.name ?? '',
    widget.initial?.smartRule?.artist ?? '',
    widget.initial?.smartRule?.album ?? '',
    widget.initial?.smartRule?.title ?? '',
    widget.initial?.smartRule?.folder ?? '',
    widget.initial?.smartRule?.formats.join(', ') ?? '',
    widget.initial?.smartRule?.minSeconds?.toString() ?? '',
    widget.initial?.smartRule?.maxSeconds?.toString() ?? '',
    widget.initial?.smartRule?.minBitrate?.toString() ?? ''
  ].map((text) => TextEditingController(text: text)).toList();
  late bool matchAll = widget.initial?.smartRule?.matchAll ?? true;
  bool get smart => widget.smart || widget.initial?.isSmart == true;

  SmartPlaylistRule rule() => SmartPlaylistRule(
      artist: fields[1].text.trim(),
      album: fields[2].text.trim(),
      title: fields[3].text.trim(),
      folder: fields[4].text.trim(),
      formats: fields[5]
          .text
          .split(RegExp(r'[,，;；\s]+'))
          .map((s) => s.trim().toLowerCase().replaceFirst('.', ''))
          .where((s) => s.isNotEmpty)
          .toList(),
      minSeconds: int.tryParse(fields[6].text),
      maxSeconds: int.tryParse(fields[7].text),
      minBitrate: int.tryParse(fields[8].text),
      matchAll: matchAll);

  void save() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(context,
        Playlist(fields[0].text.trim(), {}, smartRule: smart ? rule() : null));
  }

  @override
  Widget build(BuildContext context) {
    final currentRule = rule();
    final count = smart
        ? AudioLibrary.instance.audioCollection
            .where((audio) => currentRule.matches(
                songTitle: audio.title,
                songArtist: audio.artist,
                songAlbum: audio.album,
                filePath: audio.path,
                seconds: audio.duration,
                bitrate: audio.bitrate))
            .length
        : 0;
    const labels = [
      '歌单名称',
      '艺术家包含',
      '专辑包含',
      '歌名包含',
      '音乐文件夹（含子文件夹）',
      '格式（如 flac, mp3）',
      '最短时长（秒）',
      '最长时长（秒）',
      '最低码率（kbps）'
    ];
    return AlertDialog(
      title: Text(
          '${widget.initial == null ? '新建' : '编辑'}${smart ? '智能歌单' : '歌单'}'),
      content: SizedBox(
          width: 460,
          child: Focus(
            onFocusChange: HotkeysHelper.onFocusChanges,
            child: Form(
                key: form,
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (smart) ...[
                      const Text('符合规则的歌曲会自动加入；刷新音乐库后同步更新。留空的条件不参与匹配。'),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('满足所有条件')),
                            ButtonSegment(value: false, label: Text('满足任一条件'))
                          ],
                          selected: {
                            matchAll
                          },
                          onSelectionChanged: (v) =>
                              setState(() => matchAll = v.first)),
                      const SizedBox(height: 12),
                    ],
                    for (var i = 0; i < (smart ? fields.length : 1); i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                            controller: fields[i],
                            autofocus: i == 0,
                            decoration: InputDecoration(
                                labelText: labels[i],
                                border: const OutlineInputBorder()),
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (i == 0 && value!.trim().isEmpty)
                                return '请输入歌单名称';
                              if (i >= 6 &&
                                  value!.isNotEmpty &&
                                  (int.tryParse(value) == null ||
                                      int.parse(value) < 0))
                                return '请输入不小于 0 的整数';
                              if (i == 7 &&
                                  currentRule.minSeconds != null &&
                                  currentRule.maxSeconds != null &&
                                  currentRule.maxSeconds! <
                                      currentRule.minSeconds!)
                                return '最长时长不能小于最短时长';
                              return null;
                            }),
                      ),
                    if (smart) Text('当前匹配 $count 首歌曲'),
                  ],
                ))),
          )),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: save, child: const Text('保存'))
      ],
    );
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }
}
