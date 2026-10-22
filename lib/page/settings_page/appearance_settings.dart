import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/appearance.dart';
import 'package:coriander_player/component/playback_visuals.dart';
import 'package:flutter/material.dart';

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance,
        preferences = AppSettings.instance.appearance;
    void update(VoidCallback change) {
      preferences.update(change);
      settings.saveSettings();
    }

    return ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                  title: const Text('播放外观与动效'),
                  initiallyExpanded: true,
                  subtitle: Text(
                      '${preferences.artwork == ArtworkStyle.vinyl ? '黑胶唱片' : '经典封面'} · '
                      '${switch (preferences.progress) {
                    ProgressStyle.wave => '波浪进度条',
                    ProgressStyle.waveform => '整曲波形',
                    ProgressStyle.line => '普通进度条'
                  }}'),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('音乐库卡片悬停动效'),
                        subtitle: const Text('鼠标移入时轻微抬升，显示播放按钮'),
                        value: preferences.animateLibraryCards,
                        onChanged: (value) => update(
                            () => preferences.animateLibraryCards = value)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('音乐库卡片阴影'),
                        value: preferences.libraryCardShadows,
                        onChanged: (value) => update(
                            () => preferences.libraryCardShadows = value)),
                    Row(children: [
                      SizedBox.square(
                          dimension: 100,
                          child: VinylArtwork(
                              playing: false,
                              animate: false,
                              secondsPerTurn: preferences.rotationSeconds)),
                      Expanded(
                          child: WaveSeekBar(
                              value: 65,
                              duration: 100,
                              onChanged: null,
                              wave: preferences.progress == ProgressStyle.wave,
                              amplitude: preferences.waveAmplitude,
                              gentle: preferences.motion == MotionLevel.gentle))
                    ]),
                    _choice<ArtworkStyle>(
                        '播放页封面',
                        preferences.artwork,
                        {
                          ArtworkStyle.vinyl: '黑胶唱片',
                          ArtworkStyle.classic: '经典封面'
                        },
                        (value) => update(() => preferences.artwork = value)),
                    _choice<ProgressStyle>(
                        '进度条样式',
                        preferences.progress,
                        {
                          ProgressStyle.wave: '动态波浪',
                          ProgressStyle.line: '普通直线',
                          ProgressStyle.waveform: '整曲真实波形'
                        },
                        (value) => update(() => preferences.progress = value)),
                    if (preferences.progress == ProgressStyle.waveform)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('首次分析在后台完成，之后直接读取缓存；歌曲文件不会被修改。')),
                    _choice<SpectrumStyle>(
                        '真实音频频谱',
                        preferences.spectrum,
                        {
                          SpectrumStyle.off: '关闭',
                          SpectrumStyle.bars: '底部柱状',
                          SpectrumStyle.ring: '封面环形'
                        },
                        (value) => update(() => preferences.spectrum = value)),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('歌词细节'),
                        subtitle: const Text('当前行聚焦、柔光、边缘渐隐与行距'),
                        children: [
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('当前歌词行轻微放大'),
                              value: preferences.lyricFocus,
                              onChanged: (value) =>
                                  update(() => preferences.lyricFocus = value)),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('歌词柔光高亮'),
                              value: preferences.lyricGlow,
                              onChanged: (value) =>
                                  update(() => preferences.lyricGlow = value)),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('歌词上下边缘渐隐'),
                              value: preferences.lyricEdgeFade,
                              onChanged: (value) => update(
                                  () => preferences.lyricEdgeFade = value)),
                          _slider(
                              '非当前行亮度',
                              '${(preferences.inactiveLyricOpacity * 100).round()}%',
                              preferences.inactiveLyricOpacity,
                              .18,
                              .7,
                              (value) => preferences.update(() =>
                                  preferences.inactiveLyricOpacity = value),
                              settings.saveSettings),
                          _slider(
                              '歌词行距',
                              '${preferences.lyricLineSpacing.round()}',
                              preferences.lyricLineSpacing,
                              8,
                              24,
                              (value) => preferences.update(
                                  () => preferences.lyricLineSpacing = value),
                              settings.saveSettings),
                        ]),
                    _choice<MotionLevel>(
                        '动效强度',
                        preferences.motion,
                        {
                          MotionLevel.off: '关闭',
                          MotionLevel.gentle: '轻柔',
                          MotionLevel.full: '完整'
                        },
                        (value) => update(() => preferences.motion = value)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('播放按钮动效'),
                        value: preferences.animateControls,
                        onChanged: (value) =>
                            update(() => preferences.animateControls = value)),
                    _slider(
                        '唱片转速',
                        '${preferences.rotationSeconds.round()} 秒 / 圈',
                        preferences.rotationSeconds,
                        12,
                        40,
                        (value) => preferences
                            .update(() => preferences.rotationSeconds = value),
                        settings.saveSettings),
                    _slider(
                        '波浪幅度',
                        '${preferences.waveAmplitude.round()}',
                        preferences.waveAmplitude,
                        2,
                        9,
                        (value) => preferences
                            .update(() => preferences.waveAmplitude = value),
                        settings.saveSettings),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('封面氛围背景'),
                        subtitle: const Text('柔化封面，并在切歌时平滑过渡'),
                        value: preferences.coverBackground,
                        onChanged: (value) =>
                            update(() => preferences.coverBackground = value)),
                    if (preferences.coverBackground) ...[
                      _slider(
                          '背景模糊',
                          '${preferences.backgroundBlur.round()}',
                          preferences.backgroundBlur,
                          8,
                          48,
                          (value) => preferences
                              .update(() => preferences.backgroundBlur = value),
                          settings.saveSettings),
                      _slider(
                          '背景浓度',
                          '${(preferences.backgroundStrength * 100).round()}%',
                          preferences.backgroundStrength,
                          .1,
                          .6,
                          (value) => preferences.update(
                              () => preferences.backgroundStrength = value),
                          settings.saveSettings),
                    ],
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('后台节能'),
                        subtitle: const Text('最小化或隐藏到托盘时停止装饰动画，音乐继续播放'),
                        value: preferences.savePower,
                        onChanged: (value) =>
                            update(() => preferences.savePower = value)),
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('频谱随音乐变化；关闭动效或系统要求减少动画时，唱片、波浪和频谱保持静止。')),
                  ]),
            ));
  }

  Widget _choice<T>(String title, T value, Map<T, String> values,
          ValueChanged<T> changed) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          trailing: DropdownButton<T>(
              value: value,
              items: [
                for (final entry in values.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value))
              ],
              onChanged: (value) {
                if (value != null) changed(value);
              }));

  Widget _slider(
          String title,
          String label,
          double value,
          double min,
          double max,
          ValueChanged<double> changed,
          Future<void> Function() save) =>
      Column(children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(title), Text(label)]),
        Slider(
            value: value,
            min: min,
            max: max,
            label: label,
            onChanged: changed,
            onChangeEnd: (_) => save()),
      ]);
}
