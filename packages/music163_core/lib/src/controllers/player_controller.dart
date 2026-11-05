import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../data/audio_backend.dart';
import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';
import 'library_controller.dart';

class PlayerController extends SafeNotifier {
  PlayerController(
    this._repository,
    this._backend, {
    this.library,
    this.localPathFor,
    Random? random,
  }) : _random = random ?? Random() {
    mode = library?.playbackMode ?? PlaybackMode.sequence;
    _events = _backend.events.listen((event) {
      isPlaying = event.playing && !event.completed;
      isLoading = _resolving || event.loading;
      position = event.position;
      duration = event.duration;
      if (event.completed &&
          !_resolving &&
          source != null &&
          error == null &&
          !_handledCompletion &&
          _wantsPlaying) {
        _handledCompletion = true;
        unawaited(_advance(automatic: true));
      }
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
  final LibraryController? library;
  final String? Function(Song song)? localPathFor;
  final Random _random;
  final List<Song> _queue = [];
  List<Song> get queue => List.unmodifiable(_queue);
  int currentIndex = -1;
  PlaybackMode mode = PlaybackMode.sequence;
  final List<String> _shuffleBag = [];
  final List<String> _played = [];
  final Map<String, String> _localPaths = {};
  bool _handledCompletion = false;
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

  Future<void> play(Song song) async {
    if (closed) return;
    var index = _queue.indexWhere((e) => e.key == song.key);
    if (index < 0) {
      _queue
        ..clear()
        ..add(song);
      index = 0;
      _shuffleBag.clear();
      _played.clear();
    }
    currentIndex = index;
    await _playSelected(song);
  }

  Future<void> _playSelected(Song song) => _play(song, () async {
    final path = _localPaths[song.key] ?? localPathFor?.call(song);
    if (path != null && await File(path).exists()) {
      return _localSource(path);
    } else {
      return _repository.playbackFor(song);
    }
  });

  MediaSource _localSource(String path) => MediaSource(
    url: File(path).uri,
    extension: path.split('.').last.toLowerCase(),
    level: 'local',
    bitrate: 0,
    isTrial: false,
  );

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (closed || songs.isEmpty) return;
    if (startIndex < 0 || startIndex >= songs.length) {
      throw RangeError.index(startIndex, songs);
    }
    final selected = songs[startIndex];
    final keys = <String>{};
    _queue
      ..clear()
      ..addAll(songs.where((s) => keys.add(s.key)));
    currentIndex = _queue.indexWhere((s) => s.key == selected.key);
    _shuffleBag.clear();
    _played.clear();
    await _playSelected(selected);
  }

  void addToQueue(Song song) {
    if (closed || _queue.any((e) => e.key == song.key)) return;
    _queue.add(song);
    _shuffleBag.clear();
    changed();
  }

  Future<void> setMode(PlaybackMode value) async {
    if (closed) return;
    if (library != null) {
      await library!.setPlaybackMode(value);
      if (library!.error != null) {
        error = library!.error;
        changed();
        return;
      }
    }
    mode = value;
    _shuffleBag.clear();
    changed();
  }

  Future<void> next() => _advance(automatic: false);
  Future<void> _advance({required bool automatic}) async {
    if (closed || _queue.isEmpty) return;
    if (automatic && mode == PlaybackMode.repeatOne && currentSong != null) {
      await _playSelected(currentSong!);
      return;
    }
    int nextIndex;
    if (mode == PlaybackMode.shuffle && _queue.length > 1) {
      if (_shuffleBag.isEmpty) {
        _shuffleBag.addAll(
          _queue.where((e) => e.key != currentSong?.key).map((e) => e.key),
        );
        _shuffleBag.shuffle(_random);
      }
      final nextKey = _shuffleBag.removeLast();
      nextIndex = _queue.indexWhere((e) => e.key == nextKey);
    } else {
      nextIndex = currentIndex + 1;
      if (nextIndex >= _queue.length) {
        if (automatic && mode == PlaybackMode.sequence) {
          _wantsPlaying = false;
          isPlaying = false;
          changed();
          return;
        }
        nextIndex = 0;
      }
    }
    if (currentSong != null) {
      _played.add(currentSong!.key);
      if (_played.length > 1000) _played.removeAt(0);
    }
    currentIndex = nextIndex;
    await _playSelected(_queue[nextIndex]);
  }

  Future<void> previous() async {
    if (closed || _queue.isEmpty) return;
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    var index = currentIndex - 1;
    if (mode == PlaybackMode.shuffle && _played.isNotEmpty) {
      final previousKey = _played.removeLast();
      index = _queue.indexWhere((e) => e.key == previousKey);
    }
    if (index < 0) index = _queue.length - 1;
    currentIndex = index;
    _shuffleBag.clear();
    await _playSelected(_queue[index]);
  }

  Future<void> playLocal(Song song, String path) async {
    if (closed) return;
    _localPaths[song.key] = path;
    if (!_queue.any((e) => e.key == song.key)) {
      _queue
        ..clear()
        ..add(song);
      _shuffleBag.clear();
      _played.clear();
    }
    currentIndex = _queue.indexWhere((e) => e.key == song.key);
    await _play(song, () async {
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
  }

  Future<void> _play(Song song, Future<MediaSource> Function() resolve) async {
    if (closed) return;
    final generation = ++_generation;
    currentSong = song;
    source = null;
    error = null;
    position = Duration.zero;
    duration = song.duration;
    _resolving = true;
    _handledCompletion = false;
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
    currentIndex = -1;
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
