import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';

const first = Song(id: 1, name: '第一首', artists: '歌手', album: '专辑');
const second = Song(id: 2, name: '第二首', artists: '歌手', album: '专辑');
final media = MediaSource(
  url: Uri(scheme: 'https', host: 'media.example', path: '/1.mp3'),
  extension: 'mp3',
  level: 'higher',
  bitrate: 320000,
  isTrial: false,
);

class FakeRepository extends MusicRepository {
  FakeRepository()
    : super(
        NeteaseApi(
          client: MockClient((_) async => http.Response('{}', 200)),
          deviceId: 'test',
        ),
      );
  Future<SearchPage> Function(String, int)? onSearch;
  Future<MediaSource> Function(int)? onSource;
  @override
  Future<SearchPage> search(String query, {int offset = 0, int limit = 20}) =>
      onSearch!(query, offset);
  @override
  Future<int?> resolveInput(String input) async => null;
  @override
  Future<MediaSource> playbackSource(int id) async =>
      onSource == null ? media : await onSource!(id);
  @override
  Future<MediaSource> downloadSource(int id) => playbackSource(id);
}

class MemoryStore implements CredentialStore {
  final values = <String, String>{};
  Completer<void>? writeGate;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await writeGate?.future;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeAudio implements AudioBackend {
  final eventController = StreamController<AudioEvent>.broadcast();
  final errorController = StreamController<Object>.broadcast();
  final loaded = <Uri>[];
  int playCount = 0;
  @override
  Stream<AudioEvent> get events => eventController.stream;
  @override
  Stream<Object> get errors => errorController.stream;
  @override
  Future<void> load(Uri url) async {
    loaded.add(url);
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> close() async {
    await eventController.close();
    await errorController.close();
  }
}

void main() {
  group('协议与输入', () {
    test('EAPI 与独立 Node AES 实现的固定向量一致', () {
      final vector =
          jsonDecode(
                File('test/fixtures/crypto-vector.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        encodeEapi(
          vector['path'] as String,
          vector['payload'] as Map<String, dynamic>,
        ),
        vector['encrypted'],
      );
    });
    test('仅识别合法网易云歌曲 ID 和完整分享链接', () {
      expect(songIdFromInput('12345'), 12345);
      expect(
        songIdFromInput('分享 https://music.163.com/#/song?id=12345'),
        12345,
      );
      expect(
        songIdFromInput('https://y.music.163.com/m/song?id=99&userid=12'),
        99,
      );
      expect(songIdFromInput('https://music.163.com/playlist?id=123'), isNull);
      expect(
        songIdFromInput('https://music.163.com.evil.example/song?id=123'),
        isNull,
      );
      expect(songIdFromInput('周杰伦2024'), isNull);
      expect(songIdFromInput('0'), isNull);
    });
    test('请求仅发往网易云，匿名登录请求不带用户凭据', () async {
      var calls = 0;
      final api = NeteaseApi(
        deviceId: 'test',
        client: MockClient((request) async {
          expect(request.url.host, 'music.163.com');
          expect(request.url.scheme, 'https');
          expect(request.followRedirects, isFalse);
          expect(request.body, startsWith('params='));
          if (calls++ == 0) {
            expect(request.headers['Cookie'], contains('MUSIC_U=secret'));
          } else {
            expect(request.headers['Cookie'], isNot(contains('MUSIC_U')));
          }
          return http.Response('{"code":200}', 200);
        }),
      )..musicU = 'secret';
      await api.request('/api/test', {});
      await api.request('/api/test', {}, anonymous: true);
      api.close();
    });
    test('登录失效和风控转换为可处理的错误', () async {
      final api = NeteaseApi(
        deviceId: 'test',
        client: MockClient((_) async => http.Response('{"code":301}', 200)),
      );
      await expectLater(
        api.request('/api/test', {}),
        throwsA(isA<MusicException>().having((e) => e.code, 'code', 301)),
      );
      api.close();
    });
    test('短链接不能重定向到第三方或本地地址', () async {
      final api = NeteaseApi(
        deviceId: 'test',
        client: MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'http://127.0.0.1/secret'},
          ),
        ),
      );
      await expectLater(
        api.resolveShortLink(Uri.parse('https://163cn.tv/abc')),
        throwsA(isA<MusicException>()),
      );
      api.close();
    });
    test('试听音源可以明确标识，下载接口拒绝试听', () async {
      final api = NeteaseApi(
        deviceId: 'test',
        client: MockClient((request) async {
          final data = {
            'url': 'http://m1.music.126.net/a.mp3',
            'type': 'mp3',
            'freeTrialInfo': {'start': 0, 'end': 30000},
          };
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': request.url.path.contains('/download/') ? data : [data],
            }),
            200,
          );
        }),
      );
      final repository = MusicRepository(api);
      expect((await repository.playbackSource(1)).isTrial, isTrue);
      await expectLater(
        repository.downloadSource(1),
        throwsA(isA<MusicException>()),
      );
      api.close();
    });
  });

  group('搜索并发', () {
    test('旧请求完成后不能覆盖新查询', () async {
      final old = Completer<SearchPage>();
      final repository = FakeRepository()
        ..onSearch = (q, _) async => q == 'old'
            ? old.future
            : SearchPage(songs: [second], hasMore: false, total: 1);
      final controller = SearchController(repository);
      final pending = controller.search('old');
      await Future<void>.delayed(Duration.zero);
      await controller.search('new');
      old.complete(SearchPage(songs: [first], hasMore: true, total: 20));
      await pending;
      expect(controller.songs.single.id, 2);
      expect(controller.query, 'new');
      expect(controller.hasMore, isFalse);
      controller.dispose();
    });
    test('翻页去重且偏移按原始结果数前进', () async {
      final offsets = <int>[];
      final repository = FakeRepository()
        ..onSearch = (_, offset) async {
          offsets.add(offset);
          return SearchPage(
            songs: offset == 0 ? [first] : [first, second],
            hasMore: offset == 0,
            total: 3,
          );
        };
      final controller = SearchController(repository);
      await controller.search('test');
      await controller.loadMore();
      expect(offsets, [0, 1]);
      expect(controller.songs.map((s) => s.id), [1, 2]);
      controller.dispose();
    });
  });

  group('账号凭据', () {
    late NeteaseApi api;
    late MemoryStore store;
    late AuthController auth;
    setUp(() {
      store = MemoryStore();
      api = NeteaseApi(
        deviceId: 'test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 200,
              'profile': {'userId': 1, 'nickname': '测试用户'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      auth = AuthController(api, store);
    });
    tearDown(() {
      auth.dispose();
      api.close();
    });
    test('验证成功后才持久化，退出同时清除内存和磁盘', () async {
      await auth.importMusicU('a=1; MUSIC_U=test-token; b=2');
      expect(auth.isLoggedIn, isTrue);
      expect(api.musicU, 'test-token');
      expect(store.values[AuthController.credentialKey], 'test-token');
      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(api.musicU, isNull);
      expect(store.values[AuthController.credentialKey], isNull);
    });
    test('导入期间退出，迟到的写入不能恢复账号', () async {
      store.writeGate = Completer<void>();
      final imported = auth.importMusicU('late-token');
      await Future<void>.delayed(Duration.zero);
      final logout = auth.logout();
      store.writeGate!.complete();
      await imported;
      await logout;
      expect(api.musicU, isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(store.values[AuthController.credentialKey], isNull);
    });
    test('非法 Cookie 不会发送到服务器', () async {
      await auth.importMusicU('token\r\ninjected=value');
      expect(auth.error, isNotNull);
      expect(api.musicU, isNull);
    });
  });

  group('播放器并发', () {
    test('本地文件播放不请求在线音源', () async {
      final directory = await Directory.systemTemp.createTemp(
        'music163_local_',
      );
      final file = await File(
        '${directory.path}/test.mp3',
      ).writeAsBytes([73, 68, 51, 0]);
      final repo = FakeRepository()
        ..onSource = (_) => throw StateError('Must not request network');
      final audio = FakeAudio();
      final player = PlayerController(repo, audio);
      await player.playLocal(first, file.path);
      expect(audio.loaded.single.scheme, 'file');
      expect(player.source!.level, 'local');
      await player.close();
      await directory.delete(recursive: true);
    });
    test('快速切歌时只加载最后的音源', () async {
      final old = Completer<MediaSource>();
      final repo = FakeRepository()
        ..onSource = (id) async => id == 1 ? old.future : media;
      final audio = FakeAudio();
      final player = PlayerController(repo, audio);
      final firstLoad = player.play(first);
      await Future<void>.delayed(Duration.zero);
      await player.play(second);
      old.complete(media);
      await firstLoad;
      expect(player.currentSong!.id, 2);
      expect(audio.loaded.length, 1);
      await player.close();
    });
    test('解析音源时暂停，加载完成也不会自动播放', () async {
      final pending = Completer<MediaSource>();
      final repo = FakeRepository()..onSource = (_) => pending.future;
      final audio = FakeAudio();
      final player = PlayerController(repo, audio);
      final playing = player.play(first);
      await Future<void>.delayed(Duration.zero);
      await player.pause();
      pending.complete(media);
      await playing;
      expect(audio.playCount, 0);
      expect(player.source, isNotNull);
      await player.close();
    });
  });
}
