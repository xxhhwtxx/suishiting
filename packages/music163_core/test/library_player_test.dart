import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart'
    show FakeRepository, FakeAudio, MemoryStore, first, second;

const qq = Song(
  id: 1,
  name: 'QQ歌曲',
  artists: '歌手',
  album: '专辑',
  platform: MusicPlatform.qq,
  mid: '0039MnU',
);
const third = Song(id: 3, name: '第三首', artists: '歌手', album: '专辑');
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

class FailingStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw const FileSystemException('full');
    await super.write(key, value);
  }
}

void main() {
  test('重启恢复主题、跨平台收藏、搜索历史、歌词开关和播放模式', () async {
    final store = MemoryStore();
    final library = LibraryController(store);
    expect(library.themePreference, AppThemePreference.light);
    await library.toggleFavorite(first);
    await library.toggleFavorite(qq);
    await library.addSearch('  周杰伦 ');
    await library.addSearch('Avril');
    await library.addSearch('周杰伦');
    await library.setTheme(AppThemePreference.dark);
    await library.setDownloadLyrics(false);
    await library.setPlaybackMode(PlaybackMode.shuffle);
    await library.close();
    final restored = LibraryController(store);
    await restored.restore();
    expect(restored.favorites.map((s) => s.key), ['qq_0039MnU', '1']);
    expect(restored.history, ['周杰伦', 'Avril']);
    expect(restored.themePreference, AppThemePreference.dark);
    expect(restored.downloadLyrics, isFalse);
    expect(restored.playbackMode, PlaybackMode.shuffle);
    await restored.toggleFavorite(qq);
    expect(restored.isFavorite(first), isTrue);
    expect(restored.isFavorite(qq), isFalse);
    await restored.removeSearch('Avril');
    await restored.clearHistory();
    expect(restored.history, isEmpty);
    await restored.close();
  });
  test('并行写入有序，存储失败不伪装成功，下次写入可恢复', () async {
    final store = FailingStore();
    final library = LibraryController(store);
    await Future.wait([
      library.toggleFavorite(first),
      library.toggleFavorite(second),
      library.setTheme(AppThemePreference.dark),
    ]);
    expect(library.favorites.length, 2);
    store.fail = true;
    await library.setTheme(AppThemePreference.system);
    expect(library.themePreference, AppThemePreference.dark);
    expect(library.error, isNotNull);
    store.fail = false;
    await library.setTheme(AppThemePreference.light);
    expect(library.error, isNull);
    for (var i = 0; i < 35; i++) {
      await library.addSearch('query$i');
    }
    expect(library.history.length, 30);
    expect(library.history.first, 'query34');
    await library.close();
  });
  test('搜索请求记录历史，清空查询和切换平台不产生空记录', () async {
    final lib = LibraryController(MemoryStore());
    final repo = FakeRepository()
      ..onSearch = (_, _) async =>
          SearchPage(songs: [first], hasMore: false, total: 1);
    final search = SearchController(repo, library: lib);
    await search.search('歌手');
    await search.search('');
    expect(lib.history, ['歌手']);
    search.dispose();
    await lib.close();
    repo.api.close();
  });
  test('顺序自动衔接，最后停止；单曲循环自动重播，手动下一首仍切歌', () async {
    final audio = FakeAudio();
    final player = PlayerController(FakeRepository(), audio);
    void complete() => audio.eventController.add(
      const AudioEvent(
        playing: true,
        loading: false,
        completed: true,
        position: Duration(seconds: 10),
        duration: Duration(seconds: 10),
      ),
    );
    await player.playQueue([first, second]);
    complete();
    await tick();
    expect(player.currentSong?.key, second.key);
    complete();
    await tick();
    expect(player.currentSong?.key, second.key);
    expect(player.isPlaying, isFalse);
    await player.setMode(PlaybackMode.repeatOne);
    await player.playQueue([first, second]);
    final before = audio.playCount;
    complete();
    await tick();
    expect(player.currentSong?.key, first.key);
    expect(audio.playCount, before + 1);
    await player.next();
    expect(player.currentSong?.key, second.key);
    await player.setMode(PlaybackMode.repeatAll);
    complete();
    await tick();
    expect(player.currentSong?.key, first.key);
    await player.close();
  });
  test('随机一轮不重复，上一首回退到实际播放过的曲目', () async {
    final player = PlayerController(
      FakeRepository(),
      FakeAudio(),
      random: Random(8),
    );
    await player.setMode(PlaybackMode.shuffle);
    await player.playQueue([first, second, third]);
    final played = [player.currentSong!.key];
    await player.next();
    played.add(player.currentSong!.key);
    await player.next();
    played.add(player.currentSong!.key);
    expect(played.toSet().length, 3);
    await player.previous();
    expect(player.currentSong?.key, played[1]);
    await player.close();
  });
  test('队列去重遵循平台主键，并且自动优先离线文件', () async {
    final dir = await Directory.systemTemp.createTemp('suishiting_queue');
    final file = File('${dir.path}/song.mp3');
    await file.writeAsBytes([73, 68, 51, 0]);
    final repo = FakeRepository()
      ..onSource = (_) async => throw const MusicException('offline');
    final audio = FakeAudio();
    final player = PlayerController(
      repo,
      audio,
      localPathFor: (_) => file.path,
    );
    await player.playQueue([first, first, qq]);
    expect(player.queue.length, 2);
    expect(player.source?.level, 'local');
    await player.next();
    expect(player.currentSong?.platform, MusicPlatform.qq);
    expect(audio.loaded.last.scheme, 'file');
    await player.close();
    await dir.delete(recursive: true);
  });
}
