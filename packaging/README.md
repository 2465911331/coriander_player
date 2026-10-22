# 制作 Windows 安装包

将完整、可运行的发布目录复制到 packaging/bundle，包含主程序、data、Rust DLL、音量分析 DLL、BASS、desktop_lyric、VC++ 运行库及第三方许可等；将官方 app_icon.ico 复制为 bundle/coriander_player.ico。bundle 与 dist 已被 Git 忽略。

使用 Inno Setup 6.7.3 的编译器：

```powershell
ISCC.exe packaging/coriander_player.iss
```

输出为 dist/CorianderPlayer-Setup-1.5.7.exe。脚本沿用稳定 AppId，保留 UsePreviousAppDir/Group/Tasks；覆盖安装时只请求目标安装目录的旧进程正常退出，不影响其他目录的便携副本。不要为了发新版本更换 AppId。

将下一版程序和脚本中的版本同步更新后，重复构建、测试和覆盖安装验证。

1.5.7 发布资产中的安装包为已经验证的构建；本脚本保留相同安装逻辑，使用相对于仓库的路径，方便后续重现。
