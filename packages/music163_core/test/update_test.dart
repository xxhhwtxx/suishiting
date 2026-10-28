import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';

final apkBytes = <int>[80, 75, 3, 4, 1, 2, 3, 4];
final testRelease = AppRelease(
  version: '1.3.0',
  notes: '新版说明',
  size: apkBytes.length,
  pageUrl: Uri.parse(
    'https://github.com/xxhhwtxx/suishiting/releases/tag/v1.3.0',
  ),
  downloadUrl: Uri.parse(
    'https://github.com/xxhhwtxx/suishiting/releases/download/v1.3.0/Suishiting-1.3.0.apk',
  ),
  sha256: sha256.convert(apkBytes).toString(),
  assetId: 123,
);

class FakeUpdatePlatform implements UpdatePlatform {
  FakeUpdatePlatform(this.directory);
  final Directory directory;
  InstalledAppInfo info = const InstalledAppInfo(
    versionName: '1.2.0',
    versionCode: 8,
  );
  bool allowed = false;
  int installations = 0;
  int settingsOpened = 0;
  String? path;
  @override
  Future<InstalledAppInfo> installedApp() async => info;
  @override
  Future<Directory> updateDirectory() async => directory;
  @override
  Future<bool> canInstallPackages() async => allowed;
  @override
  Future<void> openInstallSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> installApk(String path) async {
    installations++;
    this.path = path;
  }
}

class FakeReleases extends ReleaseApi {
  FakeReleases({this.value})
    : super(client: MockClient((_) async => http.Response('{}', 200)));
  AppRelease? value;
  int checks = 0;
  @override
  Future<AppRelease?> latest() async {
    checks++;
    return value;
  }
}

