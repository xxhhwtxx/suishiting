import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class DownloadController extends SafeNotifier {
  DownloadController(
    this._repository,
    this.directory, {
    this.concurrency = 2,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final MusicRepository _repository;
  final Directory directory;
  final int concurrency;
  final http.Client Function() _clientFactory;
  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  String? error;
  final Map<String, _Transfer> _transfers = {};
  final Map<String, Future<void>> _jobs = {};
  Future<void> _saveQueue = Future.value();
  bool _closing = false;
  File get _manifest => File(p.join(directory.path, 'downloads.json'));

  Future<void> restore() async {
    await directory.create(recursive: true);
    if (!await _manifest.exists()) return;
    try {
      final data = jsonDecode(await _manifest.readAsString()) as List<dynamic>;
      for (final item in data) {
        var task = DownloadTask.fromJson(item as Map<String, dynamic>);
        if (_tasks.any((t) => t.id == task.id)) continue;
        if (task.path != null && !_ownsPath(task.path!)) continue;
        if (task.isActive) {
          task = task.copyWith(
            state: DownloadState.failed,
            error: '上次下载已中断，请重试。',
          );
        }
        if (task.state == DownloadState.completed &&
            (task.path == null || !await File(task.path!).exists())) {
          task = task.copyWith(
            state: DownloadState.failed,
            error: '本地文件不存在，请重新下载。',
          );
        }
        _tasks.add(task);
      }
    } catch (_) {
      error = '下载记录读取失败。已有音频文件仍保存在本机。';
    }
    changed();
  }

  bool _ownsPath(String path) => p.isWithin(
    p.normalize(p.absolute(directory.path)),
    p.normalize(p.absolute(path)),
  );
  DownloadTask? _find(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _replace(DownloadTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _tasks[i] = task;
    changed();
  }

  Future<void> enqueue(Song song) async {
    if (_closing || closed) return;
    final id = song.key;
    final old = _find(id);
    if (old != null && (old.isActive || old.state == DownloadState.completed)) {
      return;
    }
    final task = DownloadTask(id: id, song: song);
    if (old == null) {
      _tasks.insert(0, task);
      changed();
    } else {
      _replace(task);
    }
    await _save();
    _pump();
  }

  void _pump() {
    if (_closing || closed) return;
    final pending = _tasks
        .where(
          (t) => t.state == DownloadState.queued && !_jobs.containsKey(t.id),
        )
        .toList();
    for (final task in pending) {
      if (_jobs.length >= concurrency) break;
      final job = _run(task);
      _jobs[task.id] = job;
      unawaited(
        job.whenComplete(() {
          _jobs.remove(task.id);
          _pump();
        }),
      );
    }
  }

  Future<void> _run(DownloadTask initial) async {
    final id = initial.id;
    final transfer = _Transfer(_clientFactory());
    _transfers[id] = transfer;
    File? partial;
    IOSink? sink;
    try {
      _replace(initial.copyWith(state: DownloadState.resolving));
      final source = await _repository.downloadFor(initial.song);
      if (transfer.cancelled || _closing) throw const _Cancelled();
      final filename =
          '${safeFileName('${initial.song.key}-${initial.song.name}')}.${source.extension}';
      final finalFile = File(p.join(directory.path, filename));
      partial = File('${finalFile.path}.part');
      final request = http.AbortableRequest(
        'GET',
        source.url,
        abortTrigger: transfer.abort.future,
      );
      // Never attach account cookies to a media CDN request.
      final response = await transfer.client
          .send(request)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw const MusicException('音频服务器拒绝下载，请重试。');
      }
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('text/') ||
          type.contains('json') ||
          type.contains('xml')) {
        throw const MusicException('服务器未返回音频文件，下载已停止。');
      }
      final length = response.contentLength;
      if (length != null && length > 1024 * 1024 * 1024) {
        throw const MusicException('音频文件过大，下载已停止。');
      }
      _replace(
        initial.copyWith(state: DownloadState.downloading, totalBytes: length),
      );
      sink = partial.openWrite();
      var bytes = 0;
      final prefix = <int>[];
      var notifiedAt = DateTime.now();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (transfer.cancelled || _closing) throw const _Cancelled();
        if (prefix.length < 512) prefix.addAll(chunk.take(512 - prefix.length));
        bytes += chunk.length;
        if (bytes > 1024 * 1024 * 1024) {
          throw const MusicException('音频文件过大，下载已停止。');
        }
        sink.add(chunk);
        if (DateTime.now().difference(notifiedAt).inMilliseconds > 200) {
          await sink.flush();
          _replace(
            initial.copyWith(
              state: DownloadState.downloading,
              downloadedBytes: bytes,
              totalBytes: length,
            ),
          );
          notifiedAt = DateTime.now();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (transfer.cancelled || _closing) throw const _Cancelled();
      if (bytes == 0 ||
          (length != null && length != bytes) ||
          !looksLikeAudio(prefix)) {
        throw const MusicException('音频文件不完整或格式异常，请重试。');
      }
      await partial.rename(finalFile.path);
      partial = null;
      _replace(
        initial.copyWith(
          state: DownloadState.completed,
          path: finalFile.path,
          downloadedBytes: bytes,
          totalBytes: bytes,
        ),
      );
    } catch (e) {
      final cancelled = transfer.cancelled || e is _Cancelled || _closing;
      _replace(
        initial.copyWith(
          state: cancelled ? DownloadState.cancelled : DownloadState.failed,
          error: cancelled ? null : userError(e),
        ),
      );
    } finally {
      transfer.client.close();
      _transfers.remove(id);
      try {
        await sink?.close();
      } catch (_) {}
      if (partial != null) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
      }
      await _save();
    }
  }

  void cancel(String id) {
    final task = _find(id);
    if (task == null || !task.isActive) return;
    _transfers[id]?.cancel();
    _replace(task.copyWith(state: DownloadState.cancelled, clearError: true));
    unawaited(_save());
  }

  Future<void> retry(String id) async {
    final task = _find(id);
    if (task == null ||
        task.isActive ||
        task.state == DownloadState.completed) {
      return;
    }
    await _jobs[id];
    if (_closing || closed) return;
    _replace(DownloadTask(id: id, song: task.song));
    await _save();
    _pump();
  }

  Future<void> remove(String id) async {
    cancel(id);
    await _jobs[id];
    final task = _find(id);
    if (task == null) return;
    if (task.path != null && _ownsPath(task.path!)) {
      try {
        final file = File(task.path!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        error = '文件删除失败，请重试。';
        changed();
        return;
      }
    }
    _tasks.removeWhere((t) => t.id == id);
    await _save();
    changed();
  }

  Future<void> _save() {
    final next = _saveQueue
        .then((_) async {
          final temp = File('${_manifest.path}.tmp');
          await temp.writeAsString(
            jsonEncode(_tasks.map((t) => t.toJson()).toList()),
            flush: true,
          );
          await temp.rename(_manifest.path);
        })
        .catchError((Object _) {
          error = '下载记录保存失败，请检查可用存储空间。';
          changed();
        });
    _saveQueue = next;
    return next;
  }

  Future<void> close() async {
    _closing = true;
    for (final transfer in _transfers.values) {
      transfer.cancel();
    }
    await Future.wait(_jobs.values.toList());
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].isActive) {
        _tasks[i] = _tasks[i].copyWith(state: DownloadState.cancelled);
      }
    }
    await _save();
    dispose();
  }
}

class _Transfer {
  _Transfer(this.client);
  final http.Client client;
  final abort = Completer<void>();
  bool get cancelled => abort.isCompleted;
  void cancel() {
    if (!abort.isCompleted) {
      abort.complete();
      client.close();
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

String safeFileName(String value) {
  final clean = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (clean.isEmpty) return '歌曲';
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in clean.runes) {
    final part = String.fromCharCode(rune);
    final length = utf8.encode(part).length;
    if (bytes + length > 180) break;
    result.write(part);
    bytes += length;
  }
  return result.toString();
}

bool looksLikeAudio(List<int> bytes) {
  if (bytes.length < 4) return false;
  final prefix = String.fromCharCodes(bytes.take(4));
  return prefix.startsWith('ID3') ||
      prefix == 'fLaC' ||
      prefix == 'OggS' ||
      (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) ||
      (bytes.length >= 8 &&
          String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp');
}
