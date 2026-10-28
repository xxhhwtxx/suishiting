# Flutter 界面对接契约

## 1.2.0 检查更新（最新增量）

Codex 实现 GitHub Releases 检查/下载/校验/安卓安装逻辑和原生通道；Gemini 仅实现设置页更新卡片及对接测试，保留用户刚修改的「随时听 Anytime Music」顶栏与 GitHub 主页按钮。不要改业务包、Android、版本号或其他页面。

* 新增 `core.updates: UpdateController`（ChangeNotifier）。`status:UpdateStatus`：idle/checking/noRelease/upToDate/available/downloading/ready/permissionRequired/installing/failed。
* 属性：`currentVersionName:String?`、`release:AppRelease?`、`error:String?`、`message:String?`、`downloadedBytes:int`、`totalBytes:int?`、`progress:double?`、`isBusy:bool`、`hasDownloadedFile:bool`、`repositoryUrl:Uri`。
* `AppRelease`：`version:String`、`notes:String`（纯文本）、`size:int`、`pageUrl:Uri`。
* 方法：`Future<void> initialize()`（仅加载本机版本，可在设置页 initState 触发，不发网络请求）、`Future<void> check()`、`Future<void> download()`、`void cancelDownload()`、`Future<void> install()`、`Future<void> openInstallSettings()`。
* 更新源默认 `xxhhwtxx/suishiting`。设置页增加「应用更新」卡片，显示当前版本与检查按钮；未发 Release 显示“暂无可用更新”，upToDate 显示“已是最新版本”，available 展示新版本/大小/更新内容和下载按钮；downloading 展示进度与取消；ready 提供“安装新版”。failed 显示 error 并可重试检查或下载。
* permissionRequired 显示“请允许随时听安装应用”，提供“去设置”和“重试安装”；安装由系统确认，不承诺静默安装。用户返回后可重试安装。不要自动跳转系统设置。
* UI 只调用上述逻辑，不另写 HTTP/下载/原生安装，不新增复杂页面。更新内容按普通文本展示。对接测试可以通过 Music163Core.create(updater: fakeUpdater) 注入控制器；控制器依赖可测试，Codex 会提供实现。


## 1.1.2 QQ 扫码修复增量（最高优先）

Codex 修复业务；Gemini 仅调整 app/lib/ui/utils/formatters.dart、app/lib/ui/pages/account_settings_page.dart 与相关 Widget 测试。品牌和其他页面不变。

* `QrStatus` 新增 `authorizing`（QQ 已确认，正在完成音乐授权）、`failed`（授权/存储失败，显示真实错误，可重新获取）、`refused`（用户取消授权）。仅真正超时或 QQ 返回 65 才用 `expired`。
* `core.qqAuth.qrExpiresAt:DateTime?`，展示与网易云类似的“有效期至 HH:mm:ss”；没有二维码或已进入 authorizing 时不要继续显示旧二维码和过期时间。
* authorizing 时 `isBusy=true`、qrBytes=null，显示正在完成 QQ 音乐登录，不显示过期文案。failed/refused 状态显示错误色，提供现有重新获取按钮，不需要新页面。
* 两个平台的 qrStatusLabel switch 都需覆盖新枚举，网易云原有正常登录流程不改。QQ 成功与资料请求分离：已保存登录凭据后资料失败会保留成功登录，可能显示“已登录，账号资料暂未同步”。
* 增加 Widget 回归测试，确保“QQ 已确认、授权中/授权失败”不出现“二维码已过期”，并验证 QQ 有效期文本。不能在 UI 伪造成功或吞掉 error。其余业务由 Codex 完成。


## 新版双平台增量契约（优先于下文旧签名）

本版必须包含网易云和 QQ 音乐；Codex 实现业务，Gemini 实现 UI。Gemini 只改 app/lib、app/test，不能改业务包、Android、版本号。不要恢复关于或开源页面。

* 新增 `MusicPlatform.netease` / `MusicPlatform.qq`，每项 `.label` 为平台中文名。
* `Song` 保留 `id:int`；新增 `platform:MusicPlatform`（默认 netease）、`mid:String?`、`mediaMid:String?`、`key:String`、`displayId:String`。`key` 用于所有歌曲比较、任务关联和控件 Key（网易云保持旧数字字符串，QQ 为 qq_MID）；不要再单用 id 比较不同平台曲目。
* `core.search.platform` 当前搜索平台；`Future<void> core.search.setPlatform(MusicPlatform)` 切换后重新搜索当前 query；支持 QQ 关键词、数字 ID、songmid、y.qq.com 歌曲链接。
* 新增 `Future<String> core.repository.lyricsFor(Song song)`，播放器歌词改调用该方法，歌词请求代次以 song.key 比较。旧 lyrics(int) 保留兼容。
* 新增 `core.qqAuth`（ChangeNotifier）：`isBusy:bool`、`isLoggedIn:bool`、`profile:AccountProfile?`、`error:String?`、`qrBytes:Uint8List?`、`qrStatus:QrStatus`；`Future<void> createQr()`、`void cancelQr()`、`Future<void> importCredential(String)`、`Future<void> refresh()`、`Future<void> logout()`。QQ 二维码用 `Image.memory(qrBytes)` 显示，由 QQ 返回，不是 qr_flutter 编码 URL；提示使用 QQ 扫码并确认（可另一台设备）。导入框默认遮挡，接受 QQ 音乐完整 Cookie 或凭据 JSON（musicid、musickey），禁止日志或持久化到普通文件。
* `core.auth` 仍是网易云账号；QQ 和网易云登录彼此独立。设置页展示两者各自登录入口与状态。没有 QQ 凭据也可搜索；播放失败直接展示业务 error。
* 播放、下载仍使用 `play(Song)` / `enqueue(Song)`，内部自动按曲目平台选择 API。任务 id 对应 song.key，已保存网易云记录兼容。搜索、下载、播放器适当显示平台名，避免混淆。
* Gemini 添加平台切换控件，更新搜索提示/空状态（不要将 QQ 曲目说成网易云），完成以上所有 UI 对接和相关 Widget 测试。先写代码；Codex 实现契约期间可能暂时无法 analyze，完成后再检查。


