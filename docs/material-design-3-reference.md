# Material Design 3 学习与播放器应用参考

查阅日期：2026-10-21。范围：官方设计基础、视觉风格、动效、组件与 Flutter 实现。

本文区分官方原则、已核对的项目现状，以及建议采用的产品设计。建议尚未实施，也不表示当前播放器已完全符合 M3。

## 1. 理解规范的层次

M3 将无障碍、布局、交互状态和设计令牌作为基础，再通过颜色、文字、形状、动效与组件表达产品。M3 Expressive 是这套系统的扩展，更新了组件、形状、文字与动效；设计规范与各平台组件的实现进度需要分别核对。

来源：[M3 Foundations](https://m3.material.io/foundations/)、[M3 Get started](https://m3.material.io/get-started)。

项目应用：把颜色、文字角色、圆角与动效参数集中管理，组件引用共同定义；给播放器保留封面、黑胶与频谱等自身的视觉特色。

## 2. 视觉设计

### 颜色和层级

颜色按用途分配：`primary` 强调重要操作；`secondary` 服务较低强调的内容；`surface` 与容器角色组织背景层级。文字和图标使用对应的 `on…` 颜色，如 `primary` 搭配 `onPrimary`。卡片装饰边界适合使用 `outlineVariant`。

来源：[M3 Color roles](https://m3.material.io/styles/color/the-color-system)。

播放器建议：播放主操作突出；排序、刷新、更多操作保持次要层级；封面提取的主题色进入完整配色体系。渐变、模糊背景和半透明覆盖层需要额外验证实际文字对比度。

### 字体和信息层级

M3 基础文字角色为 Display、Headline、Title、Body、Label，各有大小等级。文字的行高、基线和缩放同样参与布局；经常变化的时间数字适合使用等宽数字，减少跳动。

来源：[M3 Typography](https://m3.material.io/styles/typography/applying-type)。

建议映射如下，具体字号通过主题和中文显示效果调整：

| 播放器内容 | 建议角色 |
| --- | --- |
| 音乐、专辑等页面标题 | Headline |
| 歌曲和专辑名称 | Title |
| 艺术家、专辑说明 | Body |
| 按钮文字、数量、状态标签 | Label |
| 播放时间 | 适当的 Body/Label，配合等宽数字 |
| 歌词 | 独立的可读性样式，保留用户字号设置 |

### 形状与卡片

形状应形成可复用的体系，并允许品牌定制。卡片有 Elevated、Filled、Outlined 三种视觉变体，强调程度不同。项目使用的 Flutter 3.32.8 源码中，三类基础卡片默认圆角为 12 个逻辑像素；播放器现有外层卡片圆角 18 是自定义值。

来源：[Material 3 主题与形状](https://developer.android.com/develop/ui/compose/designsystems/material3)、[Flutter Card](https://api.flutter.dev/flutter/material/Card-class.html)。本地默认值核对位置：Flutter SDK 的 `packages/flutter/lib/src/material/card.dart`。

播放器建议：先确定卡片的主要变体，再统一描边、表面色和阴影。悬停抬升可以作为桌面交互定制，通过主题统一强度。专辑封面使用稳定比例，艺术家头像保持正圆。

## 3. 动效

M3 Expressive 引入弹簧物理系统，有 Expressive 与 Standard 方案。Spatial 动效处理位置、尺寸、旋转、圆角等，可有回弹；Effects 处理颜色和透明度，应避免越界回弹。两类均有 Fast、Default、Slow 分级。官方动效页对 Flutter 的实现仍标为 Unavailable，不能假定打开 M3 主题就获得这套系统。

来源：[M3 Motion physics system](https://m3.material.io/styles/motion/overview/how-it-works)。

Flutter 本身提供弹簧模拟，可用于定制实现；实现仍需处理动画打断与目标切换。自定义动效要读取系统减少动画设置。

来源：[SpringSimulation](https://api.flutter.dev/flutter/physics/SpringSimulation-class.html)、[disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html)。

以下是播放器的应用建议，不是官方指定的动画组合或参数：

| 场景 | 建议动效 | 交互要求 |
| --- | --- | --- |
| 按钮按下与释放 | 状态层反馈，必要时加入轻微形状变化 | 连续操作立即响应 |
| 音乐库卡片悬停 | 轻微抬升、表面反馈、播放按钮显现 | 键盘聚焦同样能发现操作 |
| 打开播放详情 | 封面位置与尺寸连续过渡，内容渐显 | 返回时方向与来源清楚 |
| 切换歌曲 | 新旧封面及文字过渡 | 快速切歌时只呈现最新结果 |
| 展开播放队列 | 面板位置/尺寸变化，内容透明度变化 | 支持关闭、打断和重新打开 |
| 拖动进度 | 手柄跟随输入，显示时间 | 精确定位，持续拖动不被装饰动画干扰 |
| 黑胶与频谱 | 由播放状态驱动 | 暂停、隐藏和减少动画时减少装饰活动 |

动效速度需要集中定义并按组件规模分层。现有 150ms 页面过渡、170ms 卡片过渡属于项目参数，不能作为最新 M3 弹簧规范的标准值。

## 4. 组件的职责和选择

下面的对应关系是针对播放器的设计建议；具体行为应以当前 Flutter SDK 为准。

| 用户任务 | 建议组件或模式 | 使用要点 |
| --- | --- | --- |
| 主播放操作 | FilledButton / Filled IconButton | 建立明确的主操作层级 |
| 上一首、下一首、刷新 | IconButton | 清晰提示、禁用状态与焦点反馈 |
| 音乐库封面浏览 | Card 的合适变体 | 每张卡片围绕一个歌曲、专辑或集合组织 |
| 大量歌曲检索 | ListTile / 统一歌曲行 | 标题、辅助文字、图片和操作位置稳定 |
| 列表/卡片切换 | SegmentedButton | 直接呈现少量互斥选项 |
| 格式、艺术家等条件 | FilterChip；单选条件可考虑 ChoiceChip | 让筛选状态可见、可撤销 |
| 页面导航 | NavigationRail / NavigationDrawer | 随窗口可用空间调整，保留位置感 |
| 搜索及建议 | SearchBar + SearchAnchor | 桌面弹出搜索视图与全屏搜索分别设计 |
| 播放定位、音量选择 | Slider 的交互语义，可定制绘制 | 支持拖动、键盘、数值与辅助功能 |
| 扫描、分析任务进度 | ProgressIndicator | 已知完成比例与未知进度分别表达 |
| 下一首播放、加入歌单 | MenuAnchor / 菜单 | 右键操作与可发现的入口相互补充 |
| 新建歌单、编辑设置 | Dialog / 合适的编辑面板 | 确认和取消含义清楚 |
| 简短操作结果 | SnackBar | 保持非阻塞，需要时提供撤销 |

组件依据：[Card](https://api.flutter.dev/flutter/material/Card-class.html)、[M3 Lists](https://m3.material.io/components/lists/overview)、[SegmentedButton](https://api.flutter.dev/flutter/material/SegmentedButton-class.html)、[FilterChip](https://api.flutter.dev/flutter/material/FilterChip-class.html)、[NavigationRail](https://api.flutter.dev/flutter/material/NavigationRail-class.html)、[SearchAnchor](https://api.flutter.dev/flutter/material/SearchAnchor-class.html)、[M3 Snackbar](https://m3.material.io/components/snackbar/overview)。

播放进度承担可交互的定位任务。波浪、真实音频波形等样式需要保留 Slider 的选择能力和辅助语义；任务进度条则用来告知处理状态。

依据：[Slider](https://api.flutter.dev/flutter/material/Slider-class.html)、[LinearProgressIndicator](https://api.flutter.dev/flutter/material/LinearProgressIndicator-class.html)。

## 5. 自适应与无障碍

官方提供 Feed、List-detail、Supporting pane 等典型布局，可按窗口空间组合内容。

来源：[M3 Canonical layout examples](https://m3.material.io/foundations/layout/canonical-examples/overview)。

播放器建议：宽窗口显示音乐库与可选的队列/详情侧栏；窄窗口把次要内容移到独立视图。按照逻辑尺寸布局并验证显示缩放，保持视图、选择项和滚动位置。

文字与背景的对比度需要满足其字号要求，普通小文字通常至少 4.5:1，大文字通常至少 3:1。触控目标建议至少 48×48dp；鼠标等精确输入可采用较紧凑的目标。图标可见尺寸和实际可点区域是不同概念。

来源：[Android accessibility guidance](https://developer.android.com/guide/topics/ui/accessibility/apps)、[Flutter tap target size](https://api.flutter.dev/flutter/material/ButtonStyle/tapTargetSize.html)、[平台默认目标尺寸](https://api.flutter.dev/flutter/material/ThemeData/materialTapTargetSize.html)。

播放器验收建议：Tab 聚焦、键盘激活、Esc 关闭弹层、清晰焦点、读屏标签、字体放大、减少动画，以及鼠标与触控操作均应覆盖。状态同时用文字/图标表达，辅助功能需能识别正在播放、已选和禁用。

## 6. 当前项目的落地点

以下现状来自代码阅读，属于局部核对，不是完整合规审计：

| 已观察到的实现 | 后续可改进项 |
| --- | --- |
| `entry.dart` 已设置 `useMaterial3: true` | 集中定义组件主题，逐步减少分散的样式覆盖 |
| `theme_provider.dart` 已从种子色/封面生成配色 | 检查覆盖层、渐变和所有自定义组件的实际配色对比 |
| `side_nav.dart` 已使用 NavigationDrawer 与 NavigationRail | 保持现有自适应逻辑，评估宽屏队列/详情的布局 |
| 卡片已有悬停、焦点、选择与播放状态 | 将字体、圆角和状态视觉整理成统一定义 |
| `appearance.dart` 已考虑关闭动效、系统减少动画和 TickerMode | 统一检查所有路由和自定义过渡是否遵循相同偏好 |
| 路由过渡仍固定 150ms、使用 `fastOutSlowIn` | 按导航关系设计过渡，再集中接入动效偏好 |
| 卡片标题/说明仍有局部字号 15、12 | 用 TextTheme 角色承载统一的中文排版与缩放策略 |
| 卡片歌单菜单容器有 28×28 限制 | 按实际输入方式检查点击范围、聚焦与触控可用性 |

项目当前工具链已核对为 Flutter 3.32.8。本地源码具备 Card 变体、SegmentedButton、SearchBar/SearchAnchor、NavigationRail/Drawer、Slider 和 SpringSimulation。在线最新文档可能对应更新的平台实现；后续改动须先核对版本支持，再决定实现方式。

建议推进顺序：先统一主题、排版和组件状态，再优化搜索与视图切换，随后处理迷你播放器到播放页的连续过渡，最后设计宽屏队列/详情。每一步结合真实播放、键盘操作、窗口缩放与动效关闭进行验证。
