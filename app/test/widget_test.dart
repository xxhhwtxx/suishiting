import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_app/main.dart';
import 'package:music163_core/music163_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

final Uint8List _kValidPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _FakeAudioBackend implements AudioBackend {
  final StreamController<AudioEvent> _events =
      StreamController<AudioEvent>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  Uri? lastLoadedUrl;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = const Duration(minutes: 3, seconds: 20);

  void emitState() {
    if (_events.isClosed) return;
    _events.add(
      AudioEvent(
        playing: isPlaying,
        loading: false,
        completed: false,
        position: currentPosition,
        duration: totalDuration,
      ),
    );
  }

  @override
  Stream<AudioEvent> get events => _events.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> load(Uri url) async {
    lastLoadedUrl = url;
    emitState();
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    emitState();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    emitState();
  }

  @override
  Future<void> seek(Duration position) async {
    currentPosition = position;
    emitState();
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    currentPosition = Duration.zero;
    emitState();
  }

  @override
  Future<void> close() async {
    await _events.close();
    await _errors.close();
  }
}

class _FakeUpdateController extends UpdateController {
  String checkMode = 'available';
  bool pauseDownload = false;
  bool canInstall = false;
  bool hasLocalApk = false;
  int checkCount = 0;
  int downloadCount = 0;
  int cancelCount = 0;
  int installCount = 0;
  int openSettingsCount = 0;

  static final sampleRelease = AppRelease(
    version: '1.3.0',
    notes: '1. 新增应用内检查更新\n2. 优化双平台播放体验',
    size: 25690112,
    pageUrl: Uri.parse(
      'https://github.com/xxhhwtxx/suishiting/releases/tag/v1.3.0',
    ),
    downloadUrl: Uri.parse(
      'https://github.com/xxhhwtxx/suishiting/releases/download/v1.3.0/suishiting-1.3.0.apk',
    ),
    sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    assetId: 1001,
  );

  @override
  bool get hasDownloadedFile => hasLocalApk;

  @override
  Future<void> initialize() async {
    if (closed) return;
    installed = const InstalledAppInfo(versionName: '1.2.0', versionCode: 4);
    changed();
  }

  @override
  Future<void> check() async {
    if (isBusy || closed) return;
    checkCount++;
    error = null;
    message = null;
    hasLocalApk = false;
    if (checkMode == 'noRelease') {
      release = null;
      status = UpdateStatus.noRelease;
      message = '暂无可用更新';
    } else if (checkMode == 'upToDate') {
      release = null;
      status = UpdateStatus.upToDate;
      message = '已是最新版本';
    } else if (checkMode == 'failed') {
      status = UpdateStatus.failed;
      error = '更新检查暂时受限，请稍后重试。';
    } else {
      release = sampleRelease;
      status = UpdateStatus.available;
    }
    changed();
  }

  @override
  Future<void> download() async {
    if (isBusy || closed || release == null) return;
    downloadCount++;
    error = null;
    message = null;
    totalBytes = release!.size;
    if (pauseDownload) {
      status = UpdateStatus.downloading;
      downloadedBytes = 12845056;
      changed();
      return;
    }
    downloadedBytes = release!.size;
    hasLocalApk = true;
    status = UpdateStatus.ready;
    message = '下载完成，可以安装新版';
    changed();
  }

  @override
  void cancelDownload() {
    cancelCount++;
    status = UpdateStatus.available;
    message = '下载已取消';
    error = null;
    changed();
  }

  @override
  Future<void> install() async {
    if (isBusy || closed || !hasLocalApk || release == null) return;
    installCount++;
    error = null;
    if (!canInstall) {
      status = UpdateStatus.permissionRequired;
      message = '请允许随时听安装应用';
    } else {
      status = UpdateStatus.ready;
      message = '请在系统安装界面完成更新';
    }
    changed();
  }

  @override
  Future<void> openInstallSettings() async {
    openSettingsCount++;
    canInstall = true;
    changed();
  }
}

