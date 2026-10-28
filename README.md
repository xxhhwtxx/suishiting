# 随时听 · Anytime Music

一款轻便的 Android 音乐客户端，支持网易云音乐与 QQ 音乐。在手机上搜索歌曲、播放音乐、查看歌词和管理下载。

[下载 Android 安装包](https://github.com/xxhhwtxx/suishiting/releases)

## 功能

* 双平台切换，支持关键词、歌曲 ID 和歌曲链接。
* 扫码登录，两个平台账号独立管理，登录状态保存在本机。
* 播放、暂停、进度调节与同步歌词，支持优先音质设置。
* 下载队列、取消与重试，已下载歌曲可本地播放、分享导出。
* 深色模式与大字体适配。
* 设置页检查更新，下载新版并通过系统安装界面完成升级。

## 使用

安装 APK 后，在搜索页选择音乐平台并输入歌名或歌手。需要账号权限的曲目，可在「账号与设置」登录自己的对应平台账号。二维码也可以使用另一台设备扫描。

歌曲可用性与音质取决于曲目及账号权限；试听音源会单独标识。下载文件保存在应用私有目录，可在下载页分享导出。当前支持前台播放和进程内下载。

更新入口：**账号与设置 → 应用更新 → 检查更新**。发现新版本后，下载并点击「安装新版」，按系统提示确认。首次安装更新可能需要允许随时听安装应用。

## 开发

使用 Flutter 3.44 / Dart 3.12、JDK 21，最低 Android 7.0。

```sh
cd packages/music163_core
flutter pub get
flutter analyze
flutter test

cd ../../app
flutter pub get
flutter analyze
flutter test test/widget_test.dart
flutter build apk --release
```

`app/` 为应用界面与 Android 宿主，`packages/music163_core/` 为业务逻辑。验证范围见 [VALIDATION.md](VALIDATION.md)，发布方式见 [RELEASING.md](RELEASING.md)。

## 许可证

[GPL-3.0](LICENSE)。第三方许可证与版权信息保存在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
