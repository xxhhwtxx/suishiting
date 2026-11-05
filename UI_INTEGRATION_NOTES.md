# UI 界面对接与集成说明 (`UI_INTEGRATION_NOTES.md`)

## 1. 界面实现文件清单

本次界面实现严格遵循 `INTERFACE_CONTRACT.md` 及其顶部 1.3.0 简洁播放器与推荐/收藏增量契约，仅修改允许范围内的文件，未改动 `packages/music163_core` 与 `app/android`：

* `app/assets/branding/app_icon.svg`：「随时听」品牌图标源文件（1024×1024 矢量 SVG，深邃黑胶圆角底座 + 耳机头梁耳罩 + 鎏金律动八分音符，无任何文字，针对安卓小尺寸图标优化辨识度）。
* `app/lib/main.dart`：应用入口与 `MyApp`（别名 `Music163App`），品牌名称统一为「随时听」；默认使用浅色主题（`ThemeMode.light`），并由 `core.library.themePreference` 驱动主题切换与跨重启持久化；支持 `MyApp(core: core)` 直接注入及默认 `Music163Core.create()` 异步初始化、失败状态展示与点击重试，并在组件销毁/宿主退出时调用 `core.close()` 与 `AppSnackBar.cancel()`。
* `app/lib/ui/theme/app_theme.dart`：中文 Material 3 主题（「随时听」黑胶绯红与曜石深色/宣纸浅色配色、最小 48dp 触控尺寸、圆角与试听警示色板）。
* `app/lib/ui/utils/app_snackbar.dart`：统一短提示工具（`AppSnackBar.show` 调用 `clearSnackBars()` 并设置 `duration: Duration(seconds: 2)`，同时通过显式 `Timer` 在 2 秒后调用 `controller.close()`，确保即使附带 `SnackBarAction` 或开启系统无障碍导航 `accessibleNavigation` 也能在约 2 秒后自动消失）。
* `app/lib/ui/utils/formatters.dart`：纯函数格式化工具（时长、字节大小、下载进度百分比、音源等级与码率标签、支持 `source.level == 'local'` 显示「本地文件」、双平台完整覆盖 `QrStatus` 八种状态、支持 `[offset:+/-ms]` 偏移与单行多时间标签的 `parseLrc` 歌词时间轴解析、去除时间/元数据标签并按原顺序保留正文的 `plainLyricsText`、播放模式 `PlaybackMode` 与主题偏好 `AppThemePreference` 标签格式化）。
* `app/lib/ui/shell/home_shell.dart`：响应式主导航骨架（手机竖屏 `NavigationBar` + 宽屏/横屏 `NavigationRail` 五栏导航：「推荐 / 搜索 / 收藏 / 下载 / 设置」；顶栏展示「随时听 `Anytime Music`」中英双语品牌标题及右上角 GitHub 主页入口按钮与日夜主题切换按钮 `core.library.setTheme(...)`、收藏数量角标、下载角标与双平台任一账号登录状态绿点、底部常驻 `MiniPlayerBar`）。
* `app/lib/ui/pages/recommendations_page.dart`：1.3.0 双平台真实推荐页（仅在页面首次展示或用户手动切换平台/点击刷新/下拉刷新时调用 `core.recommendations.load` / `setPlatform`，不在 `build` 中触发请求；顶部操作栏采用自适应 `Wrap` 布局展示 `sourceLabel`、「播放全部」与刷新按钮，兼容 390px 窄屏与 1.4x 大字体；点击曲目调用 `core.player.playQueue(rec.songs, startIndex: index)`，支持一键收藏与下载）。
* `app/lib/ui/pages/search_page.dart`：双平台搜索与曲目解析页（顶部提供「网易云音乐 / QQ 音乐」平台切换栏与简洁输入栏，移除首页大段搜索教程卡片；空搜索词时展示 `core.library.history` 最近搜索历史芯片，支持点击复搜、单条删除 `removeSearch` 与清空历史 `clearHistory`；列表支持「播放全部」队列播放 `playQueue`、单曲收藏切换 `toggleFavorite` 与下载；全部曲目比较与组件 Key 统一使用 `song.key`）。
* `app/lib/ui/pages/favorites_page.dart`：1.3.0 本机收藏页（展示 `core.library.favorites`，支持「播放全部」队列播放、点击单曲从当前位置队列播放、取消本机收藏与下载操作）。
* `app/lib/ui/pages/downloads_page.dart`：下载任务管理页（支持「播放全部」已完成本地音频队列；展示曲目所属平台与 `ID: ${song.displayId}`、进度条与字节统计；新增 `task.lyricsPath` 已存 LRC 歌词标识、未保存歌词时的「保存歌词」`core.downloads.saveLyrics(task.id)` 按钮及 `.lrc` 歌词文件分享入口；支持 `core.player.playLocal` 离线播放本地文件与删除确认）。
* `app/lib/ui/pages/account_settings_page.dart`：双平台账号、音质、外观偏好、使用说明与应用更新设置页（独立管理网易云音乐 `core.auth` 与 QQ 音乐 `core.qqAuth` 登录状态；支持 `AudioQuality` 四档优先音质切换；新增「外观与歌词下载设置」卡片，支持浅色/深色/跟随系统主题切换及「下载歌曲时同步保存 LRC 歌词」开关 `core.library.setDownloadLyrics`；新增默认收起的 `ExpansionTile`「搜索教程与使用说明」收纳全部搜索语法与产品说明；底部挂载 `UpdateCard` 应用更新卡片）。
* `app/lib/ui/widgets/update_card.dart`：1.2.0 应用内检查 GitHub Releases 更新与安装卡片（覆盖 `UpdateStatus` 全部状态：检查更新、暂无更新、已是最新、发现新版与更新说明、下载进度与取消、安装新版、缺少未知来源安装权限引导去设置与重试安装）。
* `app/lib/ui/widgets/player_bar.dart`：底部常驻 `MiniPlayerBar`（新增队列下一首快捷按钮，点击曲目信息区或展开按钮打开完整播放页）与大封面 `NowPlayingSheet`（封面尺寸在手机端按可用宽度减 48 自适应、平板端最大 420；包含本机收藏按钮、进度拖拽条、播放模式循环切换 `sequence`/`repeatAll`/`repeatOne`/`shuffle`、上一首/播放暂停/下一首、播放队列底部弹层 `_PlaybackQueueSheet`；监听 `player` 曲目切换自动刷新 `core.repository.lyricsFor(song)` 本地/在线歌词，支持同步高亮滚动并尊重 `MediaQuery.disableAnimationsOf(context)` 减少动画设置，提供「复制全文」按钮复制纯文本歌词）。
* `app/lib/ui/widgets/song_cover.dart`：安全加载网络封面与头像组件（带 `errorBuilder` 黑胶占位与「随」字默认头像回退）。
* `app/test/widget_test.dart`：共 10 项 Widget 测试，完整覆盖初始化失败重试、网易云搜索与试听标识、LRC 歌词抽屉、下载完成任务 `playLocal` 本地播放与分享/删除确认、网易云扫码与遮挡导入 `MUSIC_U`、QQ 音乐平台切换与跨平台相同数字 ID 按 `song.key` 隔离、QQ 音乐二维码 `Image.memory` 渲染与遮挡导入凭据、QQ 扫码有效期展示与 `authorizing`/`failed`/`refused` 状态不误报过期、设置页应用更新卡片全流程、1.3.0 双平台推荐与队列播放/上下的歌自动刷新歌词/LRC `offset` 与多时间标签解析/复制整首歌词、以及搜索历史/收藏页/默认浅色主题与重启持久化/折叠说明/无障碍模式下带 Action 的 SnackBar 2 秒定时自动关闭。

