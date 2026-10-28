# music163_core

Flutter 网易云音乐业务包，无 Widget，无 Telegram/服务器依赖。

```dart
final core = await Music163Core.create();
await core.search.search('歌名 / 歌曲ID / 分享链接');
await core.player.play(core.search.songs.first);
await core.downloads.enqueue(core.search.songs.first);
```

使用 ListenableBuilder 监听 core.search、core.auth、core.player、core.downloads。
模型、方法、错误和生命周期详见根目录 INTERFACE_CONTRACT.md。
关闭调用 await core.close()。Cookie 写入加密存储，不打印账号凭据。

音源由真实网易云接口与账号权限决定。首版为前台播放和进程内下载，未实现后台服务或断点续传。

协议来源 XiaoMengXinX/Music163Api-Go，按 GPL-3.0 分发，详见 LICENSE 和根目录 THIRD_PARTY_NOTICES.md。
