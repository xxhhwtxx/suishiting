import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'song_cover.dart';

/// 底部常驻迷你播放控制栏。
/// 监听 [PlayerController]、[DownloadController] 与 [Music163Core]，
/// 显著展示曲目所属平台、试听标识、真实音源规格、播放错误重试与进度。
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.core,
    this.onOpenQueueOrDownloads,
  });

  final Music163Core core;
  final VoidCallback? onOpenQueueOrDownloads;

  void _openNowPlayingSheet(BuildContext context) {
    if (core.player.currentSong == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => NowPlayingSheet(
        core: core,
        onOpenDownloads: onOpenQueueOrDownloads,
      ),
    );
  }

  Future<void> _togglePlay(PlayerController player, Song song) async {
    if (player.isPlaying) {
      await player.pause();
    } else if (player.source != null && player.error == null) {
      await player.resume();
    } else {
      await player.play(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([core, core.player, core.downloads]),
      builder: (context, _) {
        final player = core.player;
        final song = player.currentSong;
        if (song == null && player.error == null) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final source = player.source;
        final isTrial = source?.isTrial ?? false;

        final totalMs = player.duration.inMilliseconds;
        final posMs = player.position.inMilliseconds;
        final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

        return Material(
          color: colorScheme.surfaceContainerHigh,
          elevation: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (player.isLoading)
                const LinearProgressIndicator(minHeight: 2.5)
              else
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2.5,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTrial
                        ? (isDark
                              ? AppTheme.trialAmberDark
                              : AppTheme.trialAmberLight)
                        : colorScheme.primary,
                  ),
                ),
              if (isTrial)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  color: isDark
                      ? AppTheme.trialSurfaceDark
                      : AppTheme.trialSurfaceLight,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: isDark
                            ? AppTheme.trialAmberDark
                            : AppTheme.trialAmberLight,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '试听片段 · 当前账号或曲目权限仅返回试听音源，非完整歌曲',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (player.error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  color: colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          player.error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (song != null)
                        TextButton(
                          onPressed: () => player.play(song),
                          child: Text(
                            '重试播放',
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (song != null)
                InkWell(
                  key: const Key('mini_player_tap_area'),
                  onTap: () => _openNowPlayingSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SongCover(
                          artworkUrl: song.artworkUrl,
                          size: 46,
                          borderRadius: 10,
                          isPlaying: player.isPlaying,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${song.artists} · ${UiFormatters.formatDuration(player.position)} / ${UiFormatters.formatDuration(player.duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _SmallBadge(
                                    label: song.platform.label,
                                    backgroundColor:
                                        colorScheme.tertiaryContainer,
                                    foregroundColor:
                                        colorScheme.onTertiaryContainer,
                                  ),
                                  if (source != null)
                                    _SmallBadge(
                                      label: UiFormatters.formatMediaSourceBadge(
                                        source,
                                      ),
                                      backgroundColor:
                                          colorScheme.secondaryContainer,
                                      foregroundColor:
                                          colorScheme.onSecondaryContainer,
                                    ),
                                  if (isTrial)
                                    _SmallBadge(
                                      label: '试听音源',
                                      backgroundColor: isDark
                                          ? AppTheme.trialSurfaceDark
                                          : AppTheme.trialSurfaceLight,
                                      foregroundColor: isDark
                                          ? AppTheme.trialAmberDark
                                          : AppTheme.trialAmberLight,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const Key('mini_player_play_pause_button'),
                          tooltip: player.isPlaying ? '暂停' : '播放',
                          onPressed: player.isLoading
                              ? null
                              : () => _togglePlay(player, song),
                          icon: player.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : Icon(
                                  player.isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 32,
                                  color: colorScheme.primary,
                                ),
                        ),
                        IconButton(
                          key: const Key('mini_player_expand_button'),
                          tooltip: '展开播放详情与歌词',
                          onPressed: () => _openNowPlayingSheet(context),
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        IconButton(
                          key: const Key('mini_player_stop_button'),
                          tooltip: '停止播放',
                          onPressed: player.stop,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 完整播放控制与 LRC 歌词抽屉。
class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({
    super.key,
    required this.core,
    this.onOpenDownloads,
  });

  final Music163Core core;
  final VoidCallback? onOpenDownloads;

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  double? _dragPositionMs;
  String? _lyricsSongKey;
  bool _loadingLyrics = false;
  String? _lyricsError;
  String _rawLyrics = '';
  List<LrcLine> _parsedLyrics = const [];

  @override
  void initState() {
    super.initState();
    _syncLyricsIfNeeded();
  }

  void _syncLyricsIfNeeded() {
    final currentSong = widget.core.player.currentSong;
    if (currentSong == null) return;
    if (_lyricsSongKey == currentSong.key) return;
    _fetchLyrics(currentSong);
  }

  Future<void> _fetchLyrics(Song song) async {
    final targetKey = song.key;
    setState(() {
      _lyricsSongKey = targetKey;
      _loadingLyrics = true;
      _lyricsError = null;
      _rawLyrics = '';
      _parsedLyrics = const [];
    });
    try {
      final raw = await widget.core.repository.lyricsFor(song);
      if (!mounted || _lyricsSongKey != targetKey) return;
      setState(() {
        _rawLyrics = raw;
        _parsedLyrics = UiFormatters.parseLrc(raw);
        _loadingLyrics = false;
      });
    } catch (e) {
      if (!mounted || _lyricsSongKey != targetKey) return;
      setState(() {
        _lyricsError = e.toString();
        _loadingLyrics = false;
      });
    }
  }

  Future<void> _togglePlay(PlayerController player, Song song) async {
    if (player.isPlaying) {
      await player.pause();
    } else if (player.source != null && player.error == null) {
      await player.resume();
    } else {
      await player.play(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.player,
        widget.core.downloads,
      ]),
      builder: (context, _) {
        final player = widget.core.player;
        final song = player.currentSong;
        if (song == null) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('当前没有正在播放的歌曲'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          );
        }

        if (_lyricsSongKey != song.key && !_loadingLyrics) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncLyricsIfNeeded();
          });
        }

        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final source = player.source;
        final isTrial = source?.isTrial ?? false;

        final durationMs = player.duration.inMilliseconds;
        final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
        final currentMs = (_dragPositionMs ??
                player.position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);
        final displayPosition = Duration(milliseconds: currentMs.round());

        final downloadTask = widget.core.downloads.tasks
            .where((t) => t.id == song.key || t.song.key == song.key)
            .firstOrNull;

        final activeLyricIdx = UiFormatters.activeLyricIndex(
          _parsedLyrics,
          player.position,
        );

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _SmallBadge(
                            label: song.platform.label,
                            backgroundColor: colorScheme.tertiaryContainer,
                            foregroundColor: colorScheme.onTertiaryContainer,
                          ),
                          _SmallBadge(
                            label: 'ID: ${song.displayId}',
                            backgroundColor: colorScheme.surfaceContainerHigh,
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                          _SmallBadge(
                            label: '优先请求: ${widget.core.quality.label}',
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                          ),
                          if (source != null)
                            _SmallBadge(
                              label:
                                  '实际音源: ${UiFormatters.formatMediaSourceBadge(source)}',
                              backgroundColor: colorScheme.secondaryContainer,
                              foregroundColor: colorScheme.onSecondaryContainer,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '收起播放页',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isTrial)
                  Container(
                    key: const Key('now_playing_trial_banner'),
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.trialSurfaceDark
                          : AppTheme.trialSurfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: isDark
                              ? AppTheme.trialAmberDark
                              : AppTheme.trialAmberLight,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '试听音源提示：当前歌曲受${song.platform.label}接口或当前账号权限限制，仅返回试听片段（非完整歌曲），下载功能不会将试听片段保存为完整歌曲。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.trialAmberDark
                                  : AppTheme.trialAmberLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (player.error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            player.error!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => player.play(song),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SongCover(
                      artworkUrl: song.artworkUrl,
                      size: 88,
                      borderRadius: 18,
                      isPlaying: player.isPlaying,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song.artists.isEmpty ? '未知歌手' : song.artists,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                          if (song.album.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '专辑：${song.album}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    Slider(
                      key: const Key('now_playing_seek_slider'),
                      value: currentMs,
                      min: 0,
                      max: maxMs,
                      onChanged: source == null || durationMs <= 0
                          ? null
                          : (value) {
                              setState(() {
                                _dragPositionMs = value;
                              });
                            },
                      onChangeEnd: source == null || durationMs <= 0
                          ? null
                          : (value) async {
                              setState(() {
                                _dragPositionMs = null;
                              });
                              await player.seek(
                                Duration(milliseconds: value.round()),
                              );
                            },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            UiFormatters.formatDuration(displayPosition),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            UiFormatters.formatDuration(player.duration),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    IconButton.filledTonal(
                      tooltip: '快退 10 秒',
                      onPressed: source == null
                          ? null
                          : () => player.seek(
                              player.position - const Duration(seconds: 10),
                            ),
                      icon: const Icon(Icons.replay_10_rounded),
                    ),
                    FilledButton.icon(
                      key: const Key('now_playing_play_pause_button'),
                      onPressed: player.isLoading
                          ? null
                          : () => _togglePlay(player, song),
                      icon: player.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                      label: Text(
                        player.isLoading
                            ? '解析加载中…'
                            : (player.isPlaying ? '暂停播放' : '开始播放'),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '快进 10 秒',
                      onPressed: source == null
                          ? null
                          : () => player.seek(
                              player.position + const Duration(seconds: 10),
                            ),
                      icon: const Icon(Icons.forward_10_rounded),
                    ),
                    IconButton.outlined(
                      tooltip: '停止并清空当前播放',
                      onPressed: () async {
                        await player.stop();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('now_playing_download_button'),
                        onPressed: isTrial
                            ? null
                            : () async {
                                if (downloadTask != null &&
                                    (downloadTask.state ==
                                            DownloadState.failed ||
                                        downloadTask.state ==
                                            DownloadState.cancelled)) {
                                  await widget.core.downloads.retry(
                                    downloadTask.id,
                                  );
                                } else if (downloadTask == null) {
                                  await widget.core.downloads.enqueue(song);
                                } else if (widget.onOpenDownloads != null) {
                                  Navigator.of(context).pop();
                                  widget.onOpenDownloads!();
                                }
                              },
                        icon: Icon(
                          switch (downloadTask?.state) {
                            DownloadState.completed =>
                              Icons.download_done_rounded,
                            DownloadState.queued ||
                            DownloadState.resolving ||
                            DownloadState.downloading =>
                              Icons.downloading_rounded,
                            DownloadState.failed ||
                            DownloadState.cancelled =>
                              Icons.refresh_rounded,
                            null => Icons.download_rounded,
                          },
                        ),
                        label: Text(
                          isTrial
                              ? '试听音源不可下载完整版'
                              : switch (downloadTask?.state) {
                                  DownloadState.completed => '已下载（点击查看任务）',
                                  DownloadState.queued ||
                                  DownloadState.resolving ||
                                  DownloadState.downloading =>
                                    '下载进行中（${UiFormatters.downloadStateLabel(downloadTask!.state)}）',
                                  DownloadState.failed ||
                                  DownloadState.cancelled =>
                                    '重新下载此曲',
                                  null => '加入本地下载任务',
                                },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lyrics_outlined,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '同步歌词 (LRC)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _loadingLyrics
                                ? null
                                : () => _fetchLyrics(song),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('刷新歌词'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_loadingLyrics)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_lyricsError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '歌词获取失败：$_lyricsError',
                                style: TextStyle(color: colorScheme.error),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => _fetchLyrics(song),
                                child: const Text('重试加载歌词'),
                              ),
                            ],
                          ),
                        )
                      else if (_parsedLyrics.isEmpty &&
                          _rawLyrics.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            '纯音乐或暂无歌词数据',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _parsedLyrics.length; i++)
                              _LyricRow(
                                line: _parsedLyrics[i],
                                isActive: i == activeLyricIdx,
                                onTap: _parsedLyrics[i].timestamp == null ||
                                        source == null
                                    ? null
                                    : () => player.seek(
                                        _parsedLyrics[i].timestamp!,
                                      ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '说明：基础版播放器为前台播放，暂不承诺系统级后台常驻播放服务；音源可用性与音质由对应平台接口及当前登录账号权限决定。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.line,
    required this.isActive,
    this.onTap,
  });

  final LrcLine line;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (line.timestamp != null) ...[
              Text(
                UiFormatters.formatDuration(line.timestamp!),
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                line.text,
                style: TextStyle(
                  fontSize: isActive ? 15 : 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}
