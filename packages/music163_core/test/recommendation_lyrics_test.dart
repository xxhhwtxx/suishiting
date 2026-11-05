import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart' show FakeRepository, first, second;
import 'download_test.dart' show waitFor;

const lrc = '[ti:歌曲]\n[offset:120]\n[00:01.00]第一句\n[00:02.50]第二句';

class LyricRepository extends FakeRepository {
  bool fail = false;
  Completer<String>? pending;
  @override
  Future<String> lyrics(int id) async {
    if (pending != null) return pending!.future;
    if (fail) throw const MusicException('offline');
    return lrc;
  }
}

class RecommendationRepository extends FakeRepository {
  final pending = <MusicPlatform, Completer<RecommendationResult>>{};
  @override
  Future<RecommendationResult> recommendationsFor(MusicPlatform platform) =>
      pending[platform]!.future;
}

void main() {
  test('歌词仍在获取时音频已经可播放，重复补存不会覆盖或残留临时文件', () async {
    final dir = await Directory.systemTemp.createTemp('suishiting_slow_lrc');
    final repo = LyricRepository()
      ..lyricDirectory = Directory('${dir.path}/lyrics')
      ..pending = Completer<String>();
    final downloads = DownloadController(
      repo,
      dir,
      downloadLyrics: () => true,
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          [73, 68, 51, 0, 0],
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      ),
    );
    await downloads.restore();
    await downloads.enqueue(first);
    await waitFor(
      downloads,
      () => downloads.tasks.first.state == DownloadState.completed,
    );
    expect(await File(downloads.tasks.first.path!).exists(), isTrue);
    expect(downloads.tasks.first.lyricsPath, isNull);
    final saves = [
      downloads.saveLyrics(first.key),
      downloads.saveLyrics(first.key),
    ];
    repo.pending!.complete(lrc);
    await Future.wait(saves);
    expect(await File(downloads.tasks.first.lyricsPath!).readAsString(), lrc);
    await downloads.close();
    expect(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.endsWith('.tmp')),
      isFalse,
    );
    repo.api.close();
    await dir.delete(recursive: true);
  });
  test('推荐解析真实平台结构；匿名新歌请求不带音乐凭据', () async {
    final api = NeteaseApi(
      deviceId: 'test',
      client: MockClient((request) async {
        expect(request.url.path, '/eapi/personalized/newsong');
        expect(request.headers['Cookie'], isNot(contains('MUSIC_U')));
        return http.Response(
          jsonEncode({
            'code': 200,
            'result': [
              {'song': first.toJson()},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final qq = QqApi(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['req_0']['module'], 'newsong.NewSongServer');
        return http.Response(
          jsonEncode({
            'code': 0,
            'req_0': {
              'code': 0,
              'data': {
                'songlist': [
                  {
                    'id': 2,
                    'mid': '003mid',
                    'name': '新歌',
                    'singer': [
                      {'name': '歌手'},
                    ],
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final repo = MusicRepository(api, qqApi: qq);
    expect(
      (await repo.recommendationsFor(MusicPlatform.netease)).songs.single.key,
      '1',
    );
    expect(
      (await repo.recommendationsFor(MusicPlatform.qq)).songs.single.key,
      'qq_003mid',
    );
    api.close();
    qq.close();
  });
  test('切换平台丢弃旧请求结果，失败保留可重试状态', () async {
    final repo = RecommendationRepository();
    repo.pending[MusicPlatform.netease] = Completer();
    repo.pending[MusicPlatform.qq] = Completer();
    final picks = RecommendationController(repo);
    final a = picks.load();
    final b = picks.setPlatform(MusicPlatform.qq);
    repo.pending[MusicPlatform.qq]!.complete(
      RecommendationResult([second, second], 'QQ 新歌推荐'),
    );
    await b;
    repo.pending[MusicPlatform.netease]!.complete(
      RecommendationResult([first], '网易云新歌推荐'),
    );
    await a;
    expect(picks.songs.single.key, '2');
    expect(picks.sourceLabel, 'QQ 新歌推荐');
    repo.pending[MusicPlatform.qq] = Completer()
      ..completeError(const MusicException('offline'));
    await picks.load(refresh: true);
    expect(picks.error, 'offline');
    expect(picks.songs.single.key, '2');
    picks.dispose();
    repo.api.close();
  });
  test('保存LRC保留时间戳，重启和断网后完全从本地读取', () async {
    final dir = await Directory.systemTemp.createTemp('suishiting_lrc');
    final repo = LyricRepository()..lyricDirectory = dir;
    final path = await repo.saveLyricsFor(first);
    expect(path, isNotNull);
    final offline = LyricRepository()
      ..lyricDirectory = dir
      ..fail = true;
    expect(await offline.lyricsFor(first), lrc);
    expect(await File(path!).readAsString(), contains('[00:02.50]'));
    repo.api.close();
    offline.api.close();
    await dir.delete(recursive: true);
  });
  test('歌词开关关闭不下载，开启保存，歌词失败不破坏音频，旧任务可补存并删除', () async {
    final dir = await Directory.systemTemp.createTemp(
      'suishiting_download_lrc',
    );
    final repo = LyricRepository()
      ..lyricDirectory = Directory('${dir.path}/lyrics');
    var enabled = false;
    final downloads = DownloadController(
      repo,
      dir,
      downloadLyrics: () => enabled,
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          [73, 68, 51, 0, 0],
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      ),
    );
    await downloads.restore();
    await downloads.enqueue(first);
    await waitFor(
      downloads,
      () => downloads.tasks.first.state == DownloadState.completed,
    );
    expect(downloads.tasks.first.lyricsPath, isNull);
    await downloads.saveLyrics(first.key);
    final path = downloads.tasks.first.lyricsPath!;
    expect(await File(path).exists(), isTrue);
    enabled = true;
    repo.fail = true;
    await downloads.enqueue(second);
    await waitFor(
      downloads,
      () =>
          downloads.tasks.first.state == DownloadState.completed &&
          downloads.tasks.first.lyricsError != null,
    );
    expect(downloads.tasks.first.lyricsError, isNotNull);
    expect(await File(downloads.tasks.first.path!).exists(), isTrue);
    await downloads.remove(first.key);
    expect(await File(path).exists(), isFalse);
    await downloads.close();
    repo.api.close();
    await dir.delete(recursive: true);
  });
  test(
    '真实双平台推荐可用且有曲目和封面',
    () async {
      final api = NeteaseApi(
        client: http.Client(),
        deviceId: 'suishiting-live-test',
      );
      final qq = QqApi(client: http.Client());
      final repo = MusicRepository(api, qqApi: qq);
      try {
        for (final platform in MusicPlatform.values) {
          final result = await repo.recommendationsFor(platform);
          expect(result.songs, isNotEmpty, reason: platform.name);
          expect(result.songs.first.name, isNotEmpty);
          expect(
            result.songs.first.artworkUrl,
            startsWith('http'),
            reason: '${platform.name} album cover',
          );
          // ignore: avoid_print
          print(
            '${platform.label}: ${result.songs.length}首, ${result.songs.first.name}',
          );
        }
      } finally {
        api.close();
        qq.close();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_RECOMMENDATIONS'),
    timeout: const Timeout(Duration(seconds: 80)),
  );
}