Future<Music163Core> _createTestCore({
  required Directory tempDir,
  required _MemoryCredentialStore store,
  required _FakeAudioBackend audio,
  UpdateController? updater,
}) {
  final client = MockClient((request) async {
    final path = request.url.path;

    if (path.contains('/ptqrshow')) {
      return http.Response.bytes(
        _kValidPngBytes,
        200,
        headers: {
          'content-type': 'image/png',
          'set-cookie': 'qrsig=test_qq_sig; Path=/',
        },
      );
    }

    if (path.contains('/lyric/fcgi-bin/fcg_query_lyric_new.fcg')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'lyric': '[00:00.00]刮风这天我试过握着你手\n[00:05.00]但偏偏雨渐渐大到我看你不见',
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/cgi-bin/musicu.fcg')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final req0 = body['req_0'] as Map<String, dynamic>? ?? {};
      final method = req0['method'] as String? ?? '';

      if (method == 'do_search_v2') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'req_0': {
                'code': 0,
                'data': {
                  'body': {
                    'item_song': {
                      'items': [
                        {
                          'id': 101,
                          'mid': '0039MnYb0qxYhV',
                          'name': '晴天（QQ 音乐版）',
                          'singer': [
                            {'name': '周杰伦'},
                          ],
                          'album': {'name': '叶惠美', 'mid': '002Neh8l0uciQZ'},
                          'interval': 269,
                          'file': {'media_mid': '0039MnYb0qxYhV'},
                        },
                      ],
                    },
                  },
                  'meta': {'sum': 1},
                },
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      if (method == 'UrlGetVkey') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'req_0': {
                'code': 0,
                'data': {
                  'sip': ['https://isure.stream.qqmusic.qq.com/'],
                  'midurlinfo': [
                    {
                      'result': 0,
                      'purl': 'M8000039MnYb0qxYhV.mp3?vkey=test',
                      'isTry': 0,
                    },
                  ],
                },
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      if (method == 'GetLoginUserInfo') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'req_0': {
                'code': 0,
                'data': {
                  'code': 0,
                  'userInfo': {'nick': 'QQ 测试乐迷', 'headurl': ''},
                },
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }

    if (path.contains('/eapi/v1/search/song/get')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 200,
            'result': {
              'songCount': 2,
              'hasMore': false,
              'songs': [
                {
                  'id': 101,
                  'name': '晴天（测试曲目）',
                  'ar': [
                    {'name': '周杰伦'},
                  ],
                  'al': {'name': '叶惠美'},
                  'dt': 269000,
                },
                {
                  'id': 102,
                  'name': '夜曲（完整音源）',
                  'ar': [
                    {'name': '周杰伦'},
                  ],
                  'al': {'name': '十一月的萧邦'},
                  'dt': 226000,
                },
              ],
            },
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/eapi/song/enhance/player/url/v1')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 200,
            'data': [
              {
                'url': 'https://m8.music.126.net/test/101.mp3',
                'type': 'mp3',
                'level': 'higher',
                'br': 320000,
                'freeTrialInfo': {'start': 0, 'end': 30000},
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/eapi/song/lyric')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 200,
            'lrc': {'lyric': '[00:00.00]故事的小黄花\n[00:04.50]从出生那年就飘着'},
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/eapi/login/qrcode/unikey')) {
      return http.Response.bytes(
        utf8.encode(jsonEncode({'code': 200, 'unikey': 'local-test-qr-key'})),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path.contains('/eapi/w/nuser/account/get')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'code': 200,
            'profile': {'userId': 9527, 'nickname': '测试音乐人'},
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    return http.Response.bytes(
      utf8.encode(jsonEncode({'code': 200})),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  return Music163Core.create(
    credentialStore: store,
    client: client,
    updater: updater,
    audioBackend: audio,
    downloadDirectory: tempDir,
  );
}

Future<void> _pumpRealIo(WidgetTester tester, {int cycles = 10}) async {
  for (var i = 0; i < cycles; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
    });
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _cleanupTestCore(
  WidgetTester tester,
  Music163Core? core,
  Directory tempDir,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  if (core != null) {
    final closing = core.close();
    await _pumpRealIo(tester);
    await closing;
  }
  await tester.runAsync(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
}

void main() {
  testWidgets('初始化失败时展示错误状态并支持点击重试进入主界面', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    Music163Core? core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_init_');
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      var attempts = 0;
      Uri? openedUrl;
      await tester.pumpWidget(
        MyApp(
          openExternalUrl: (uri) async {
            openedUrl = uri;
            return true;
          },
          coreLoader: () async {
            attempts++;
            if (attempts == 1) {
              throw const MusicException('模拟存储初始化异常');
            }
            return core!;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bootstrap_error_view')), findsOneWidget);
      expect(find.textContaining('模拟存储初始化异常'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bootstrap_retry_button')));
      await tester.pumpAndSettle();

      expect(find.text('随时听'), findsOneWidget);
      expect(find.text('Anytime Music'), findsOneWidget);
      expect(attempts, 2);

      // 验证右上角主题按钮旁边的 GitHub 图标按钮及点击跳转链接
      expect(find.byKey(const Key('app_bar_theme_toggle')), findsOneWidget);
      expect(find.byKey(const Key('app_bar_github_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('app_bar_github_button')));
      await tester.pumpAndSettle();
      expect(openedUrl?.toString(), 'https://github.com/xxhhwtxx');
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('搜索曲目、点播试听音源展示试听标识、展开播放器查看歌词', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_search_');
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search_input_field')), '晴天');
      await tester.pump();
      await tester.tap(find.byKey(const Key('search_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('晴天（测试曲目）'), findsOneWidget);
      expect(find.text('夜曲（完整音源）'), findsOneWidget);

      await tester.tap(find.byKey(const Key('song_play_btn_101')));
      await tester.pumpAndSettle();

      // 迷你播放栏必须清晰提示试听音源
      expect(find.textContaining('试听片段 · 当前账号或曲目权限仅返回试听音源'), findsOneWidget);

      // 展开完整播放器并验证试听横幅与同步歌词
      await tester.tap(find.byKey(const Key('mini_player_expand_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('now_playing_trial_banner')), findsOneWidget);
      expect(find.text('故事的小黄花'), findsOneWidget);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('下载页展示已完成任务、支持 playLocal 本地播放、分享导出与删除二次确认弹窗', (tester) async {
    late Directory tempDir;
    late File fakeAudioFile;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_dl_');
      fakeAudioFile = File('${tempDir.path}/102-夜曲.mp3');
      await fakeAudioFile.create(recursive: true);
      await fakeAudioFile.writeAsBytes([0x49, 0x44, 0x33, 0x04, 0x00]);

      final manifest = File('${tempDir.path}/downloads.json');
      await manifest.writeAsString(
        jsonEncode([
          DownloadTask(
            id: '102',
            song: const Song(
              id: 102,
              name: '夜曲（完整音源）',
              artists: '周杰伦',
              album: '十一月的萧邦',
            ),
            state: DownloadState.completed,
            downloadedBytes: 5,
            totalBytes: 5,
            path: fakeAudioFile.path,
          ).toJson(),
        ]),
      );

      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      DownloadTask? sharedTask;
      await tester.pumpWidget(
        MyApp(
          core: core,
          shareFile: (task) async {
            sharedTask = task;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_tab_downloads')));
      await tester.pumpAndSettle();

      expect(find.text('夜曲（完整音源）'), findsOneWidget);

      // 点击播放曲目，验证调用 playLocal（source.level == 'local'）
      await tester.tap(find.byKey(const Key('download_play_btn_102')));
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();
      expect(core.player.source?.level, 'local');
      expect(audio.lastLoadedUrl?.scheme, 'file');

      // 点击分享导出
      await tester.tap(find.byKey(const Key('download_share_btn_102')));
      await tester.pumpAndSettle();
      expect(sharedTask?.id, '102');

      // 点击删除，必须先弹出确认对话框
      await tester.tap(find.byKey(const Key('download_remove_btn_102')));
      await tester.pumpAndSettle();
      expect(find.text('确认删除下载记录？'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_remove_accept_button')));
      await tester.pumpAndSettle();
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();

      expect(core.downloads.tasks, isEmpty);
      expect(find.text('暂无下载任务'), findsOneWidget);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('账号与设置页支持本地二维码生成、遮挡输入 MUSIC_U、退出登录与音质切换', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_auth_');
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_tab_account')));
      await tester.pumpAndSettle();

      // 验证 MUSIC_U 输入框默认开启 obscureText 遮挡
      final musicUField = tester.widget<TextField>(
        find.byKey(const Key('music_u_input_field')),
      );
      expect(musicUField.obscureText, isTrue);

      // 验证本地生成登录二维码
      await tester.tap(find.byKey(const Key('qr_create_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(QrImageView), findsOneWidget);

      final qrCancelFinder = find.byKey(const Key('qr_cancel_button'));
      await tester.ensureVisible(qrCancelFinder);
      await tester.pump();
      await tester.tap(qrCancelFinder);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);

      // 验证导入 MUSIC_U 登录与退出
      final musicUInputFinder = find.byKey(const Key('music_u_input_field'));
      await tester.ensureVisible(musicUInputFinder);
      await tester.pumpAndSettle();
      await tester.enterText(
        musicUInputFinder,
        'MUSIC_U=valid_test_cookie_token;',
      );
      await tester.pump();
      final musicUImportFinder = find.byKey(const Key('music_u_import_button'));
      await tester.ensureVisible(musicUImportFinder);
      await tester.pumpAndSettle();
      await tester.tap(musicUImportFinder);
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();

      expect(core.auth.isLoggedIn, isTrue);
      expect(find.text('测试音乐人'), findsOneWidget);

      final logoutFinder = find.byKey(const Key('auth_logout_button'));
      await tester.ensureVisible(logoutFinder);
      await tester.pumpAndSettle();
      await tester.tap(logoutFinder);
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();
      expect(core.auth.isLoggedIn, isFalse);

      // 验证音质档位切换
      final losslessFinder = find.byKey(const Key('quality_option_lossless'));
      await tester.ensureVisible(losslessFinder);
      await tester.pumpAndSettle();
      await tester.tap(losslessFinder);
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();
      expect(core.quality, AudioQuality.lossless);

      // 确认已移除关于与开源来源说明卡片
      expect(find.byKey(const Key('open_source_about_card')), findsNothing);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('支持切换 QQ 音乐搜索、跨平台相同数字 ID 曲目按 song.key 隔离播放状态与歌词', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_qq_search_');
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      // 1. 先在网易云搜索并播放 id=101 的曲目（key='101'）
      await tester.enterText(find.byKey(const Key('search_input_field')), '晴天');
      await tester.pump();
      await tester.tap(find.byKey(const Key('search_submit_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('song_play_btn_101')));
      await tester.pumpAndSettle();
      expect(core.player.currentSong?.key, '101');
      expect(core.player.isPlaying, isTrue);

      // 2. 切换到 QQ 音乐，自动重新搜索，返回同样 id=101 但 mid='0039MnYb0qxYhV' 的 QQ 曲目
      await tester.tap(find.byKey(const Key('search_platform_qq')));
      await tester.pumpAndSettle();

      expect(core.search.platform, MusicPlatform.qq);
      expect(find.text('晴天（QQ 音乐版）'), findsOneWidget);
      expect(find.text('ID: 0039MnYb0qxYhV'), findsOneWidget);

      // 验证相同数字 id=101 的 QQ 曲目不会被误判为正在播放的网易云曲目
      final qqPlayBtn = find.byKey(
        const Key('song_play_btn_qq_0039MnYb0qxYhV'),
      );
      expect(qqPlayBtn, findsOneWidget);
      expect(
        find.descendant(
          of: qqPlayBtn,
          matching: find.byIcon(Icons.play_circle_outline_rounded),
        ),
        findsOneWidget,
      );

      // 3. 点击播放 QQ 音乐曲目并展开播放器验证 lyricsFor(Song)
      await tester.tap(qqPlayBtn);
      await tester.pumpAndSettle();
      expect(core.player.currentSong?.key, 'qq_0039MnYb0qxYhV');

      await tester.tap(find.byKey(const Key('mini_player_expand_button')));
      await tester.pumpAndSettle();
      expect(find.text('刮风这天我试过握着你手'), findsOneWidget);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('支持 QQ 音乐二维码 Image.memory 渲染、遮挡导入凭据与独立退出登录', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('music163_ui_qq_auth_');
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_tab_account')));
      await tester.pumpAndSettle();

      // 验证 QQ 凭据输入框默认开启 obscureText 遮挡
      final qqFieldFinder = find.byKey(const Key('qq_credential_input_field'));
      await tester.ensureVisible(qqFieldFinder);
      await tester.pumpAndSettle();
      final qqField = tester.widget<TextField>(qqFieldFinder);
      expect(qqField.obscureText, isTrue);

      // 验证生成 QQ 登录二维码并通过 Image.memory 展示
      final qqQrCreateFinder = find.byKey(const Key('qq_qr_create_button'));
      await tester.ensureVisible(qqQrCreateFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqQrCreateFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('qq_qr_image')), findsOneWidget);

      final qqQrCancelFinder = find.byKey(const Key('qq_qr_cancel_button'));
      await tester.ensureVisible(qqQrCancelFinder);
      await tester.pump();
      await tester.tap(qqQrCancelFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qq_qr_image')), findsNothing);

      // 验证导入 QQ 音乐凭据与退出登录（与网易云账号状态互不影响）
      await tester.ensureVisible(qqFieldFinder);
      await tester.pumpAndSettle();
      await tester.enterText(
        qqFieldFinder,
        'uin=123456; qqmusic_key=W_X_valid_qq_token;',
      );
      await tester.pump();

      final qqImportFinder = find.byKey(
        const Key('qq_credential_import_button'),
      );
      await tester.ensureVisible(qqImportFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqImportFinder);
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();

      expect(core.qqAuth.isLoggedIn, isTrue);
      expect(core.auth.isLoggedIn, isFalse);
      expect(find.text('QQ 测试乐迷'), findsOneWidget);

      final qqLogoutFinder = find.byKey(const Key('qq_auth_logout_button'));
      await tester.ensureVisible(qqLogoutFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqLogoutFinder);
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();

      expect(core.qqAuth.isLoggedIn, isFalse);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('QQ 扫码展示有效期、授权中/失败/拒绝不误报过期、登录成功后资料暂不可用仍保持已登录', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    late Music163Core core;

    var checkQrMode = 'confirm';
    var checkSigShouldSucceed = false;
    Completer<http.Response>? pendingCheckSig;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'music163_ui_qq_qr_regression_',
      );
      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/ptqrshow')) {
          return http.Response.bytes(
            _kValidPngBytes,
            200,
            headers: {
              'content-type': 'image/png',
              'set-cookie': 'qrsig=test_qq_sig; Path=/',
            },
          );
        }

        if (path.contains('/ptqrlogin')) {
          if (checkQrMode == 'refused') {
            return http.Response.bytes(
              utf8.encode("ptuiCB('68','0','','0','本次登录已被拒绝', '');"),
              200,
              headers: {'content-type': 'text/plain; charset=utf-8'},
            );
          }
          return http.Response.bytes(
            utf8.encode(
              "ptuiCB('0','0','https://ssl.ptlogin2.graph.qq.com/check_sig?uin=123456&ptsigx=sig123','0','登录成功！', '测试用户');",
            ),
            200,
            headers: {'content-type': 'text/plain; charset=utf-8'},
          );
        }

        if (path.contains('/check_sig')) {
          if (pendingCheckSig case final pending?) {
            return pending.future;
          }
          if (!checkSigShouldSucceed) {
            return http.Response('', 200);
          }
          return http.Response(
            '',
            302,
            headers: {
              'set-cookie': 'p_skey=test_pskey; Path=/',
              'location': 'https://graph.qq.com/oauth2.0/login_jump',
            },
          );
        }

        if (path.contains('/oauth2.0/authorize')) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://y.qq.com/portal/wx_redirect.html?code=oauth_code_1',
            },
          );
        }

        if (path.contains('/cgi-bin/musicu.fcg')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final req0 = body['req_0'] as Map<String, dynamic>? ?? {};
          final method = req0['method'] as String? ?? '';

          if (method == 'QQLogin') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'req_0': {
                    'code': 0,
                    'data': {
                      'code': 0,
                      'musicid': 123456,
                      'musickey': 'W_X_qr_login_key',
                    },
                  },
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          if (method == 'GetLoginUserInfo') {
            // 模拟凭据保存成功后资料接口暂时失败
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'req_0': {
                    'code': 0,
                    'data': {'code': 500},
                  },
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
        }

        return http.Response.bytes(
          utf8.encode(jsonEncode({'code': 200})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      core = await Music163Core.create(
        credentialStore: store,
        client: client,
        audioBackend: audio,
        downloadDirectory: tempDir,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_tab_account')));
      await tester.pumpAndSettle();

      // 1. 生成二维码，验证显示二维码图片与「有效期至 HH:mm:ss」
      final qqQrCreateFinder = find.byKey(const Key('qq_qr_create_button'));
      await tester.ensureVisible(qqQrCreateFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqQrCreateFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('qq_qr_image')), findsOneWidget);
      expect(find.byKey(const Key('qq_qr_expiry_text')), findsOneWidget);
      expect(find.textContaining('有效期至 '), findsOneWidget);

      // 2. 模拟手机端确认登录进入 authorizing：隐藏旧二维码和有效期，禁止重复生成，且绝不显示过期
      late Future<void> pollFuture;
      await tester.runAsync(() async {
        pendingCheckSig = Completer<http.Response>();
        pollFuture = core.qqAuth.pollQr();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(core.qqAuth.qrStatus, QrStatus.authorizing);
      expect(core.qqAuth.isBusy, isTrue);
      expect(find.textContaining('正在完成 QQ 音乐登录授权'), findsOneWidget);
      expect(find.textContaining('二维码已过期'), findsNothing);
      expect(find.byKey(const Key('qq_qr_image')), findsNothing);
      expect(find.byKey(const Key('qq_qr_expiry_text')), findsNothing);

      final busyCreateBtn = tester.widget<FilledButton>(qqQrCreateFinder);
      expect(busyCreateBtn.onPressed, isNull);

      // 3. 模拟授权阶段失败（failed）：展示真实错误与失败提示，绝不误报「二维码已过期」，且可重新获取
      await tester.runAsync(() async {
        pendingCheckSig?.complete(http.Response('', 200));
        pendingCheckSig = null;
        await pollFuture;
      });
      await tester.pumpAndSettle();

      expect(core.qqAuth.qrStatus, QrStatus.failed);
      expect(core.qqAuth.isBusy, isFalse);
      expect(find.textContaining('二维码已过期'), findsNothing);
      expect(find.textContaining('QQ 音乐登录授权未完成'), findsOneWidget);
      expect(find.byKey(const Key('qq_qr_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('qq_auth_error_banner')), findsNothing);
      expect(find.textContaining('QQ 授权未返回登录凭据'), findsOneWidget);

      // 4. 模拟手机端拒绝授权（refused）：显示拒绝提示而非过期
      checkQrMode = 'refused';
      await tester.ensureVisible(qqQrCreateFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqQrCreateFinder);
      await tester.pump();
      await tester.runAsync(() async {
        await core.qqAuth.pollQr();
      });
      await tester.pumpAndSettle();

      expect(core.qqAuth.qrStatus, QrStatus.refused);
      expect(find.textContaining('已在手机端取消或拒绝本次授权'), findsOneWidget);
      expect(find.textContaining('二维码已过期'), findsNothing);

      // 5. 模拟扫码授权成功但资料接口失败：保留已登录状态，展示「QQ 音乐用户」与资料暂未同步提示
      checkQrMode = 'confirm';
      checkSigShouldSucceed = true;
      await tester.ensureVisible(qqQrCreateFinder);
      await tester.pumpAndSettle();
      await tester.tap(qqQrCreateFinder);
      await tester.pump();
      await tester.runAsync(() async {
        await core.qqAuth.pollQr();
      });
      await _pumpRealIo(tester);
      await tester.pumpAndSettle();

      expect(core.qqAuth.isLoggedIn, isTrue);
      expect(find.text('QQ 音乐用户'), findsOneWidget);
      expect(find.textContaining('账号资料暂未同步'), findsOneWidget);
      expect(find.textContaining('二维码已过期'), findsNothing);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });

  testWidgets('设置页应用更新卡片：检查更新、发现新版与版本说明、下载进度与取消、缺少安装权限引导及重试安装', (tester) async {
    late Directory tempDir;
    final store = _MemoryCredentialStore();
    final audio = _FakeAudioBackend();
    final fakeUpdater = _FakeUpdateController();
    late Music163Core core;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'music163_ui_update_card_test_',
      );
      core = await _createTestCore(
        tempDir: tempDir,
        store: store,
        audio: audio,
        updater: fakeUpdater,
      );
    });

    try {
      await tester.pumpWidget(MyApp(core: core));
      await tester.pumpAndSettle();

      // 验证顶栏保留「随时听」「Anytime Music」与 GitHub 入口按钮
      expect(find.text('随时听'), findsOneWidget);
      expect(find.text('Anytime Music'), findsOneWidget);
      expect(find.byKey(const Key('app_bar_github_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_tab_account')));
      await tester.pumpAndSettle();

      final updateCardFinder = find.byKey(const Key('app_update_card'));
      await tester.ensureVisible(updateCardFinder);
      await tester.pumpAndSettle();

      // 1. 初始状态展示当前版本与「检查更新」按钮
      expect(find.text('当前版本：1.2.0'), findsOneWidget);
      final checkBtnFinder = find.byKey(const Key('update_check_button'));
      expect(checkBtnFinder, findsOneWidget);

      // 2. 模拟无可用发布（noRelease）
      fakeUpdater.checkMode = 'noRelease';
      await tester.ensureVisible(checkBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(checkBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.noRelease);
      expect(find.text('暂无可用更新'), findsOneWidget);

      // 3. 模拟已是最新版本（upToDate）
      fakeUpdater.checkMode = 'upToDate';
      await tester.tap(checkBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.upToDate);
      expect(find.text('已是最新版本'), findsOneWidget);

      // 4. 模拟检查失败（failed），展示错误横幅并支持重试检查
      fakeUpdater.checkMode = 'failed';
      await tester.tap(checkBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.failed);
      expect(find.byKey(const Key('update_error_banner')), findsOneWidget);
      expect(find.textContaining('更新检查暂时受限'), findsOneWidget);

      // 5. 模拟发现新版本（available），显示新版本号、安装包大小、纯文本更新说明与下载按钮
      fakeUpdater.checkMode = 'available';
      await tester.ensureVisible(checkBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(checkBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.available);
      expect(find.text('发现新版本 1.3.0'), findsOneWidget);
      expect(find.text('大小：24.50 MB'), findsOneWidget);
      expect(find.byKey(const Key('update_release_notes')), findsOneWidget);
      expect(find.textContaining('1. 新增应用内检查更新'), findsOneWidget);

      // 6. 点击下载按钮进入 downloading 状态，展示进度条、字节进度与取消下载按钮
      fakeUpdater.pauseDownload = true;
      final downloadBtnFinder = find.byKey(const Key('update_download_button'));
      await tester.ensureVisible(downloadBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtnFinder);
      await tester.pump();

      expect(fakeUpdater.status, UpdateStatus.downloading);
      expect(
        find.byKey(const Key('update_download_progress_bar')),
        findsOneWidget,
      );
      expect(find.text('12.25 MB / 24.50 MB (50%)'), findsOneWidget);

      final cancelBtnFinder = find.byKey(
        const Key('update_cancel_download_button'),
      );
      await tester.ensureVisible(cancelBtnFinder);
      await tester.pump();
      await tester.tap(cancelBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.cancelCount, 1);
      expect(fakeUpdater.status, UpdateStatus.available);
      expect(find.text('下载已取消'), findsOneWidget);

      // 7. 再次点击下载并完成，进入 ready 状态展示「安装新版」按钮
      fakeUpdater.pauseDownload = false;
      await tester.ensureVisible(downloadBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(downloadBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.ready);
      expect(find.text('新版安装包已就绪（1.3.0）'), findsOneWidget);
      final installBtnFinder = find.byKey(const Key('update_install_button'));
      expect(installBtnFinder, findsOneWidget);

      // 8. 首次点击安装时缺少未知来源安装权限（permissionRequired）：展示提示、「去设置」和「重试安装」按钮
      fakeUpdater.canInstall = false;
      await tester.ensureVisible(installBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(installBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.status, UpdateStatus.permissionRequired);
      expect(find.text('请允许随时听安装应用'), findsOneWidget);

      final openSettingsBtnFinder = find.byKey(
        const Key('update_open_settings_button'),
      );
      final retryInstallBtnFinder = find.byKey(
        const Key('update_retry_install_button'),
      );
      expect(openSettingsBtnFinder, findsOneWidget);
      expect(retryInstallBtnFinder, findsOneWidget);

      // 9. 点击「去设置」授权后点击「重试安装」，调起系统安装器
      await tester.ensureVisible(openSettingsBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(openSettingsBtnFinder);
      await tester.pumpAndSettle();
      expect(fakeUpdater.openSettingsCount, 1);

      await tester.ensureVisible(retryInstallBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(retryInstallBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeUpdater.installCount, 2);
      expect(fakeUpdater.status, UpdateStatus.ready);
      expect(find.text('请在系统安装界面完成更新'), findsOneWidget);
    } finally {
      await _cleanupTestCore(tester, core, tempDir);
    }
  });
}
