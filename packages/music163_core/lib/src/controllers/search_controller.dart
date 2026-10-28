import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class SearchController extends SafeNotifier {
  SearchController(this._repository);
  final MusicRepository _repository;
  String query = '';
  List<Song> get songs => List.unmodifiable(_songs);
  List<Song> _songs = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  String? error;
  int _generation = 0;
  int _offset = 0;
  MusicPlatform platform = MusicPlatform.netease;

  Future<void> setPlatform(MusicPlatform value) async {
    if (value == platform || closed) return;
    platform = value;
    await search(query);
  }

  Future<void> search(String text) async {
    if (closed) return;
    final request = ++_generation;
    final selectedPlatform = platform;
    query = text.trim();
    _songs = [];
    _offset = 0;
    hasMore = false;
    error = null;
    isLoadingMore = false;
    if (query.isEmpty) {
      isLoading = false;
      changed();
      return;
    }
    isLoading = true;
    changed();
    try {
      final resolved = await _repository.resolveSong(selectedPlatform, query);
      final page = resolved != null
          ? SearchPage(songs: [resolved], hasMore: false, total: 1)
          : await _repository.searchFor(selectedPlatform, query);
      if (request != _generation || closed) return;
      _songs = page.songs;
      _offset = page.nextOffset ?? page.songs.length;
      hasMore = page.hasMore;
    } catch (e) {
      if (request == _generation) error = userError(e);
    } finally {
      if (request == _generation) {
        isLoading = false;
        changed();
      }
    }
  }

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || closed) return;
    final request = _generation;
    isLoadingMore = true;
    error = null;
    changed();
    try {
      final page = await _repository.searchFor(
        platform,
        query,
        offset: _offset,
      );
      if (request != _generation || closed) return;
      final ids = _songs.map((s) => s.key).toSet();
      _songs = [..._songs, ...page.songs.where((s) => ids.add(s.key))];
      _offset = page.nextOffset ?? _offset + page.songs.length;
      hasMore = page.hasMore;
    } catch (e) {
      if (request == _generation) error = userError(e);
    } finally {
      if (request == _generation) {
        isLoadingMore = false;
        changed();
      }
    }
  }
}
