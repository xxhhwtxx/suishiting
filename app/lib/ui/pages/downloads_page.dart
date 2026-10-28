import 'dart:io';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/formatters.dart';
import '../widgets/song_cover.dart';

/// 下载任务页：展示应用私有目录中的下载队列、进度、错误原因，
/// 支持取消、重试、系统分享导出及带二次确认的删除。
class DownloadsPageView extends StatelessWidget {
  const DownloadsPageView({
    super.key,
    required this.core,
    required this.onNavigateToSearch,
    this.shareFile,
  });

  final Music163Core core;
  final VoidCallback onNavigateToSearch;
  final Future<void> Function(DownloadTask task)? shareFile;

  Future<void> _handleShare(BuildContext context, DownloadTask task) async {
    final path = task.path;
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到本地音频文件路径，请重新下载。')),
      );
      return;
    }

    try {
      if (shareFile != null) {
        await shareFile!(task);
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地音频文件不存在，可能已被清理，请重试下载。')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: '${task.song.name} - ${task.song.artists}',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('调用系统分享失败：$e')),
      );
    }
  }

  Future<void> _confirmRemove(BuildContext context, DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final hasFile =
            task.state == DownloadState.completed &&
            (task.path?.isNotEmpty ?? false);
        return AlertDialog(
          title: const Text('确认删除下载记录？'),
          content: Text(
            hasFile
                ? '将同时移除「${task.song.name}」的下载记录并删除本机私有目录中的音频文件（${UiFormatters.fileNameFromPath(task.path)}）。此操作不可恢复。'
                : '将从下载列表中移除「${task.song.name}」的任务记录。',
          ),
          actions: [
            TextButton(
              key: const Key('confirm_remove_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('保留'),
            ),
            FilledButton(
              key: const Key('confirm_remove_accept_button'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await core.downloads.remove(task.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([core.downloads, core.player]),
      builder: (context, _) {
        final downloads = core.downloads;
        final tasks = downloads.tasks;
        final colorScheme = Theme.of(context).colorScheme;

        final activeCount = tasks.where((t) => t.isActive).length;
        final completedCount = tasks
            .where((t) => t.state == DownloadState.completed)
            .length;
        final failedOrCancelledCount = tasks
            .where(
              (t) =>
                  t.state == DownloadState.failed ||
                  t.state == DownloadState.cancelled,
            )
            .length;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SummaryPill(
                        icon: Icons.downloading_rounded,
                        label: '进行中 $activeCount',
                        color: colorScheme.primaryContainer,
                        onColor: colorScheme.onPrimaryContainer,
                      ),
                      _SummaryPill(
                        icon: Icons.check_circle_outline_rounded,
                        label: '已完成 $completedCount',
                        color: colorScheme.secondaryContainer,
                        onColor: colorScheme.onSecondaryContainer,
                      ),
                      if (failedOrCancelledCount > 0)
                        _SummaryPill(
                          icon: Icons.error_outline_rounded,
                          label: '异常/已取消 $failedOrCancelledCount',
                          color: colorScheme.errorContainer,
                          onColor: colorScheme.onErrorContainer,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '存储说明：文件保存在应用私有目录，完成后可点击「分享导出」发送到外部应用；卸载应用将清理私有目录。试听音源不会保存为完整歌曲。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.38,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (downloads.error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('downloads_global_error_banner'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              downloads.error!,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.separated(
                      key: const Key('downloads_task_list'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _DownloadTaskCard(
                          task: task,
                          isPlaying:
                              core.player.currentSong?.key == task.song.key &&
                              core.player.isPlaying,
                          onCancel: () => downloads.cancel(task.id),
                          onRetry: () => downloads.retry(task.id),
                          onShare: () => _handleShare(context, task),
                          onPlay: () {
                            final path = task.path;
                            if (path != null && path.trim().isNotEmpty) {
                              core.player.playLocal(task.song, path);
                            } else {
                              core.player.play(task.song);
                            }
                          },
                          onRemove: () => _confirmRemove(context, task),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.download_for_offline_outlined,
                  size: 34,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '暂无下载任务',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '在搜索页检索歌曲后点击下载图标，即可将完整音源保存到本机私有目录并随时分享导出。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('downloads_go_search_button'),
                onPressed: onNavigateToSearch,
                icon: const Icon(Icons.search_rounded),
                label: const Text('前往搜索歌曲'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({
    required this.task,
    required this.isPlaying,
    required this.onCancel,
    required this.onRetry,
    required this.onShare,
    required this.onPlay,
    required this.onRemove,
  });

  final DownloadTask task;
  final bool isPlaying;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onShare;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final song = task.song;
    final fileName = UiFormatters.fileNameFromPath(task.path);

    final (badgeBg, badgeFg) = switch (task.state) {
      DownloadState.completed => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      DownloadState.failed => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      DownloadState.cancelled => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      _ => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
    };

    return Card(
      key: Key('download_task_card_${task.id}'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (song.artists.isNotEmpty) song.artists,
                          if (song.album.isNotEmpty) song.album,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: song.platform == MusicPlatform.qq
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              song.platform.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: song.platform == MusicPlatform.qq
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ID: ${song.displayId}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              UiFormatters.downloadStateLabel(task.state),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badgeFg,
                              ),
                            ),
                          ),
                          Text(
                            UiFormatters.formatByteProgress(
                              task.downloadedBytes,
                              task.totalBytes,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (task.isActive || task.state == DownloadState.completed) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: task.state == DownloadState.completed
                      ? 1.0
                      : task.progress,
                ),
              ),
            ],
            if (fileName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.audio_file_outlined,
                    size: 15,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '本地文件：$fileName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (task.isActive)
                  OutlinedButton.icon(
                    key: Key('download_cancel_btn_${task.id}'),
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('取消下载'),
                  ),
                if (task.state == DownloadState.failed ||
                    task.state == DownloadState.cancelled)
                  FilledButton.tonalIcon(
                    key: Key('download_retry_btn_${task.id}'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试下载'),
                  ),
                if (task.state == DownloadState.completed) ...[
                  OutlinedButton.icon(
                    key: Key('download_play_btn_${task.id}'),
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('播放曲目'),
                  ),
                  FilledButton.tonalIcon(
                    key: Key('download_share_btn_${task.id}'),
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('分享导出'),
                  ),
                ],
                TextButton.icon(
                  key: Key('download_remove_btn_${task.id}'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: onColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: onColor,
            ),
          ),
        ],
      ),
    );
  }
}
