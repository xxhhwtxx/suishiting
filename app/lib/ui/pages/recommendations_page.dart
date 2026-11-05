import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/song_cover.dart';

/// 双平台真实推荐页（调用 [RecommendationController]）。
/// 仅在页面首次出现或用户主动刷新/切换平台时请求接口，不在 [build] 中触发请求。
class RecommendationsPageView extends StatefulWidget {
  const RecommendationsPageView({
    super.key,
    required this.core,
    required this.isActive,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final bool isActive;
  final VoidCallback onNavigateToDownloads;

  @override
  State<RecommendationsPageView> createState() =>
      _RecommendationsPageViewState();
}

class _RecommendationsPageViewState extends State<RecommendationsPageView> {
  bool _hasRequestedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _requestInitialLoadIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant RecommendationsPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _requestInitialLoadIfNeeded();
    }
  }

  void _requestInitialLoadIfNeeded() {
    if (_hasRequestedInitialLoad) return;
    _hasRequestedInitialLoad = true;
    final rec = widget.core.recommendations;
    if (rec.songs.isEmpty && !rec.isLoading) {
      unawaited(rec.load());
    }
  }

  Future<void> _handleSongTap(List<Song> songs, int index) async {
    final song = songs[index];
    final player = widget.core.player;
    final isCurrent = player.currentSong?.key == song.key;
    if (isCurrent && player.isPlaying) {
      await player.pause();
    } else if (isCurrent && player.source != null && player.error == null) {
      await player.resume();
    } else {
      await player.playQueue(songs, startIndex: index);
    }
  }

  Future<void> _handleDownloadTap(
    BuildContext context,
    Song song,
    DownloadTask? existingTask,
  ) async {
    final downloads = widget.core.downloads;
    if (existingTask == null) {
      await downloads.enqueue(song);
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入下载任务',
        action: SnackBarAction(
          label: '查看下载',
          onPressed: widget.onNavigateToDownloads,
        ),
      );
      return;
    }

    if (existingTask.state == DownloadState.failed ||
        existingTask.state == DownloadState.cancelled) {
      await downloads.retry(existingTask.id);
      if (!context.mounted) return;
      AppSnackBar.show(context, message: '已重新开始下载「${song.name}」');
      return;
    }

