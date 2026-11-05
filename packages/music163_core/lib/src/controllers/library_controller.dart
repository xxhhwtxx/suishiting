import 'dart:convert';
import '../data/credentials.dart';
import '../domain/models.dart';
import 'base_controller.dart';

enum AppThemePreference { light, dark, system }

enum PlaybackMode { sequence, repeatAll, repeatOne, shuffle }

class LibraryController extends SafeNotifier {
  LibraryController(this._store);
  final CredentialStore _store;
  static const storageKey = 'suishiting.library.v1';
  final List<Song> _favorites = [];
  final List<String> _history = [];
  List<Song> get favorites => List.unmodifiable(_favorites);
  List<String> get history => List.unmodifiable(_history);
  AppThemePreference themePreference = AppThemePreference.light;
  PlaybackMode playbackMode = PlaybackMode.sequence;
  bool downloadLyrics = true;
  String? error;
  Future<void> _writes = Future.value();

  Future<void> restore() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      themePreference =
          AppThemePreference.values
              .where((e) => e.name == data['theme'])
              .firstOrNull ??
          AppThemePreference.light;
      playbackMode =
          PlaybackMode.values
              .where((e) => e.name == data['mode'])
              .firstOrNull ??
          PlaybackMode.sequence;
      downloadLyrics = data['downloadLyrics'] is bool
          ? data['downloadLyrics'] as bool
          : true;
      for (final item in (data['favorites'] as List? ?? []).take(1000)) {
        try {
          final song = Song.fromJson(Map<String, dynamic>.from(item as Map));
          if (!isFavorite(song)) _favorites.add(song);
        } catch (_) {
          error = '部分收藏记录无法读取。';
        }
      }
      for (final item in data['history'] as List? ?? []) {
        if (item is String &&
            item.trim().isNotEmpty &&
            !_history.contains(item)) {
          _history.add(item);
        }
        if (_history.length == 30) break;
      }
    } catch (_) {
      error = '本机偏好记录无法读取，请重新设置。';
    }
    changed();
  }

  bool isFavorite(Song song) => _favorites.any((e) => e.key == song.key);
  Future<void> _update(void Function() mutation) {
    final result = _writes.catchError((Object _) {}).then((_) async {
      if (closed) return;
      // Apply in call order, and restore the last saved state on failure.
      final beforeFavorites = List<Song>.of(_favorites);
      final beforeHistory = List<String>.of(_history);
      final beforeTheme = themePreference;
      final beforeMode = playbackMode;
      final beforeLyrics = downloadLyrics;
      try {
        mutation();
        await _store.write(
          storageKey,
          jsonEncode({
            'favorites': _favorites.map((e) => e.toJson()).toList(),
            'history': _history,
            'theme': themePreference.name,
            'mode': playbackMode.name,
            'downloadLyrics': downloadLyrics,
          }),
        );
        error = null;
      } catch (_) {
        _favorites
          ..clear()
          ..addAll(beforeFavorites);
        _history
          ..clear()
          ..addAll(beforeHistory);
        themePreference = beforeTheme;
        playbackMode = beforeMode;
        downloadLyrics = beforeLyrics;
        error = '本机设置保存失败，请重试。';
      }
      changed();
    });
    _writes = result;
    return result;
  }

  Future<void> toggleFavorite(Song song) => _update(() {
    if (isFavorite(song)) {
      _favorites.removeWhere((e) => e.key == song.key);
    } else if (_favorites.length < 1000) {
      _favorites.insert(0, song);
    } else {
      throw const MusicException('收藏已达1000首，请先整理收藏。');
    }
  });
  Future<void> addSearch(String query) {
    final text = query.trim();
    if (text.isEmpty) return Future.value();
    return _update(() {
      _history.removeWhere((e) => e.toLowerCase() == text.toLowerCase());
      _history.insert(0, text.length > 1000 ? text.substring(0, 1000) : text);
      if (_history.length > 30) _history.removeRange(30, _history.length);
    });
  }

  Future<void> removeSearch(String text) =>
      _update(() => _history.remove(text));
  Future<void> clearHistory() => _update(_history.clear);
  Future<void> setTheme(AppThemePreference value) =>
      _update(() => themePreference = value);
  Future<void> setDownloadLyrics(bool value) =>
      _update(() => downloadLyrics = value);
  Future<void> setPlaybackMode(PlaybackMode value) =>
      _update(() => playbackMode = value);
  Future<void> close() async {
    await _writes.catchError((Object _) {});
    dispose();
  }
}
