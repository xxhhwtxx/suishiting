import 'package:flutter/foundation.dart';
import 'package:music163_core/music163_core.dart';

/// 界面展示格式化与 LRC 歌词解析工具（纯函数，无业务逻辑）。
abstract final class UiFormatters {
  /// 将时长格式化为 `mm:ss` 或 `hh:mm:ss`。
  static String formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '00:00';
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final hh = hours.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  /// 格式化字节数为人类可读单位（KB / MB）。
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  /// 格式化已下载字节与总字节进度。
  static String formatByteProgress(int downloadedBytes, int? totalBytes) {
    final downloaded = formatBytes(downloadedBytes);
    if (totalBytes == null || totalBytes <= 0) {
      return downloadedBytes > 0 ? '已接收 $downloaded' : '准备接收数据…';
    }
    final total = formatBytes(totalBytes);
    final percent = ((downloadedBytes / totalBytes).clamp(0.0, 1.0) * 100)
        .toStringAsFixed(0);
    return '$downloaded / $total ($percent%)';
  }

  /// 格式化音源编码与码率描述。
  static String formatMediaSourceBadge(MediaSource source) {
    final ext = source.extension.toUpperCase();
    final levelText = formatSourceLevel(source.level);
    final kbps = source.bitrate > 0
        ? '${(source.bitrate / 1000).round()}kbps'
        : '';
    final parts = <String>[
      if (levelText.isNotEmpty) levelText,
      ext,
      if (kbps.isNotEmpty) kbps,
    ];
    return parts.join(' · ');
  }

  /// 将网易云返回的音源 level 转换为中文可读标签。
  static String formatSourceLevel(String level) {
    return switch (level.trim().toLowerCase()) {
      'standard' => '标准音质',
      'higher' => '较高音质',
      'exhigh' => '极高音质',
      'lossless' => '无损 FLAC',
      'hires' => 'Hi-Res',
      'jyeffect' => '高清臻音',
      'sky' => '沉浸环绕声',
      'jymaster' => '超清母带',
      'local' => '本地文件',
      '' => '',
      _ => level.toUpperCase(),
    };
  }

  /// 各优先音质档位的详细说明。
  static String qualitySubtitle(AudioQuality quality) {
    return switch (quality) {
      AudioQuality.standard => '约 128kbps MP3 · 节省流量与存储空间',
      AudioQuality.higher => '约 320kbps MP3 · 兼顾细腻度与体积（推荐）',
      AudioQuality.lossless => 'FLAC 无损音频 · 需歌曲有源且账号具备对应权限',
      AudioQuality.hires => 'Hi-Res 高解析度无损 · 最高规格母带级音源请求',
    };
  }

  /// 下载任务状态中文说明。
  static String downloadStateLabel(DownloadState state) {
    return switch (state) {
      DownloadState.queued => '排队等待中',
      DownloadState.resolving => '正在解析音源',
      DownloadState.downloading => '正在下载',
      DownloadState.completed => '已完成',
      DownloadState.failed => '下载失败',
      DownloadState.cancelled => '已取消',
    };
  }

  /// 二维码登录状态中文说明（支持网易云音乐与 QQ 音乐）。
  static String qrStatusLabel(
    QrStatus status, {
    MusicPlatform platform = MusicPlatform.netease,
  }) {
    if (platform == MusicPlatform.qq) {
      return switch (status) {
        QrStatus.idle => '点击下方按钮获取 QQ 音乐登录二维码',
        QrStatus.waiting => '请使用手机 QQ（可用另一台设备）扫描二维码',
        QrStatus.scanned => '已扫码，请在手机 QQ 中点击「确认登录」',
        QrStatus.authorizing => 'QQ 已确认，正在完成 QQ 音乐登录授权…',
        QrStatus.success => 'QQ 扫码登录成功，已同步账号信息',
        QrStatus.expired => '二维码已过期，请点击重新获取',
        QrStatus.failed => 'QQ 音乐登录授权未完成，请查看错误提示并重新获取二维码',
        QrStatus.refused => '已在手机端取消或拒绝本次授权，请点击重新获取二维码',
      };
    }
    return switch (status) {
      QrStatus.idle => '点击下方按钮生成本地登录二维码',
      QrStatus.waiting => '请使用另一台设备上的网易云音乐 App 扫码',
      QrStatus.scanned => '已扫码，请在手机网易云音乐 App 中点击「确认登录」',
      QrStatus.authorizing => '已确认扫码，正在完成网易云音乐登录授权…',
      QrStatus.success => '扫码登录成功，已同步账号信息',
      QrStatus.expired => '二维码已过期，请点击重新生成',
      QrStatus.failed => '扫码登录失败，请点击重新生成二维码',
      QrStatus.refused => '已取消本次扫码授权，请点击重新生成二维码',
    };
  }

  /// 提取本地路径中的文件名。
  static String fileNameFromPath(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  /// 解析 LRC 歌词文本为按时间排序的歌词行列表。
  static List<LrcLine> parseLrc(String rawLrc) {
    if (rawLrc.trim().isEmpty) return const [];
    final lines = rawLrc.split(RegExp(r'\r?\n'));
    final timePattern = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final parsed = <LrcLine>[];

    for (final rawLine in lines) {
      final matches = timePattern.allMatches(rawLine).toList();
      if (matches.isEmpty) {
        final plain = rawLine.trim();
        if (plain.isNotEmpty && !plain.startsWith('[')) {
          parsed.add(LrcLine(timestamp: null, text: plain));
        }
        continue;
      }
      final text = rawLine.replaceAll(timePattern, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fractionRaw = match.group(3) ?? '0';
        final millis = switch (fractionRaw.length) {
          1 => (int.tryParse(fractionRaw) ?? 0) * 100,
          2 => (int.tryParse(fractionRaw) ?? 0) * 10,
          _ => int.tryParse(fractionRaw.padRight(3, '0').substring(0, 3)) ?? 0,
        };
        parsed.add(
          LrcLine(
            timestamp: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: millis,
            ),
            text: text,
          ),
        );
      }
    }

    parsed.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return -1;
      if (b.timestamp == null) return 1;
      return a.timestamp!.compareTo(b.timestamp!);
    });
    return parsed;
  }

  /// 计算当前播放位置对应的激活歌词行索引。
  static int activeLyricIndex(List<LrcLine> lines, Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final ts = lines[i].timestamp;
      if (ts == null) continue;
      if (ts <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

@immutable
class LrcLine {
  const LrcLine({required this.timestamp, required this.text});

  final Duration? timestamp;
  final String text;
}
