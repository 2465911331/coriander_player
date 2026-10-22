import 'package:coriander_player/page/settings_page/appearance_settings.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/settings_page/artist_separator_editor.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/audio_settings.dart';
import 'package:coriander_player/page/settings_page/theme_settings.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const DefaultTabController(
      length: 5,
      child: PageScaffold(
          title: '设置',
          actions: [],
          body: Column(children: [
            TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: '播放与窗口'),
              Tab(text: '声音'),
              Tab(text: '音乐库'),
              Tab(text: '外观与动效'),
              Tab(text: '关于')
            ]),
            SizedBox(height: 16),
            Expanded(
                child: TabBarView(children: [
              _SettingsSection(storage: 'playback', children: [
                PlaybackAndWindowSettings(),
                DefaultLyricSourceControl()
              ]),
              _SettingsSection(storage: 'audio', children: [AudioSettings()]),
              _SettingsSection(
                  storage: 'library',
                  children: [AudioLibraryEditor(), ArtistSeparatorEditor()]),
              _SettingsSection(storage: 'appearance', children: [
                AppearanceSettings(),
                DynamicThemeSwitch(),
                UseSystemThemeSwitch(),
                ThemeSelector(),
                UseSystemThemeModeSwitch(),
                ThemeModeControl(),
                SelectFontCombobox()
              ]),
              _SettingsSection(
                  storage: 'about',
                  children: [CheckForUpdate(), CreateIssueTile()]),
            ])),
          ])));
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.storage, required this.children});
  final String storage;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
              key: PageStorageKey('settings-$storage'),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < children.length; i++) ...[
                                if (i > 0)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Divider()),
                                children[i],
                              ]
                            ])))
              ])));
}
