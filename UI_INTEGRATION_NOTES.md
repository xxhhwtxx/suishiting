# UI 界面对接与集成说明 (`UI_INTEGRATION_NOTES.md`)

## 1. 界面实现文件清单

本次界面实现严格遵循 `INTERFACE_CONTRACT.md` 及其顶部双平台增量契约，仅修改允许范围内的文件，未改动 `packages/music163_core` 与 `app/android`：

* `app/assets/branding/app_icon.svg`：「随时听」品牌图标源文件（1024×1024 矢量 SVG，深邃黑胶圆角底座 + 耳机头梁耳罩 + 鎏金律动八分音符，无任何文字，针对安卓小尺寸图标优化辨识度）。
* `app/lib/main.dart`：应用入口与 `MyApp`（别名 `Music163App`），品牌名称统一为「随时听」；支持 `MyApp(core: core)` 直接注入及默认 `Music163Core.create()` 异步初始化、失败状态展示与点击重试，并在组件销毁/宿主退出时调用 `core.close()`。
* `app/lib/ui/theme/app_theme.dart`：中文 Material 3 主题（「随时听」黑胶绯红与曜石深色/宣纸浅色配色、最小 48dp 触控尺寸、圆角与试听警示色板）。
* `app/lib/ui/utils/formatters.dart`：纯函数格式化工具（时长、字节大小、下载进度百分比、音源等级与码率标签、支持 `source.level == 'local'` 显示「本地文件」、双平台完整覆盖 `QrStatus` 的 `idle`/`waiting`/`scanned`/`authorizing`/`success`/`expired`/`failed`/`refused` 八种状态、LRC 歌词时间轴解析与当前行计算）。
* `app/lib/ui/shell/home_shell.dart`：响应式主导航骨架（手机竖屏 `NavigationBar` + 宽屏/横屏 `NavigationRail`、顶栏展示「随时听 `Anytime Music`」中英双语品牌标题及右上角 GitHub 主页入口按钮与日夜主题切换按钮、下载角标与双平台任一账号登录状态绿点、底部常驻 `MiniPlayerBar`）。
* `app/lib/ui/pages/search_page.dart`：双平台搜索与曲目解析页（顶部提供「网易云音乐 / QQ 音乐」平台切换栏调用 `core.search.setPlatform(MusicPlatform)`；根据当前平台动态切换输入框提示、空状态引导与无结果提示，支持 QQ 关键词、数字 ID、`songmid` 及 `y.qq.com` 链接；全部曲目比较、下载任务映射与组件 Key 统一使用 `song.key`；展示 `song.platform.label` 徽章与 `ID: ${song.displayId}`）。
* `app/lib/ui/pages/downloads_page.dart`：下载任务管理页（按 `song.key` 关联播放状态，展示曲目所属平台 `song.platform.label` 与 `ID: ${song.displayId}`、进度条与字节统计；支持取消、重试、调用 `core.player.playLocal(task.song, task.path!)` 直接离线播放本地文件、`share_plus` 系统分享导出，以及删除文件与记录前的二次确认弹窗）。
* `app/lib/ui/pages/account_settings_page.dart`：双平台账号、音质与应用更新设置页（同时展示并独立管理网易云音乐 `core.auth` 与 QQ 音乐 `core.qqAuth` 登录状态；网易云支持 `qr_flutter` 本地渲染 `qrSession.loginUrl` 与遮挡输入 `MUSIC_U`；QQ 音乐支持 `Image.memory(qqAuth.qrBytes!)` 渲染手机 QQ 登录二维码与 `qqAuth.qrExpiresAt` 有效期展示，在 `authorizing` 阶段隐藏旧二维码与有效期并禁止重复生成，区分 `failed`/`refused`/`expired` 状态并在二维码卡片就地展示真实错误 `qq_qr_error_banner`，登录成功但资料暂未同步时仍保持展示已登录状态；支持 `AudioQuality` 四档优先音质切换；底部挂载 `UpdateCard` 应用更新卡片；不包含关于与开源说明卡片）。
* `app/lib/ui/widgets/update_card.dart`：1.2.0 应用内检查 GitHub Releases 更新与安装卡片（组件初始化时调用 `core.updates.initialize()` 读取当前版本号；支持 `UpdateStatus` 全部状态：展示当前版本与「检查更新」、`noRelease`「暂无可用更新」、`upToDate`「已是最新版本」、`available` 新版本号/APK 大小/纯文本更新说明与下载按钮、`downloading` 进度条/字节进度与取消下载、`ready`「安装新版」、`permissionRequired`「请允许随时听安装应用」及「去设置」`openInstallSettings()` 与「重试安装」`install()` 按钮、`failed` 错误横幅与重试操作）。
* `app/lib/ui/widgets/player_bar.dart`：底部常驻 `MiniPlayerBar` 与可展开的 `NowPlayingSheet`（展示 `song.platform.label` 与 `ID: ${song.displayId}`，按 `song.key` 匹配下载任务与歌词请求代次，调用 `core.repository.lyricsFor(song)` 获取双平台同步 LRC 歌词并支持点击歌词跳转进度）。
* `app/lib/ui/widgets/song_cover.dart`：安全加载网络封面与头像组件（带 `errorBuilder` 黑胶占位与「随」字默认头像回退）。
* `app/test/widget_test.dart`：共 8 项 Widget 测试，完整覆盖初始化失败重试、网易云搜索与试听标识、LRC 歌词抽屉、下载完成任务 `playLocal` 本地播放与分享/删除确认、网易云扫码与遮挡导入 `MUSIC_U`、QQ 音乐平台切换与跨平台相同数字 ID 按 `song.key` 隔离及 `lyricsFor(Song)`、QQ 音乐二维码 `Image.memory` 渲染与遮挡导入凭据 `importCredential`、QQ 扫码有效期展示与 `authorizing`/`failed`/`refused` 状态不误报过期及资料暂未同步时保持已登录、设置页应用更新卡片检查/发现新版/下载进度与取消/安装权限引导及重试安装全流程。

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
