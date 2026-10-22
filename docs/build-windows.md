# Windows 源码编译

本分支基于 @Ferry-200 的 [coriander_player](https://github.com/Ferry-200/coriander_player)。应用源码、原生修改与第三方许可均在仓库中保留。

## 环境

- Flutter 3.32.8 / Dart 3.8.1（本版验证使用的版本）。
- Visual Studio 2022 的“使用 C++ 的桌面开发”，含 Windows SDK、MSVC 和 CMake。
- Rust stable 的 MSVC x64 工具链、Git；安装器使用 Inno Setup 6.7.3。
- 使用仓库的 pubspec.lock 与 rust/Cargo.lock，不要为了编译本版主动升级依赖。

## 构建程序

```powershell
git clone --branch enhanced https://github.com/2465911331/coriander_player.git
Set-Location coriander_player
Copy-Item lib/page/settings_page/cpfeedback_key.example.dart lib/page/settings_page/cpfeedback_key.dart
flutter pub get
flutter build windows --release
```

反馈密钥示例为空字符串，和发布包保持一致；编译不需要原作者的私有令牌。请在本仓库 Issues 反馈，不要把自己的访问令牌写入应用或提交到 Git。

Flutter 构建会通过项目已有的 Cargokit 集成构建 Rust 库，并编译本地 libebur128 音量分析库、复制 bassmix。主程序位于 build/windows/x64/runner/Release。

运行前，按上游方式准备 BASS 及格式插件的 Windows x64 DLL，放入发布目录的 BASS 文件夹：bass、basswasapi、bassape、bassdsd、bassflac、bassmidi、bassopus、basswv，以及本仓库提供的 bassmix。库和许可说明来自 [UN4SEEN](https://www.un4seen.com/)。

桌面歌词是独立应用。应另行构建 [Ferry-200/desktop_lyric](https://github.com/Ferry-200/desktop_lyric)，使用 pubspec.yaml 固定的提交 536be8df55c80a7fdf7cc20f603d3fc76a732821，将其完整构建输出放入主程序目录的 desktop_lyric 文件夹。保留对应的许可证、官方图标及所需 VC++ 运行库。

本次已发布的 EXE 已包含运行所需组件，普通用户无需搭建上述环境。

## 检查

```powershell
dart analyze lib test tool
flutter test
```

1.5.7 共 107 项测试通过，静态检查无错误、无警告；仍有信息级风格及弃用提示。没有对全部显示缩放组合或逐帧性能作认证。

发布包支持使用 CORIANDER_DATA_DIR 环境变量指定隔离数据目录；开发验证时请使用独立目录，以免触及现有音乐库。

## 安装器

见 [packaging/README.md](../packaging/README.md)。原项目说明保存在 [upstream-readme.md](upstream-readme.md)。
