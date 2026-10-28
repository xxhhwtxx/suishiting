import '../domain/models.dart';
import 'netease_api.dart';
import 'qq_api.dart';

class MusicRepository {
  MusicRepository(this.api, {this.qqApi});
  final NeteaseApi api;
  final QqApi? qqApi;
  AudioQuality quality = AudioQuality.higher;

  QqApi get _qq => qqApi ?? (throw const MusicException('QQ 音乐未初始化。'));
  Future<SearchPage> searchFor(
    MusicPlatform platform,
    String query, {
    int offset = 0,
    int limit = 20,
  }) => platform == MusicPlatform.qq
      ? _qq.search(query, offset: offset, limit: limit)
      : search(query, offset: offset, limit: limit);

  Future<Song?> resolveSong(MusicPlatform platform, String input) async {
    if (platform == MusicPlatform.netease) {
      final id = await resolveInput(input);
      return id == null ? null : song(id);
    }
    final direct = RegExp(r'^(?:\d+|[0-9A-Za-z]{14})$').hasMatch(input)
        ? input
        : null;
    if (direct != null) return _qq.song(direct);
    final match = RegExp(r'https?://[^\s<>"“”]+').firstMatch(input);
    if (match == null) return null;
    final uri = Uri.tryParse(match[0]!);
    if (uri == null || !['y.qq.com', 'i.y.qq.com'].contains(uri.host)) {
      throw const MusicException('请粘贴 QQ 音乐歌曲链接，或输入歌名搜索。');
    }
    final mid =
        uri.queryParameters['songmid'] ??
        RegExp(r'/songDetail/([a-zA-Z0-9]+)').firstMatch(uri.path)?[1] ??
        RegExp(r'/song/([a-zA-Z0-9]+)(?:\.html)?').firstMatch(uri.path)?[1];
    final value = mid ?? uri.queryParameters['songid'];
    if (value == null || !RegExp(r'^[a-zA-Z0-9]{1,64}$').hasMatch(value)) {
      throw const MusicException('请复制 QQ 音乐的歌曲链接，或输入歌曲 MID、ID 或歌名。');
    }
    return _qq.song(value);
  }

  Future<MediaSource> playbackFor(Song song) =>
      song.platform == MusicPlatform.qq
      ? _qq.source(song, quality)
      : playbackSource(song.id);
  Future<MediaSource> downloadFor(Song song) =>
      song.platform == MusicPlatform.qq
      ? _qq.source(song, quality, download: true)
      : downloadSource(song.id);
  Future<String> lyricsFor(Song song) =>
      song.platform == MusicPlatform.qq ? _qq.lyrics(song) : lyrics(song.id);

  Future<SearchPage> search(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    final reply = await api.request('/api/v1/search/song/get', {
      's': query,
      'offset': offset,
      'limit': limit,
    });
    final result = reply.json['result'] as Map<String, dynamic>? ?? {};
    final songs = ((result['songs'] as List<dynamic>?) ?? [])
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
    final total = (result['songCount'] as num? ?? songs.length).toInt();
    return SearchPage(
      songs: songs,
      total: total,
      hasMore:
          songs.isNotEmpty &&
          (result['hasMore'] as bool? ?? offset + songs.length < total),
    );
  }

  Future<Song> song(int id) async {
    final response = await api.request('/api/v3/song/detail', {
      'c': '[{"id":$id}]',
    });
    final songs = response.json['songs'] as List<dynamic>? ?? [];
    if (songs.isEmpty) throw const MusicException('找不到这首歌曲，请检查 ID 或链接。');
    return Song.fromJson(songs.first as Map<String, dynamic>);
  }

  Future<int?> resolveInput(String input) async {
    final id = songIdFromInput(input);
    if (id != null) return id;
    final match = RegExp(r'https?://[^\s<>"“”]+').firstMatch(input);
    if (match == null) return null;
    final link = Uri.tryParse(match.group(0)!);
    if (link == null || !isMusicLink(link)) {
      throw const MusicException('请粘贴网易云歌曲链接，或输入歌名搜索。');
    }
    if (link.host == '163cn.tv' || link.host == '163cn.link') {
      final target = await api.resolveShortLink(link);
      final resolved = songIdFromInput(target.toString());
      if (resolved != null) return resolved;
    }
    throw const MusicException('暂时只支持歌曲链接，请复制歌曲分享链接或输入歌曲 ID。');
  }

  Future<MediaSource> playbackSource(int id) async {
    final response = await api.request('/api/song/enhance/player/url/v1', {
      'ids': '["$id"]',
      'level': quality.apiValue,
      'encodeType': 'mp3',
    });
    final list = response.json['data'] as List<dynamic>? ?? [];
    if (list.isEmpty) throw const MusicException('暂无可用音源。');
    return _source(list.first as Map<String, dynamic>);
  }

  Future<MediaSource> downloadSource(int id) async {
    final br = switch (quality) {
      AudioQuality.standard => 128000,
      AudioQuality.higher => 320000,
      AudioQuality.lossless || AudioQuality.hires => 999000,
    };
    final reply = await api.request('/api/song/enhance/download/url', {
      'id': id,
      'br': br,
    });
    final data = reply.json['data'] as Map<String, dynamic>?;
    if (data == null || data['url'] == null) {
      throw const MusicException('当前账号无法下载此歌曲，请登录并确认下载权限，或换一首。');
    }
    final source = _source(data);
    if (source.isTrial) throw const MusicException('此音源仅供试听，无法保存为完整歌曲。');
    return source;
  }

  MediaSource _source(Map<String, dynamic> data) {
    final raw = data['url'] as String?;
    final url = raw == null ? null : Uri.tryParse(raw);
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty) {
      throw const MusicException('此歌曲暂不可用，或当前账号没有对应权限。');
    }
    // CDN supports TLS; keep credentials off the CDN request entirely.
    final secureUrl = url.scheme == 'http' ? url.replace(scheme: 'https') : url;
    final extension = (data['type'] as String? ?? 'mp3').toLowerCase();
    return MediaSource(
      url: secureUrl,
      extension: {'mp3', 'flac', 'm4a', 'aac', 'ogg'}.contains(extension)
          ? extension
          : 'mp3',
      level: data['level'] as String? ?? '',
      bitrate: (data['br'] as num? ?? 0).toInt(),
      isTrial:
          data['freeTrialInfo'] != null ||
          data['freeTrialPrivilege'] is Map &&
              (data['freeTrialPrivilege'] as Map)['listenType'] == 1,
    );
  }

  Future<String> lyrics(int id) async {
    final reply = await api.request('/api/song/lyric', {
      'id': id,
      'lv': -1,
      'kv': -1,
      'tv': -1,
      'yv': -1,
    });
    return (reply.json['lrc'] as Map<String, dynamic>?)?['lyric'] as String? ??
        '';
  }
}