用户指定：Codex 写逻辑，Antigravity/Gemini 写界面。独立 Android App，无服务器，无 Telegram Token。

`packages/music163_core` 是业务包，`app` 是 Flutter 安卓应用。界面只改 `app/lib/**`、`app/test/**`、必要图像/字体资源；不得另写 HTTP、播放、下载、登录逻辑。

## 初始化

```dart
import 'package:music163_core/music163_core.dart';
WidgetsFlutterBinding.ensureInitialized();
final core = await Music163Core.create();
runApp(MyApp(core: core));
```

`core`、`core.search`、`core.auth`、`core.player`、`core.downloads` 都是 ChangeNotifier。用 ListenableBuilder 监听，不需要 Provider 依赖。宿主关闭前调用 `await core.close()`。

## 稳定 API（实现由 Codex 负责）

* `core.search`: `query:String`, `songs:List<Song>`, `isLoading:bool`, `isLoadingMore:bool`, `hasMore:bool`, `error:String?`; `Future<void> search(String text)`, `Future<void> loadMore()`。支持关键词、数字歌曲 ID、网易云分享长短链接。页面主动点搜索；翻页可用按钮。
* `core.auth`: `isBusy:bool`, `isLoggedIn:bool`, `profile:AccountProfile?`, `error:String?`, `qrSession:QrSession?`, `qrStatus:QrStatus`; `Future<void> createQr()`, `void cancelQr()`, `Future<void> importMusicU(String cookieOrValue)`, `Future<void> logout()`, `Future<void> refresh()`。二维码由 `qrSession.loginUrl` 在设备本地生成，禁止第三方二维码服务。自动检查登录状态；提示可用另一台设备扫码，也可输入 MUSIC_U；输入框遮挡凭据。
* `core.player`: `currentSong:Song?`, `isPlaying:bool`, `isLoading:bool`, `position:Duration`, `duration:Duration`, `source:MediaSource?`, `error:String?`; `Future<void> play(Song)`, `Future<void> pause()`, `Future<void> resume()`, `Future<void> seek(Duration)`, `Future<void> stop()`。
* `core.downloads`: `tasks:List<DownloadTask>`, `error:String?`; `Future<void> enqueue(Song)`, `void cancel(String id)`, `Future<void> retry(String id)`, `Future<void> remove(String id)`。下载在 App 私有目录，可由 UI 使用 `share_plus` 分享已完成的本地文件。`remove` 删除文件和记录，应有 UI 确认。
* `core.quality:AudioQuality`，`Future<void> core.setQuality(AudioQuality)`。音质仅代表优先请求值，最终以源文件实际权限为准。
* `Future<String> core.repository.lyrics(int songId)` 返回 LRC 歌词；UI 可决定是否展示。

### 模型

`Song`: `id:int`, `name:String`, `artists:String`, `album:String`, `artworkUrl:String?`, `duration:Duration`。

`AccountProfile`: `id:int`, `nickname:String`, `avatarUrl:String?`。

`AudioQuality`: `standard`, `higher`, `lossless`, `hires`；每项有 `.label:String`。

`QrSession`: `loginUrl:String`, `expiresAt:DateTime`；`QrStatus`: `idle`, `waiting`, `scanned`, `success`, `expired`。

`MediaSource`: `url:Uri`, `extension:String`, `level:String`, `bitrate:int`, `isTrial:bool`。试听提示必须可见，不能宣称完整音源。

`DownloadTask`: `id:String`, `song:Song`, `state:DownloadState`, `progress:double?` (0..1), `downloadedBytes:int`, `totalBytes:int?`, `path:String?`, `error:String?`, `isActive:bool`。

`DownloadState`: `queued`, `resolving`, `downloading`, `completed`, `failed`, `cancelled`。

## 界面范围

补充业务 API：`Future<void> core.player.playLocal(Song song, String path)`。下载完成的任务请用该方法播放本地文件，避免下载页点播放还需联网。`source.level == 'local'` 表示本地播放。

由 Gemini 决定视觉和布局，中文优先，使用 Material 3，照顾深色模式、键盘、系统边距、大字体和 48dp 触控区域。完成搜索结果/空状态/错误/加载、播放进度/暂停、下载记录/重试/取消/分享、账号登录/退出和音质设置。按用户要求，设置页不展示关于、开源说明或许可证入口；源码中的 LICENSE 和第三方声明保留。不要虚构推荐歌曲或账号、不要增加服务器地址和 Bot Token 表单。

界面入口需能处理初始化失败，提供重试。声明这是基于 Music163bot-Go 的独立客户端改造，歌曲可用性由网易云接口及账号权限决定。基础版播放器为前台播放；不承诺已完成后台播放服务。

## 约束

禁止日志打印 Cookie，禁止把 MUSIC_U 发给第三方。业务层处理音源权限和试听下载限制。不要修改 packages/music163_core；发现接口问题写到 `UI_INTEGRATION_NOTES.md`。运行 Flutter 命令使用 `D:\flutter-sdk\bin\flutter.bat`。可以增加 `qr_flutter`、`share_plus` 的 app 依赖，并在 README 写清更改。
