import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/song_cover.dart';

/// 本机收藏歌曲页：展示 [LibraryController.favorites]，
/// 支持一键队列播放全部、单曲点播、取消收藏及加入下载。
class FavoritesPageView extends StatelessWidget {
  const FavoritesPageView({
    super.key,
    required this.core,
    required this.onNavigateToSearch,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final VoidCallback onNavigateToSearch;
  final VoidCallback onNavigateToDownloads;

  Future<void> _handlePlayTap(List<Song> favorites, int index) async {
    final song = favorites[index];
    final player = core.player;
    final isCurrent = player.currentSong?.key == song.key;
    if (isCurrent && player.isPlaying) {
      await player.pause();
    } else if (isCurrent && player.source != null && player.error == null) {
      await player.resume();
    } else {
      await player.playQueue(favorites, startIndex: index);
    }
  }

  Future<void> _handleDownloadTap(
    BuildContext context,
    Song song,
    DownloadTask? existingTask,
  ) async {
    final downloads = core.downloads;
    if (existingTask == null) {
      await downloads.enqueue(song);
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入下载任务',
        action: SnackBarAction(label: '查看下载', onPressed: onNavigateToDownloads),
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

    onNavigateToDownloads();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        core,
        core.library,
        core.player,
        core.downloads,
      ]),
      builder: (context, _) {
        final favorites = core.library.favorites;
        final colorScheme = Theme.of(context).colorScheme;

        final taskMap = <String, DownloadTask>{
          for (final task in core.downloads.tasks) task.song.key: task,
          for (final task in core.downloads.tasks) task.id: task,
        };

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本机收藏 (${favorites.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '仅保存在本机，不同步至云端平台',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (favorites.isNotEmpty)
                    FilledButton.tonalIcon(
                      key: const Key('favorites_play_all_button'),
                      onPressed: () {
                        unawaited(
                          core.player.playQueue(favorites, startIndex: 0),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('播放全部'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: favorites.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.favorite_border_rounded,
                                  size: 32,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '暂无本机收藏歌曲',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '在推荐、搜索或播放器点击爱心图标即可收藏常听歌曲。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                key: const Key('favorites_go_search_button'),
                                onPressed: onNavigateToSearch,
                                icon: const Icon(Icons.search_rounded),
                                label: const Text('前往搜索歌曲'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('favorites_list'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                      itemCount: favorites.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final song = favorites[index];
                        final isCurrent =
                            core.player.currentSong?.key == song.key;
                        final isPlaying = isCurrent && core.player.isPlaying;
                        final isLoading = isCurrent && core.player.isLoading;
                        final downloadTask = taskMap[song.key];

                        final subtitleParts = <String>[
                          if (song.artists.isNotEmpty) song.artists,
                          if (song.album.isNotEmpty) song.album,
                        ];

                        return Material(
                          color: isCurrent
                              ? colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                )
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: Key('favorite_song_item_${song.key}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _handlePlayTap(favorites, index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrent
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.6,
                                        )
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.45,
                                        ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SongCover(
                                    artworkUrl: song.artworkUrl,
                                    size: 50,
                                    borderRadius: 12,
                                    isPlaying: isPlaying,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: isCurrent
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
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    song.platform ==
                                                        MusicPlatform.qq
                                                    ? colorScheme
                                                          .tertiaryContainer
                                                    : colorScheme
                                                          .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                song.platform.label,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      song.platform ==
                                                          MusicPlatform.qq
                                                      ? colorScheme
                                                            .onTertiaryContainer
                                                      : colorScheme
                                                            .onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                            if (song.duration > Duration.zero)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .surfaceContainerHigh,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  UiFormatters.formatDuration(
                                                    song.duration,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: Key('favorite_play_btn_${song.key}'),
                                    tooltip: isPlaying ? '暂停' : '播放',
                                    onPressed: isLoading
                                        ? null
                                        : () =>
                                              _handlePlayTap(favorites, index),
                                    icon: isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying
                                                ? Icons
                                                      .pause_circle_filled_rounded
                                                : Icons
                                                      .play_circle_outline_rounded,
                                            color: isCurrent
                                                ? colorScheme.primary
                                                : colorScheme.onSurface,
                                            size: 26,
                                          ),
                                  ),
                                  IconButton(
                                    key: Key(
                                      'favorite_download_btn_${song.key}',
                                    ),
                                    tooltip: '下载歌曲',
                                    onPressed: () => _handleDownloadTap(
                                      context,
                                      song,
                                      downloadTask,
                                    ),
                                    icon: Icon(
                                      downloadTask?.state ==
                                              DownloadState.completed
                                          ? Icons.download_done_rounded
                                          : Icons.download_for_offline_outlined,
                                      size: 22,
                                      color:
                                          downloadTask?.state ==
                                              DownloadState.completed
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  IconButton(
                                    key: Key('favorite_remove_btn_${song.key}'),
                                    tooltip: '取消收藏',
                                    onPressed: () {
                                      unawaited(
                                        core.library.toggleFavorite(song),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.favorite_rounded,
                                      color: colorScheme.error,
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
