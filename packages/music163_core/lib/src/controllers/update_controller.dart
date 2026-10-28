import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../data/release_api.dart';
import '../data/update_platform.dart';
import '../domain/models.dart';
import '../domain/update_models.dart';
import 'base_controller.dart';

class UpdateController extends SafeNotifier {
  UpdateController({
    ReleaseApi? api,
    UpdatePlatform? platform,
    http.Client Function()? downloadClientFactory,
  }) : _api = api ?? ReleaseApi(),
       _platform = platform ?? AndroidUpdatePlatform(),
       _downloadClientFactory = downloadClientFactory ?? http.Client.new;
  final ReleaseApi _api;
  final UpdatePlatform _platform;
  final http.Client Function() _downloadClientFactory;
  UpdateStatus status = UpdateStatus.idle;
  InstalledAppInfo? installed;
  String? get currentVersionName => installed?.versionName;
  AppRelease? release;
  String? error;
  String? message;
  int downloadedBytes = 0;
  int? totalBytes;
  double? get progress =>
      totalBytes == null ? null : (downloadedBytes / totalBytes!).clamp(0, 1);
  bool get isBusy => {
    UpdateStatus.checking,
    UpdateStatus.downloading,
    UpdateStatus.installing,
  }.contains(status);
  bool get hasDownloadedFile => _apkPath != null;
  Uri get repositoryUrl => _api.repositoryUrl;
  String? _apkPath;
  Completer<void>? _abort;
  http.Client? _downloadClient;
  Future<void>? _downloadJob;
  Future<void>? _initializing;
  bool _closing = false;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final info = await _platform.installedApp();
      if (!closed) {
        installed = info;
        changed();
      }
    } catch (_) {
      /* Unsupported test/desktop host: manual check reports errors. */
    }
  }

  Future<void> check() async {
    if (isBusy || closed || _closing) return;
    status = UpdateStatus.checking;
    error = null;
    message = null;
    release = null;
    _apkPath = null;
    changed();
    try {
      final info = await _platform.installedApp();
      if (closed) return;
      installed = info;
      final latest = await _api.latest();
      if (closed) return;
      release = latest;
      if (latest == null) {
        status = UpdateStatus.noRelease;
        message = '暂无可用更新';
      } else if (compareReleaseVersions(
            latest.version,
            latest.version.contains('+')
                ? '${info.versionName.split('+').first}+${info.versionCode}'
                : info.versionName,
          ) <=
          0) {
        status = UpdateStatus.upToDate;
        message = '已是最新版本';
      } else {
        status = UpdateStatus.available;
      }
    } catch (e) {
      if (!closed) {
        status = UpdateStatus.failed;
        error = userError(e);
      }
    }
    if (!closed) changed();
  }

  Future<void> download() async {
    if (isBusy || closed || _closing || release == null) return;
    final selected = release!;
    status = UpdateStatus.downloading;
    error = null;
    message = null;
    downloadedBytes = 0;
    totalBytes = selected.size;
    _apkPath = null;
    final abort = Completer<void>();
    _abort = abort;
    final client = _downloadClientFactory();
    _downloadClient = client;
    changed();
    final job = _download(selected, client, abort);
    _downloadJob = job;
    await job;
    if (identical(_downloadJob, job)) _downloadJob = null;
  }

  Future<http.StreamedResponse> _openAsset(
    AppRelease selected,
    http.Client client,
    Completer<void> abort,
  ) async {
    var url = selected.downloadUrl;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (abort.isCompleted || closed) throw const _UpdateCancelled();
      final request =
          http.AbortableRequest('GET', url, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers['User-Agent'] = 'Suishiting-Android';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null) throw const MusicException('更新下载跳转无效。');
        final next = url.resolve(location);
        if (next.scheme != 'https' ||
            next.userInfo.isNotEmpty ||
            !{
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(next.host)) {
          throw const MusicException('更新下载跳转地址不受支持。');
        }
        url = next;
        continue;
      }
      return response;
    }
    throw const MusicException('更新下载跳转次数过多。');
  }

  Future<void> _download(
    AppRelease selected,
    http.Client client,
    Completer<void> abort,
  ) async {
    File? partial;
    IOSink? sink;
    try {
      final directory = await _platform.updateDirectory();
      await directory.create(recursive: true);
      final finalFile = File(
        p.join(directory.path, 'update-${selected.assetId}.apk'),
      );
      partial = File('${finalFile.path}.part');
      final response = await _openAsset(selected, client, abort);
      if (response.statusCode != 200) {
        throw const MusicException('安装包下载失败，请稍后重试。');
      }
      if (response.contentLength != null &&
          response.contentLength != selected.size) {
        throw const MusicException('安装包大小不符，请重新检查更新。');
      }
      final type = response.headers['content-type'] ?? '';
      if (type.startsWith('text/') || type.contains('json')) {
        throw const MusicException('服务器未返回 APK 安装包。');
      }
      sink = partial.openWrite();
      final prefix = <int>[];
      var lastNotice = DateTime.now();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (abort.isCompleted || closed) throw const _UpdateCancelled();
        if (prefix.length < 4) prefix.addAll(chunk.take(4 - prefix.length));
        downloadedBytes += chunk.length;
        if (downloadedBytes > selected.size ||
            downloadedBytes > ReleaseApi.maxApkSize) {
          throw const MusicException('安装包大小异常，已停止下载。');
        }
        sink.add(chunk);
        if (DateTime.now().difference(lastNotice).inMilliseconds >= 150) {
          changed();
          lastNotice = DateTime.now();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (abort.isCompleted || closed) throw const _UpdateCancelled();
      if (downloadedBytes != selected.size ||
          prefix.length < 4 ||
          prefix[0] != 80 ||
          prefix[1] != 75 ||
          prefix[2] != 3 ||
          prefix[3] != 4) {
        throw const MusicException('安装包不完整，请重新下载。');
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != selected.sha256) {
        throw const MusicException('安装包校验失败，请重新下载。');
      }
      if (abort.isCompleted || closed) throw const _UpdateCancelled();
      if (await finalFile.exists()) await finalFile.delete();
      await partial.rename(finalFile.path);
      partial = null;
      _apkPath = finalFile.path;
      status = UpdateStatus.ready;
      message = '下载完成，可以安装新版';
    } catch (e) {
      if (!closed) {
        if (abort.isCompleted || e is _UpdateCancelled) {
          status = UpdateStatus.available;
          message = '下载已取消';
          error = null;
        } else {
          status = UpdateStatus.failed;
          error = e is MusicException ? e.message : '更新下载未完成，请检查网络后重试。';
        }
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        /* Keep the original error. */
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {
        /* Android clears the private cache; retain the original failure. */
      }
      client.close();
      if (identical(_downloadClient, client)) {
        _downloadClient = null;
        _abort = null;
      }
      if (!closed) changed();
    }
  }

  void cancelDownload() {
    if (_abort?.isCompleted == false) _abort!.complete();
    _downloadClient?.close();
  }

  Future<void> install() async {
    if (isBusy || closed || _closing || _apkPath == null || release == null) {
      return;
    }
    status = UpdateStatus.installing;
    error = null;
    message = null;
    changed();
    try {
      final file = File(_apkPath!);
      if (!await file.exists() ||
          await file.length() != release!.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              release!.sha256) {
        _apkPath = null;
        throw const MusicException('已下载的安装包不完整，请重新下载。');
      }
      if (closed || _closing) return;
      final allowed = await _platform.canInstallPackages();
      if (closed || _closing) return;
      if (!allowed) {
        status = UpdateStatus.permissionRequired;
        message = '请允许随时听安装应用';
      } else {
        await _platform.installApk(file.path);
        status = UpdateStatus.ready;
        message = '请在系统安装界面完成更新';
      }
    } catch (e) {
      if (!closed) {
        status = UpdateStatus.failed;
        error = e is MusicException ? e.message : '无法打开安装界面，请重试。';
      }
    }
    if (!closed) changed();
  }

  Future<void> openInstallSettings() async {
    try {
      await _platform.openInstallSettings();
    } catch (_) {
      if (!closed) {
        error = '无法打开安装权限设置，请在系统设置中允许安装。';
        changed();
      }
    }
  }

  Future<void> close() async {
    if (closed) return;
    _closing = true;
    cancelDownload();
    _api.close();
    await _downloadJob;
    dispose();
  }
}

class _UpdateCancelled implements Exception {
  const _UpdateCancelled();
}