    widget.onNavigateToDownloads();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.recommendations,
        widget.core.player,
        widget.core.downloads,
        widget.core.library,
      ]),
      builder: (context, _) {
        final rec = widget.core.recommendations;
        final colorScheme = Theme.of(context).colorScheme;
        final sourceText = rec.sourceLabel.trim().isNotEmpty
            ? rec.sourceLabel.trim()
            : '${rec.platform.label}推荐';

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RecommendPlatformBar(
                    selected: rec.platform,
                    onChanged: (platform) {
                      unawaited(rec.setPlatform(platform));
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        key: const Key('recommend_source_label'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 15,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                sourceText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (rec.songs.isNotEmpty)
                            FilledButton.tonalIcon(
                              key: const Key('recommend_play_all_button'),
                              onPressed: () {
                                unawaited(
                                  widget.core.player.playQueue(
                                    rec.songs,
                                    startIndex: 0,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text('播放全部 (${rec.songs.length})'),
                            ),
                          IconButton(
                            key: const Key('recommend_refresh_button'),
                            tooltip: '刷新推荐',
                            onPressed: rec.isLoading
                                ? null
                                : () => unawaited(rec.load(refresh: true)),
                            icon: rec.isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, rec)),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, RecommendationController rec) {
    final colorScheme = Theme.of(context).colorScheme;

    if (rec.isLoading && rec.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                '正在加载${rec.platform.label}推荐曲目…',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rec.error != null && rec.songs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              key: const Key('recommend_error_card'),
              elevation: 0,
              color: colorScheme.errorContainer.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 42,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '推荐加载未完成',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rec.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('recommend_retry_button'),
                      onPressed: () => unawaited(rec.load(refresh: true)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (rec.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.queue_music_rounded,
                size: 46,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text(
                '暂无推荐曲目',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('recommend_empty_retry_button'),
                onPressed: () => unawaited(rec.load(refresh: true)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新推荐'),
              ),
            ],
          ),
        ),
      );
    }

    final taskMap = <String, DownloadTask>{
      for (final task in widget.core.downloads.tasks) task.song.key: task,
      for (final task in widget.core.downloads.tasks) task.id: task,
    };

    return RefreshIndicator(
      onRefresh: () => rec.load(refresh: true),
      child: ListView.separated(
        key: const Key('recommend_songs_list'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        itemCount: rec.songs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final song = rec.songs[index];
          final player = widget.core.player;
          final isCurrent = player.currentSong?.key == song.key;
          final isPlaying = isCurrent && player.isPlaying;
          final isLoading = isCurrent && player.isLoading;
          final isTrial = isCurrent && (player.source?.isTrial ?? false);
          final downloadTask = taskMap[song.key];
          final isFav = widget.core.library.isFavorite(song);

          return _RecommendSongTile(
            song: song,
            isCurrentSong: isCurrent,
            isPlaying: isPlaying,
            isLoading: isLoading,
            isTrial: isTrial,
            isFavorite: isFav,
            downloadTask: downloadTask,
            onPlayTap: () => _handleSongTap(rec.songs, index),
            onFavoriteTap: () {
              unawaited(widget.core.library.toggleFavorite(song));
            },
            onDownloadTap: () =>
                _handleDownloadTap(context, song, downloadTask),
          );
        },
      ),
    );
  }
}

class _RecommendPlatformBar extends StatelessWidget {
  const _RecommendPlatformBar({
    required this.selected,
    required this.onChanged,
  });

  final MusicPlatform selected;
  final ValueChanged<MusicPlatform> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          for (final platform in MusicPlatform.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: selected == platform
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: Key('recommend_platform_${platform.name}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(platform),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                platform == MusicPlatform.qq
                                    ? Icons.queue_music_rounded
                                    : Icons.cloud_queue_rounded,
                                size: 17,
                                color: selected == platform
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  platform.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected == platform
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: selected == platform
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendSongTile extends StatelessWidget {
  const _RecommendSongTile({
    required this.song,
    required this.isCurrentSong,
    required this.isPlaying,
    required this.isLoading,
    required this.isTrial,
    required this.isFavorite,
    required this.downloadTask,
    required this.onPlayTap,
    required this.onFavoriteTap,
    required this.onDownloadTap,
  });

  final Song song;
  final bool isCurrentSong;
  final bool isPlaying;
  final bool isLoading;
  final bool isTrial;
  final bool isFavorite;
  final DownloadTask? downloadTask;
  final VoidCallback onPlayTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onDownloadTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleParts = <String>[
      if (song.artists.isNotEmpty) song.artists,
      if (song.album.isNotEmpty) song.album,
    ];

    return Material(
      color: isCurrentSong
          ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.32 : 0.45)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('recommend_song_item_${song.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onPlayTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrentSong
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              SongCover(
                artworkUrl: song.artworkUrl,
                size: 52,
                borderRadius: 12,
                isPlaying: isPlaying,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCurrentSong
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.isEmpty
                          ? '未知艺人'
                          : subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MiniChip(
                          text: song.platform.label,
                          background: song.platform == MusicPlatform.qq
                              ? colorScheme.tertiaryContainer
                              : colorScheme.secondaryContainer,
                          foreground: song.platform == MusicPlatform.qq
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                        if (song.duration > Duration.zero)
                          _MiniChip(
                            text: UiFormatters.formatDuration(song.duration),
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (isTrial)
                          _MiniChip(
                            text: '试听片段',
                            background: isDark
                                ? AppTheme.trialSurfaceDark
                                : AppTheme.trialSurfaceLight,
                            foreground: isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('recommend_favorite_btn_${song.key}'),
                tooltip: isFavorite ? '取消本机收藏' : '加入本机收藏',
                onPressed: onFavoriteTap,
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              IconButton(
                key: Key('recommend_play_btn_${song.key}'),
                tooltip: isPlaying ? '暂停' : '播放',
                onPressed: isLoading ? null : onPlayTap,
                icon: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_outline_rounded,
                        color: isCurrentSong
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        size: 26,
                      ),
              ),
              IconButton(
                key: Key('recommend_download_btn_${song.key}'),
                tooltip: switch (downloadTask?.state) {
                  DownloadState.completed => '已下载，查看下载任务',
                  DownloadState.queued ||
                  DownloadState.resolving ||
                  DownloadState.downloading => '正在下载，查看进度',
                  DownloadState.failed || DownloadState.cancelled => '重试下载',
                  null => '下载歌曲',
                },
                onPressed: onDownloadTap,
                icon: Icon(
                  switch (downloadTask?.state) {
                    DownloadState.completed => Icons.download_done_rounded,
                    DownloadState.queued ||
                    DownloadState.resolving ||
                    DownloadState.downloading => Icons.downloading_rounded,
                    DownloadState.failed ||
                    DownloadState.cancelled => Icons.refresh_rounded,
                    null => Icons.download_for_offline_outlined,
                  },
                  color: switch (downloadTask?.state) {
                    DownloadState.completed => colorScheme.primary,
                    DownloadState.failed => colorScheme.error,
                    _ => colorScheme.onSurfaceVariant,
                  },
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
