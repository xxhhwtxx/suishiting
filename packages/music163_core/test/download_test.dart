import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart' show FakeRepository, first, media;

Future<void> waitFor(
  DownloadController controller,
  bool Function() condition,
) async {
  if (condition()) return;
  final done = Completer<void>();
  void listener() {
    if (condition() && !done.isCompleted) done.complete();
  }

  controller.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('music163_test_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('音频完整后才发布文件，CDN 请求没有账号 Cookie', () async {
    final controller = DownloadController(
      FakeRepository(),
      directory,
      clientFactory: () => MockClient((request) async {
        expect(
          request.headers.keys.map((s) => s.toLowerCase()),
          isNot(contains('cookie')),
        );
        return http.Response.bytes(
          [73, 68, 51, 4, 0, 0, 1, 2],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      }),
    );
    await controller.restore();
    await controller.enqueue(first);
    await waitFor(
      controller,
      () => controller.tasks.single.state == DownloadState.completed,
    );
    final file = File(controller.tasks.single.path!);
    expect(await file.exists(), isTrue);
    expect(await file.length(), 8);
    await controller.close();
    final restored = DownloadController(FakeRepository(), directory);
    await restored.restore();
    expect(restored.tasks.single.state, DownloadState.completed);
    await restored.remove('1');
    expect(await file.exists(), isFalse);
    await restored.close();
  });
  test('拒绝伪装音频的 HTML，清理临时文件', () async {
    final controller = DownloadController(
      FakeRepository(),
      directory,
      clientFactory: () => MockClient(
        (_) async => http.Response(
          '<html>denied</html>',
          200,
          headers: {'content-type': 'application/octet-stream'},
        ),
      ),
    );
    await controller.restore();
    await controller.enqueue(first);
    await waitFor(
      controller,
      () => controller.tasks.single.state == DownloadState.failed,
    );
    await controller.close();
    expect(
      directory.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.mp3') || f.path.endsWith('.part'),
      ),
      isEmpty,
    );
  });
  test('取消解析阶段不会继续下载', () async {
    final source = Completer<MediaSource>();
    var requested = false;
    final repo = FakeRepository()..onSource = (_) => source.future;
    final controller = DownloadController(
      repo,
      directory,
      clientFactory: () => MockClient((_) async {
        requested = true;
        return http.Response('', 200);
      }),
    );
    await controller.restore();
    await controller.enqueue(first);
    controller.cancel('1');
    source.complete(media);
    await controller.close();
    expect(requested, isFalse);
    expect(controller.tasks.single.state, DownloadState.cancelled);
  });
  test('记录中的越界路径不会被读取或删除', () async {
    final outside = File('${directory.path}-outside.mp3');
    await outside.writeAsString('untouched');
    addTearDown(() async {
      if (await outside.exists()) await outside.delete();
    });
    final record = DownloadTask(
      id: '1',
      song: first,
      state: DownloadState.completed,
      path: outside.path,
    );
    await File(
      '${directory.path}/downloads.json',
    ).writeAsString(jsonEncode([record.toJson()]));
    final controller = DownloadController(FakeRepository(), directory);
    await controller.restore();
    expect(controller.tasks, isEmpty);
    await controller.remove('1');
    expect(await outside.readAsString(), 'untouched');
    await controller.close();
  });
  test('文件名过滤目录分隔符，音频头识别不接受 JSON', () {
    expect(safeFileName('../a:b\\c'), isNot(contains('/')));
    expect(safeFileName('../a:b\\c'), isNot(contains('\\')));
    expect(
      utf8.encode(safeFileName('中文歌名' * 100)).length,
      lessThanOrEqualTo(180),
    );
    expect(looksLikeAudio(utf8.encode('{"error":true}')), isFalse);
    expect(looksLikeAudio(utf8.encode('fLaCdata')), isTrue);
  });
  test('真实 HTTP 流传输取消会终止连接并清理半成品', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connected = Completer<void>();
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add([73, 68, 51, 4]);
      await request.response.flush();
      connected.complete();
    });
    final repo = FakeRepository()
      ..onSource = (_) async => MediaSource(
        url: Uri.parse('http://127.0.0.1:${server.port}/audio'),
        extension: 'mp3',
        level: 'standard',
        bitrate: 128000,
        isTrial: false,
      );
    final controller = DownloadController(repo, directory);
    await controller.restore();
    await controller.enqueue(first);
    await connected.future.timeout(const Duration(seconds: 5));
    await waitFor(
      controller,
      () => controller.tasks.single.state == DownloadState.downloading,
    );
    controller.cancel('1');
    await controller.close();
    expect(controller.tasks.single.state, DownloadState.cancelled);
    expect(
      directory.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.part'),
      ),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 12)));
}
