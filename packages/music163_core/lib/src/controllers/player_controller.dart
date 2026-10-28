import 'dart:async';
import 'dart:io';
import '../data/audio_backend.dart';
import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class PlayerController extends SafeNotifier {
  PlayerController(this._repository, this._backend) {
    _events = _backend.events.listen((event) {
      isPlaying = event.playing && !event.completed;
      isLoading = _resolving || event.loading;
      position = event.position;
      duration = event.duration;
      changed();
    });
    _errors = _backend.errors.listen((_) {
      isPlaying = false;
      isLoading = false;
      _resolving = false;
      error = '音频播放失败，请检查网络或重新选择歌曲。';
      changed();
    });
  }
  final MusicRepository _repository;
  final AudioBackend _backend;
  late final StreamSubscription<AudioEvent> _events;
  late final StreamSubscription<Object> _errors;
  Song? currentSong;
  bool isPlaying = false;
  bool isLoading = false;
  bool _resolving = false;
  bool _wantsPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  MediaSource? source;
  String? error;
  int _generation = 0;

  Future<void> play(Song song) =>
      _play(song, () => _repository.playbackFor(song));

  Future<void> playLocal(Song song, String path) => _play(song, () async {
    final file = File(path);
    if (!await file.exists()) throw const MusicException('本地文件不存在，请重新下载。');
    return MediaSource(
      url: file.uri,
      extension: path.split('.').last.toLowerCase(),
      level: 'local',
      bitrate: 0,
      isTrial: false,
    );
  });

  Future<void> _play(Song song, Future<MediaSource> Function() resolve) async {
    if (closed) return;
    final generation = ++_generation;
    currentSong = song;
    source = null;
    error = null;
    position = Duration.zero;
    duration = song.duration;
    _resolving = true;
    isLoading = true;
    _wantsPlaying = true;
    changed();
    try {
      await _backend.pause();
      final resolved = await resolve();
      if (generation != _generation || closed) return;
      await _backend.load(resolved.url);
      if (generation != _generation || closed) return;
      source = resolved;
      _resolving = false;
      isLoading = false;
      if (_wantsPlaying) _start(generation);
    } catch (e) {
      if (generation == _generation) {
        error = userError(e);
        _resolving = false;
        isLoading = false;
        isPlaying = false;
      }
    } finally {
      if (generation == _generation) changed();
    }
  }

  void _start(int generation) {
    // just_audio.play completes when playback ends, so never await it in UI commands.
    unawaited(
      _backend.play().catchError((Object _) {
        if (generation == _generation && !closed) {
          error = '播放未能开始，请重新点播。';
          isPlaying = false;
          changed();
        }
      }),
    );
  }

  Future<void> pause() async {
    _wantsPlaying = false;
    try {
      await _backend.pause();
      isPlaying = false;
    } catch (_) {
      error = '暂停失败，请重试。';
    }
    changed();
  }

  Future<void> resume() async {
    if (source == null || closed) return;
    _wantsPlaying = true;
    error = null;
    if (duration > Duration.zero && position >= duration) {
      await seek(Duration.zero);
    }
    _start(_generation);
    changed();
  }

  Future<void> seek(Duration target) async {
    if (source == null || closed) return;
    final bounded = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    try {
      await _backend.seek(bounded);
      position = bounded;
    } catch (_) {
      error = '定位播放进度失败，请重试。';
    }
    changed();
  }

  Future<void> stop() async {
    _generation++;
    _wantsPlaying = false;
    _resolving = false;
    try {
      await _backend.stop();
    } catch (_) {
      error = '停止播放失败，请重试。';
    }
    isPlaying = false;
    isLoading = false;
    position = Duration.zero;
    source = null;
    currentSong = null;
    changed();
  }

  Future<void> close() async {
    _generation++;
    dispose();
    await _events.cancel();
    await _errors.cancel();
    await _backend.close();
  }
}
