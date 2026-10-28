import 'package:flutter/foundation.dart';

enum MusicPlatform {
  netease('网易云音乐'),
  qq('QQ 音乐');

  const MusicPlatform(this.label);
  final String label;
}

enum AudioQuality {
  standard('标准', 'standard'),
  higher('较高', 'higher'),
  lossless('无损', 'lossless'),
  hires('Hi-Res', 'hires');

  const AudioQuality(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    this.artworkUrl,
    this.duration = Duration.zero,
    this.platform = MusicPlatform.netease,
    this.mid,
    this.mediaMid,
    this.songType = 0,
  });
  final int id;
  final String name;
  final String artists;
  final String album;
  final String? artworkUrl;
  final Duration duration;
  final MusicPlatform platform;
  final String? mid;
  final String? mediaMid;
  final int songType;
  String get key => platform == MusicPlatform.qq ? 'qq_${mid ?? id}' : '$id';
  String get displayId => mid ?? '$id';

  factory Song.fromJson(Map<String, dynamic> json) {
    final album = (json['al'] ?? json['album']) as Map<String, dynamic>? ?? {};
    final artists = (json['ar'] ?? json['artists']) as List<dynamic>? ?? [];
    return Song(
      id: (json['id'] as num).toInt(),
      platform: json['platform'] == 'qq'
          ? MusicPlatform.qq
          : MusicPlatform.netease,
      mid: json['mid'] as String?,
      mediaMid: json['mediaMid'] as String?,
      songType: (json['songType'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '未命名歌曲',
      artists: artists
          .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .join(' / '),
      album: album['name'] as String? ?? '',
      artworkUrl: album['picUrl'] as String?,
      duration: Duration(
        milliseconds: ((json['dt'] ?? json['duration']) as num? ?? 0).toInt(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.name,
    'mid': mid,
    'mediaMid': mediaMid,
    'songType': songType,
    'name': name,
    'ar': [
      {'name': artists},
    ],
    'al': {'name': album, 'picUrl': artworkUrl},
    'dt': duration.inMilliseconds,
  };
}

@immutable
class SearchPage {
  SearchPage({
    required List<Song> songs,
    required this.hasMore,
    required this.total,
    this.nextOffset,
  }) : songs = List.unmodifiable(songs);
  final List<Song> songs;
  final bool hasMore;
  final int total;
  final int? nextOffset;
}

@immutable
class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
  });
  final int id;
  final String nickname;
  final String? avatarUrl;
}

enum QrStatus {
  idle,
  waiting,
  scanned,
  authorizing,
  success,
  expired,
  failed,
  refused,
}

@immutable
class QrSession {
  const QrSession({
    required this.key,
    required this.loginUrl,
    required this.expiresAt,
  });
  final String key;
  final String loginUrl;
  final DateTime expiresAt;
}

@immutable
class MediaSource {
  const MediaSource({
    required this.url,
    required this.extension,
    required this.level,
    required this.bitrate,
    required this.isTrial,
  });
  final Uri url;
  final String extension;
  final String level;
  final int bitrate;
  final bool isTrial;
}

enum DownloadState {
  queued,
  resolving,
  downloading,
  completed,
  failed,
  cancelled,
}

@immutable
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.song,
    this.state = DownloadState.queued,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.path,
    this.error,
  });
  final String id;
  final Song song;
  final DownloadState state;
  final int downloadedBytes;
  final int? totalBytes;
  final String? path;
  final String? error;
  double? get progress => totalBytes != null && totalBytes! > 0
      ? (downloadedBytes / totalBytes!).clamp(0, 1)
      : null;
  bool get isActive =>
      state == DownloadState.queued ||
      state == DownloadState.resolving ||
      state == DownloadState.downloading;

  DownloadTask copyWith({
    DownloadState? state,
    int? downloadedBytes,
    int? totalBytes,
    String? path,
    String? error,
    bool clearError = false,
  }) => DownloadTask(
    id: id,
    song: song,
    state: state ?? this.state,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    path: path ?? this.path,
    error: clearError ? null : error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'song': song.toJson(),
    'state': state.name,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'path': path,
    'error': error,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    song: Song.fromJson(json['song'] as Map<String, dynamic>),
    state: DownloadState.values.byName(json['state'] as String),
    downloadedBytes: (json['downloadedBytes'] as num? ?? 0).toInt(),
    totalBytes: (json['totalBytes'] as num?)?.toInt(),
    path: json['path'] as String?,
    error: json['error'] as String?,
  );
}

class MusicException implements Exception {
  const MusicException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}
