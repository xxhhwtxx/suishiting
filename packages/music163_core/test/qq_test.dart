import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart'
    show MemoryStore, FakeAudio, first, media, FakeRepository;
import 'download_test.dart' show waitFor;

const qqSong = Song(
  id: 1,
  name: 'QQ歌曲',
  artists: '歌手',
  album: '专辑',
  platform: MusicPlatform.qq,
  mid: '001testMID00001',
  mediaMid: 'media00001',
);
const credential =
    '{"musicid":12345,"musickey":"test_music_key","refresh_token":"test_refresh","loginType":2}';
http.Response rpc(Map<String, dynamic> data, {int code = 0}) => http.Response(
  jsonEncode({
    'code': 0,
    'req_0': {'code': code, 'data': data},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> requestBody(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;
final rawSong = <String, dynamic>{
  'id': 1,
  'mid': qqSong.mid,
  'name': qqSong.name,
  'singer': [
    {'name': '歌手'},
  ],
  'album': {'name': '专辑', 'mid': 'album0001'},
  'file': {'media_mid': 'media00001'},
  'interval': 180,
};

class MultiRepository extends FakeRepository {
  final sources = <String>[];
  @override
  Future<MediaSource> playbackFor(Song song) async {
    sources.add(song.key);
    return media;
  }

  @override
  Future<MediaSource> downloadFor(Song song) => playbackFor(song);
}

void main() {
  test('跨平台歌曲持久化与旧网易云记录兼容', () {
    final old = Song.fromJson({'id': 1, 'name': '旧记录'});
    expect(old.platform, MusicPlatform.netease);
    expect(old.key, '1');
    final restored = Song.fromJson(
      jsonDecode(jsonEncode(qqSong.toJson())) as Map<String, dynamic>,
    );
    expect(restored.key, 'qq_${qqSong.mid}');
    expect(restored.key, isNot(old.key));
    expect(restored.mediaMid, qqSong.mediaMid);
  });

  test('QQ Cookie 和 JSON 凭据解析，拒绝普通QQ Cookie及注入', () {
    expect(
      QqCredential.parse('uin=o0012345; qm_keyst=test_key').musicId,
      '12345',
    );
    expect(QqCredential.parse(credential).canRefresh, isTrue);
    expect(
      () => QqCredential.parse('p_skey=ordinaryQQ'),
      throwsA(isA<MusicException>()),
    );
    expect(
      () => QqCredential.parse('{"musicid":12,"musickey":"key;evil=value"}'),
      throwsA(isA<MusicException>()),
    );
  });

  test('QQ 搜索使用服务器页码而非结果条数，末页停止', () async {
    final pages = <int>[];
    final api = QqApi(
      client: MockClient((r) async {
        final body = requestBody(r);
        expect(r.url.host, 'u.y.qq.com');
        expect(r.headers.containsKey('cookie'), isFalse);
        final page = ((body['req_0'] as Map)['param'] as Map)['page_id'] as int;
        pages.add(page);
        return rpc({
          'body': {
            'item_song': {
              'items': [rawSong],
              'total_num': 2,
            },
          },
          'meta': {'nextpage': page == 1 ? 2 : -1},
        });
      }),
    );
    final repo = MusicRepository(
      NeteaseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
        deviceId: 'test',
      ),
      qqApi: api,
    );
    final search = SearchController(repo);
    await search.setPlatform(MusicPlatform.qq);
    await search.search('歌名');
    expect(search.songs.single.mid, qqSong.mid);
    await search.loadMore();
    expect(pages, [1, 2]);
    expect(search.songs, hasLength(1));
    expect(search.hasMore, isFalse);
    search.dispose();
    api.close();
    repo.api.close();
  });

  test('切换到QQ时迟到的网易云结果不能覆盖新平台', () async {
    final pending = Completer<SearchPage>();
    final api = QqApi(
      client: MockClient(
        (_) async => rpc({
          'body': {
            'item_song': {
              'items': [rawSong],
            },
          },
          'meta': {'nextpage': -1},
        }),
      ),
    );
    final repo = _SwitchRepository(api, pending);
    final search = SearchController(repo);
    final old = search.search('歌名');
    await Future<void>.delayed(Duration.zero);
    await search.setPlatform(MusicPlatform.qq);
    pending.complete(SearchPage(songs: [first], hasMore: false, total: 1));
    await old;
    expect(search.songs.single.platform, MusicPlatform.qq);
    search.dispose();
    api.close();
    repo.api.close();
  });

  test('QQ 链接解析限定官方歌曲页，非歌曲链接不发送请求', () async {
    var requests = 0;
    final api = QqApi(
      client: MockClient((r) async {
        requests++;
        expect((requestBody(r)['req_0'] as Map)['param'], {
          'song_mid': qqSong.mid,
        });
        return rpc({'track_info': rawSong});
      }),
    );
    final repo = MusicRepository(
      NeteaseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
        deviceId: 'test',
      ),
      qqApi: api,
    );
    expect(
      (await repo.resolveSong(
        MusicPlatform.qq,
        '分享 https://y.qq.com/n/ryqq/songDetail/${qqSong.mid}',
      ))!.key,
      qqSong.key,
    );
    await expectLater(
      repo.resolveSong(
        MusicPlatform.qq,
        'https://y.qq.com.evil.example/songDetail/x',
      ),
      throwsA(isA<MusicException>()),
    );
    await expectLater(
      repo.resolveSong(MusicPlatform.qq, 'https://y.qq.com/n/ryqq/playlist/1'),
      throwsA(isA<MusicException>()),
    );
    expect(requests, 1);
    api.close();
    repo.api.close();
  });

  test('按账号取QQ源，降级音质并保持实际音质，拒绝空地址', () async {
    final prefixes = <String>[];
    final api = QqApi(
      client: MockClient((r) async {
        expect(r.headers['cookie'], contains('qqmusic_key=test_music_key'));
        expect(r.headers['cookie'], isNot(contains('MUSIC_U')));
        final params = (requestBody(r)['req_0'] as Map)['param'] as Map;
        final filename = (params['filename'] as List).single as String;
        prefixes.add(filename.substring(0, 4));
        return rpc({
          'sip': ['http://isure.stream.qqmusic.qq.com/'],
          'midurlinfo': [
            {
              'result': 0,
              'purl': filename.startsWith('M500') ? '$filename?vkey=test' : '',
            },
          ],
        });
      }),
    )..credential = QqCredential.parse(credential);
    final source = await api.source(qqSong, AudioQuality.lossless);
    expect(prefixes, ['F000', 'M800', 'M500']);
    expect(source.url.scheme, 'https');
    expect(source.level, 'standard');
    expect(source.bitrate, 128000);
    expect(source.isTrial, isFalse);
    api.close();
    final empty = QqApi(
      client: MockClient(
        (_) async => rpc({
          'midurlinfo': [
            {'purl': ''},
          ],
        }),
      ),
    );
    await expectLater(
      empty.source(qqSong, AudioQuality.standard),
      throwsA(isA<MusicException>()),
    );
    empty.close();
  });

  test('QQ 试听下载及非QQ音源地址被拒绝', () async {
    for (final path in ['RS02clip.mp3', 'https://example.com/audio.mp3']) {
      final api = QqApi(
        client: MockClient(
          (_) async => rpc({
            'midurlinfo': [
              {'purl': path},
            ],
          }),
        ),
      );
      await expectLater(
        api.source(qqSong, AudioQuality.standard, download: true),
        throwsA(isA<MusicException>()),
      );
      api.close();
    }
  });

  test('QQ 导入验证后才保存，退出清理QQ凭据不影响网易云', () async {
    final store = MemoryStore()..values['music163.music_u'] = 'netease_test';
    final api = QqApi(
      client: MockClient(
        (_) async => rpc({
          'userInfo': {'nick': 'QQ测试账号'},
        }),
      ),
    );
    final auth = QqAuthController(api, store);
    await auth.importCredential(credential);
    expect(auth.profile?.nickname, 'QQ测试账号');
    expect(store.values[QqAuthController.credentialKey], isNotNull);
    await auth.logout();
    expect(api.credential, isNull);
    expect(store.values[QqAuthController.credentialKey], isNull);
    expect(store.values['music163.music_u'], 'netease_test');
    auth.dispose();
    api.close();
  });

  test('QQ 导入期间退出，迟到的凭据不会恢复登录', () async {
    final gate = Completer<http.Response>();
    final store = MemoryStore();
    final api = QqApi(client: MockClient((_) => gate.future));
    final auth = QqAuthController(api, store);
    final importing = auth.importCredential(credential);
    await Future<void>.delayed(Duration.zero);
    await auth.logout();
    gate.complete(
      rpc({
        'userInfo': {'nick': '旧账号'},
      }),
    );
    await importing;
    expect(auth.isLoggedIn, isFalse);
    expect(api.credential, isNull);
    expect(store.values[QqAuthController.credentialKey], isNull);
    auth.dispose();
    api.close();
  });

  test('QQ 二维码完整授权链、状态转换及本地加密存储接口', () async {
    var checks = 0;
    final api = QqApi(
      client: MockClient((r) async {
        if (r.url.path == '/ptqrshow') {
          return http.Response.bytes(
            [137, 80, 78, 71, 13, 10, 26, 10, 1],
            200,
            headers: {
              'set-cookie':
                  'qrsig=test_sig; Path=/; Secure, pt_guid_sig=test_guid; Path=/',
            },
          );
        }
        if (r.url.path == '/ptqrlogin') {
          expect(r.url.queryParameters['ptqrtoken'], '${qqHash('test_sig')}');
          expect(r.headers['cookie'], contains('pt_guid_sig=test_guid'));
          checks++;
          return http.Response(
            checks == 1
                ? "ptuiCB('67','0','','0','scanned','');"
                : "ptuiCB('0','0','https://ssl.ptlogin2.qq.com/check_sig?uin=12345&ptsigx=test','0','ok','');",
            200,
            headers: {'set-cookie': 'pt_login_sig=test_login; Path=/'},
          );
        }
        if (r.url.path == '/check_sig') {
          expect(r.followRedirects, isFalse);
          expect(r.headers['cookie'], contains('pt_login_sig=test_login'));
          return http.Response(
            '',
            302,
            headers: {
              'set-cookie':
                  'p_skey=test_pskey; Domain=.graph.qq.com; Path=/, p_uin=o12345; Path=/, p_skey=; Domain=.qq.com; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/',
              'location': 'https://graph.qq.com/oauth2.0/login_jump',
            },
          );
        }
        if (r.url.path == '/oauth2.0/authorize') {
          expect(r.headers['cookie'], contains('p_skey=test_pskey'));
          expect(r.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://y.qq.com/portal/wx_redirect.html?code=test_code&state=state',
              'set-cookie': 'oauth_session=test_oauth; Path=/',
            },
          );
        }
        final req = requestBody(r)['req_0'] as Map;
        if (req['method'] == 'QQLogin') {
          expect(r.headers['cookie'], contains('p_skey=test_pskey'));
          expect(r.headers['cookie'], contains('qrsig=test_sig'));
          expect(r.headers['cookie'], contains('oauth_session=test_oauth'));
          expect(r.headers['cookie'], isNot(contains('MUSIC_U')));
          expect(req['param'], {'code': 'test_code'});
          return rpc({
            ...jsonDecode(credential) as Map<String, dynamic>,
            'str_musicid': '',
          });
        }
        return rpc({
          'userInfo': {'nick': '扫码用户'},
        });
      }),
    );
    final store = MemoryStore();
    final auth = QqAuthController(api, store);
    await auth.createQr();
    expect(auth.qrBytes, isNotNull);
    await auth.pollQr();
    expect(auth.qrStatus, QrStatus.scanned);
    await auth.pollQr();
    expect(auth.isLoggedIn, isTrue);
    expect(auth.qrBytes, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(auth.profile?.nickname, '扫码用户');
    auth.dispose();
    api.close();
  });

  test('QQ 过期/取消二维码停止轮询，取消不保存迟到结果', () async {
    var calls = 0;
    final api = QqApi(
      client: MockClient((r) async {
        if (r.url.path == '/ptqrshow') {
          return http.Response.bytes(
            [137, 80, 78, 71, 13, 10, 26, 10, 1],
            200,
            headers: {'set-cookie': 'qrsig=test; Path=/'},
          );
        }
        calls++;
        return http.Response("ptuiCB('65','0','','0','expired','');", 200);
      }),
    );
    final auth = QqAuthController(api, MemoryStore());
    await auth.createQr();
    await auth.pollQr();
    await auth.pollQr();
    expect(auth.qrStatus, QrStatus.expired);
    expect(calls, 1);
    await auth.createQr();
    auth.cancelQr();
    await auth.pollQr();
    expect(auth.qrBytes, isNull);
    expect(calls, 1);
    auth.dispose();
    api.close();
  });

  test('QQ 凭据刷新采用移动端协议并替换存储，保留OAuth刷新字段', () async {
    final methods = <String>[];
    final store = MemoryStore();
    final api = QqApi(
      client: MockClient((r) async {
        final body = requestBody(r), req = body['req_0'] as Map;
        methods.add(req['method'] as String);
        expect((body['comm'] as Map)['ct'], 11);
        if (req['method'] == 'Login') {
          return rpc({'musicid': 12345, 'musickey': 'new_key', 'loginType': 2});
        }
        return rpc({
          'userInfo': {'nick': '刷新用户'},
        });
      }),
    )..credential = QqCredential.parse(credential);
    final auth = QqAuthController(api, store);
    await auth.refresh();
    expect(api.credential?.musicKey, 'new_key');
    expect(api.credential?.canRefresh, isTrue);
    expect(methods, ['Login', 'GetLoginUserInfo']);
    auth.dispose();
    api.close();
  });

  test('同数字ID的双平台歌曲可分别播放、下载并恢复记录', () async {
    final dir = await Directory.systemTemp.createTemp('qq_multi_test_');
    final repo = MultiRepository();
    final backend = FakeAudio();
    final player = PlayerController(repo, backend);
    final downloads = DownloadController(
      repo,
      dir,
      clientFactory: () => MockClient((r) async {
        expect(r.headers.containsKey('cookie'), isFalse);
        return http.Response.bytes(
          [73, 68, 51, 4, 0, 0, 1, 2],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      }),
    );
    try {
      await player.play(first);
      await player.play(qqSong);
      expect(player.currentSong?.key, qqSong.key);
      await downloads.restore();
      await downloads.enqueue(first);
      await downloads.enqueue(qqSong);
      await waitFor(
        downloads,
        () =>
            downloads.tasks.length == 2 &&
            downloads.tasks.every((t) => t.state == DownloadState.completed),
      );
      expect(downloads.tasks.map((t) => t.id).toSet(), {'1', qqSong.key});
      expect(downloads.tasks.map((t) => t.path).toSet(), hasLength(2));
      await downloads.close();
      final restored = DownloadController(repo, dir);
      await restored.restore();
      expect(restored.tasks.map((t) => t.song.platform).toSet(), {
        MusicPlatform.netease,
        MusicPlatform.qq,
      });
      await restored.close();
    } finally {
      if (!downloads.closed) await downloads.close();
      await player.close();
      repo.api.close();
      await dir.delete(recursive: true);
    }
  });
}

class _SwitchRepository extends MusicRepository {
  _SwitchRepository(QqApi qq, this.pending)
    : super(
        NeteaseApi(
          client: MockClient((_) async => http.Response('{}', 200)),
          deviceId: 'test',
        ),
        qqApi: qq,
      );
  final Completer<SearchPage> pending;
  @override
  Future<int?> resolveInput(String input) async => null;
  @override
  Future<SearchPage> search(String query, {int offset = 0, int limit = 20}) =>
      pending.future;
}