---

## 2. 对接过程中发现的契约与依赖问题记录

1. **跨平台曲目主键与下载任务关联（已统一使用 `song.key`）**
   * **处理**：搜索结果卡片、播放状态判断（`player.currentSong?.key == song.key`）、下载任务映射（`task.id == song.key || task.song.key == song.key`）以及歌词请求代次跟踪均已改为使用 `song.key`，避免网易云与 QQ 音乐存在相同数字 `id` 时发生状态串台或 Widget Key 冲突。

2. **已完成下载任务的离线本地播放（已接入 `core.player.playLocal`）**
   * **处理**：下载页针对 `DownloadState.completed` 且存在本地路径的任务，点击「播放曲目」直接调用 `core.player.playLocal(task.song, path)`，播放器状态栏展示 `source.level == 'local'`（「本地文件」），断网状态下也可直接播放已下载音频。

3. **`share_plus` 与 `flutter_secure_storage` 的版本约束冲突（已在 `app/pubspec.yaml` 解决）**
   * **处理**：`app/pubspec.yaml` 中使用 `share_plus: ^13.3.1`（兼容 `win32: ^6.0.1`），并在下载页使用 `SharePlus.instance.share(ShareParams(files: [XFile(path)], ...))` 接口。

4. **`SearchController` 命名与 Flutter Material 内置组件同名**
   * **处理**：在同时引入 `package:flutter/material.dart` 与 `package:music163_core/music163_core.dart` 的 UI 文件中使用 `import 'package:flutter/material.dart' hide SearchController;`，确保 `SearchController` 唯一指向 `music163_core` 的搜索控制器。
