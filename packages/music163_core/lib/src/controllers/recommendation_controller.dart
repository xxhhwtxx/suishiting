import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class RecommendationController extends SafeNotifier {
  RecommendationController(this._repository);
  final MusicRepository _repository;
  MusicPlatform platform = MusicPlatform.netease;
  List<Song> _songs = [];
  List<Song> get songs => List.unmodifiable(_songs);
  bool isLoading = false;
  String? error;
  String sourceLabel = '新歌推荐';
  int _generation = 0;
  bool _loaded = false;
  Future<void> setPlatform(MusicPlatform value) async {
    if (closed || value == platform) return;
    platform = value;
    _songs = [];
    _loaded = false;
    await load(refresh: true);
  }

  Future<void> load({bool refresh = false}) async {
    if (closed || (isLoading && !refresh) || (_loaded && !refresh)) return;
    final generation = ++_generation;
    isLoading = true;
    error = null;
    changed();
    try {
      final result = await _repository.recommendationsFor(platform);
      if (closed || generation != _generation) return;
      final keys = <String>{};
      _songs = result.songs.where((e) => keys.add(e.key)).toList();
      sourceLabel = result.label;
      _loaded = true;
    } catch (e) {
      if (!closed && generation == _generation) error = userError(e);
    } finally {
      if (!closed && generation == _generation) {
        isLoading = false;
        changed();
      }
    }
  }
}
