import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/play_service/loudness_model.dart';
import 'package:coriander_player/play_service/loudness_service.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

class AudioSettings extends StatefulWidget {
  const AudioSettings({super.key});
  @override
  State<AudioSettings> createState() => _AudioSettingsState();
}

class _AudioSettingsState extends State<AudioSettings> {
  final settings = AppSettings.instance;
  final loudness = LoudnessService.instance;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('无缝播放'),
            subtitle: const Text('预先准备下一首，连续播放时不额外插入停顿；独占模式使用普通切歌'),
            value: settings.gaplessPlayback,
            onChanged: (value) async {
              setState(() => settings.gaplessPlayback = value);
              PlayService.instance.playbackService
                  .updateAudioSettings(rebuildOutput: true);
              await settings.saveSettings();
            }),
        const SizedBox(height: 16),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('歌曲音量统一'),
            subtitle: const Text('单曲模式平衡歌曲音量；专辑模式保留同目录、同专辑的音量关系。音乐文件不会被修改。'),
            trailing: DropdownButton<NormalizationMode>(
                value: settings.normalizationMode,
                items: NormalizationMode.values
                    .map((mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)))
                    .toList(),
                onChanged: (mode) async {
                  if (mode == null) return;
                  setState(() => settings.normalizationMode = mode);
                  PlayService.instance.playbackService.updateAudioSettings();
                  await settings.saveSettings();
                })),
        ListenableBuilder(
            listenable: loudness,
            builder: (context, _) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(loudness.status),
                  if (loudness.isScanning)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(
                            value: loudness.total == 0
                                ? 0
                                : loudness.completed / loudness.total)),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonal(
                            onPressed: loudness.isScanning
                                ? null
                                : loudness.analyzeLibrary,
                            child: Text(loudness.isScanning
                                ? '正在分析 ${loudness.completed}/${loudness.total}'
                                : '分析音乐库音量')),
                        if (loudness.isScanning)
                          TextButton(
                              onPressed: loudness.stopScan,
                              child: const Text('完成当前专辑后停止')),
                      ]),
                  const SizedBox(height: 8),
                  const Text('首次播放会自动在后台分析，完成后生效。提前分析可在播放前准备好音量。'),
                ])),
      ]);
}