Map<String, dynamic> payload({
  String version = 'v1.3.0',
  String? digest,
  String? url,
}) => {
  'tag_name': version,
  'body': '改进体验',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'id': 123,
      'name': 'Suishiting-${version.replaceFirst('v', '')}.apk',
      'state': 'uploaded',
      'size': apkBytes.length,
      'digest': digest ?? 'sha256:${testRelease.sha256}',
      'browser_download_url': url ?? testRelease.downloadUrl.toString(),
    },
  ],
};
http.Response jsonReply(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('语义版本比较，不把1.10排在1.9前面或重复更新同一构建', () {
    expect(compareReleaseVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareReleaseVersions('v1.2.0+10', '1.2.0+8'), greaterThan(0));
    expect(compareReleaseVersions('1.2.0', '1.2.0'), 0);
    expect(
      () => compareReleaseVersions('latest', '1.2.0'),
      throwsFormatException,
    );
  });

  test('从固定公开仓库读取Release和GitHub SHA256，不带账号Cookie', () async {
    final api = ReleaseApi(
      client: MockClient((r) async {
        expect(
          r.url.toString(),
          'https://api.github.com/repos/xxhhwtxx/suishiting/releases/latest',
        );
        expect(r.headers.containsKey('cookie'), isFalse);
        expect(r.headers.containsKey('authorization'), isFalse);
        return jsonReply(payload());
      }),
    );
    final result = await api.latest();
    expect(result?.version, '1.3.0');
    expect(result?.sha256, testRelease.sha256);
    api.close();
  });
  test('没有发布版或只有预发布版本时不提供更新', () async {
    for (final reply in [
      http.Response('{}', 404),
      jsonReply({...payload(), 'draft': true}),
      jsonReply({...payload(), 'prerelease': true}),
      jsonReply({...payload(), 'assets': []}),
    ]) {
      final api = ReleaseApi(client: MockClient((_) async => reply));
      expect(await api.latest(), isNull);
      api.close();
    }
  });
  test('拒绝缺少摘要、外国仓库地址和无效版本号的更新', () async {
    for (final data in [
      payload(digest: ''),
      payload(url: 'https://example.com/other.apk'),
      payload(version: 'nightly'),
    ]) {
      final api = ReleaseApi(client: MockClient((_) async => jsonReply(data)));
      await expectLater(api.latest(), throwsA(isA<MusicException>()));
      api.close();
    }
  });
  test('GitHub限流有明确错误，不误报为最新版本', () async {
    final api = ReleaseApi(
      client: MockClient((_) async => http.Response('{}', 403)),
    );
    await expectLater(api.latest(), throwsA(isA<MusicException>()));
    api.close();
  });

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'suishiting_update_test_',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('初始化仅读取本机版本，检查后区分暂无发布/最新/可更新', () async {
    final platform = FakeUpdatePlatform(directory), api = FakeReleases();
    final controller = UpdateController(api: api, platform: platform);
    try {
      await controller.initialize();
      expect(api.checks, 0);
      expect(controller.currentVersionName, '1.2.0');
      await controller.check();
      expect(controller.status, UpdateStatus.noRelease);
      api.value = testRelease;
      await controller.check();
      expect(controller.status, UpdateStatus.available);
      platform.info = const InstalledAppInfo(
        versionName: '1.3.0',
        versionCode: 10,
      );
      await controller.check();
      expect(controller.status, UpdateStatus.upToDate);
    } finally {
      await controller.close();
    }
  });
  test('带构建号的同版本Release不会在已安装后反复提示', () async {
    final api = FakeReleases(
      value: AppRelease(
        version: '1.2.0+8',
        notes: '',
        size: 8,
        pageUrl: testRelease.pageUrl,
        downloadUrl: testRelease.downloadUrl,
        sha256: testRelease.sha256,
        assetId: 1,
      ),
    );
    final controller = UpdateController(
      api: api,
      platform: FakeUpdatePlatform(directory),
    );
    await controller.check();
    expect(controller.status, UpdateStatus.upToDate);
    await controller.close();
  });
  test('下载校验完整后才发布文件，并按用户操作打开权限设置和安装', () async {
    final platform = FakeUpdatePlatform(directory);
    final controller = UpdateController(
      api: FakeReleases(value: testRelease),
      platform: platform,
      downloadClientFactory: () => MockClient((r) async {
        expect(r.headers.containsKey('cookie'), isFalse);
        return http.Response.bytes(
          apkBytes,
          200,
          headers: {'content-type': 'application/vnd.android.package-archive'},
        );
      }),
    );
    try {
      await controller.check();
      await controller.download();
      expect(controller.status, UpdateStatus.ready);
      expect(controller.progress, 1);
      expect(
        directory.listSync().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
      await controller.install();
      expect(controller.status, UpdateStatus.permissionRequired);
      expect(platform.settingsOpened, 0);
      expect(platform.installations, 0);
      await controller.openInstallSettings();
      expect(platform.settingsOpened, 1);
      platform.allowed = true;
      await controller.install();
      expect(platform.installations, 1);
      expect(await File(platform.path!).readAsBytes(), apkBytes);
    } finally {
      await controller.close();
    }
  });
  test('SHA不符或被截断的安装包不会留下可安装文件', () async {
    for (final bytes in [
      <int>[80, 75, 3, 4, 9, 9, 9, 9],
      <int>[80, 75, 3, 4],
    ]) {
      final controller = UpdateController(
        api: FakeReleases(value: testRelease),
        platform: FakeUpdatePlatform(directory),
        downloadClientFactory: () =>
            MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      await controller.check();
      await controller.download();
      expect(controller.status, UpdateStatus.failed);
      expect(controller.hasDownloadedFile, isFalse);
      expect(directory.listSync(), isEmpty);
      await controller.close();
    }
  });
  test('更新下载拒绝跳转到非GitHub服务器', () async {
    var calls = 0;
    final controller = UpdateController(
      api: FakeReleases(value: testRelease),
      platform: FakeUpdatePlatform(directory),
      downloadClientFactory: () => MockClient((_) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/other.apk'},
        );
      }),
    );
    await controller.check();
    await controller.download();
    expect(calls, 1);
    expect(controller.status, UpdateStatus.failed);
    expect(controller.hasDownloadedFile, isFalse);
    await controller.close();
  });
  test('安装前再次校验缓存，文件被修改后不能调用安装器', () async {
    final platform = FakeUpdatePlatform(directory)..allowed = true;
    final controller = UpdateController(
      api: FakeReleases(value: testRelease),
      platform: platform,
      downloadClientFactory: () =>
          MockClient((_) async => http.Response.bytes(apkBytes, 200)),
    );
    await controller.check();
    await controller.download();
    await File(
      '${directory.path}/update-123.apk',
    ).writeAsBytes([80, 75, 3, 4, 9, 9, 9, 9]);
    await controller.install();
    expect(controller.status, UpdateStatus.failed);
    expect(platform.installations, 0);
    await controller.close();
  });
  test('取消实际HTTP下载会停止传输并移除半成品', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const length = 1024 * 1024;
    server.listen((request) async {
      request.response.contentLength = length;
      request.response.headers.contentType = ContentType(
        'application',
        'octet-stream',
      );
      try {
        request.response.add([80, 75, 3, 4]);
        await request.response.flush();
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          request.response.add(List.filled(4096, 1));
          await request.response.flush();
        }
      } catch (_) {
        /* Expected after cancellation. */
      } finally {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    final local = AppRelease(
      version: '1.3.0',
      notes: '',
      size: length,
      pageUrl: testRelease.pageUrl,
      downloadUrl: Uri.parse('http://127.0.0.1:${server.port}/test.apk'),
      sha256: testRelease.sha256,
      assetId: 999,
    );
    final controller = UpdateController(
      api: FakeReleases(value: local),
      platform: FakeUpdatePlatform(directory),
    );
    final received = Completer<void>();
    controller.addListener(() {
      if (controller.downloadedBytes > 0 && !received.isCompleted) {
        received.complete();
      }
    });
    try {
      await controller.check();
      final job = controller.download();
      await received.future.timeout(const Duration(seconds: 5));
      controller.cancelDownload();
      await job;
      expect(controller.status, UpdateStatus.available);
      expect(controller.error, isNull);
      expect(directory.listSync(), isEmpty);
    } finally {
      await controller.close();
      await server.close(force: true);
    }
  });
}
