import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:music163_core/music163_core.dart';

import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/song_cover.dart';

/// 搜索与曲目解析页。
/// 支持网易云音乐与 QQ 音乐双平台切换、搜索历史、一键队列播放、收藏与下载。
class SearchPageView extends StatefulWidget {
  const SearchPageView({
    super.key,
    required this.core,
    required this.onNavigateToDownloads,
    required this.onNavigateToAccount,
  });

  final Music163Core core;
  final VoidCallback onNavigateToDownloads;
  final VoidCallback onNavigateToAccount;

  @override
  State<SearchPageView> createState() => _SearchPageViewState();
}

class _SearchPageViewState extends State<SearchPageView> {
  late final TextEditingController _inputController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: widget.core.search.query);
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitSearch([String? overrideQuery]) async {
    _focusNode.unfocus();
    final target = overrideQuery ?? _inputController.text;
    if (overrideQuery != null) {
      _inputController.value = TextEditingValue(
        text: overrideQuery,
        selection: TextSelection.collapsed(offset: overrideQuery.length),
      );
    }
    await widget.core.search.search(target);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _handlePlayTap(List<Song> songs, int index) async {
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
        widget.core.search,
        widget.core.library,
        widget.core.auth,
        widget.core.qqAuth,
        widget.core.player,
        widget.core.downloads,
      ]),
      builder: (context, _) {
        final search = widget.core.search;
        final auth = widget.core.auth;
        final qqAuth = widget.core.qqAuth;
        final isQq = search.platform == MusicPlatform.qq;
        final isCurrentPlatformLoggedIn = isQq
            ? qqAuth.isLoggedIn
            : auth.isLoggedIn;
        final currentPlatformAccountLabel = isQq
            ? (qqAuth.isLoggedIn
                  ? 'QQ 音乐已登录：${qqAuth.profile?.nickname ?? 'QQ 音乐用户'}'
                  : 'QQ 音乐未登录（点击设置）')
            : (auth.isLoggedIn
                  ? '已登录：${auth.profile?.nickname ?? '网易云用户'}'
                  : '匿名模式（点击登录账号）');
        final colorScheme = Theme.of(context).colorScheme;

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
                  _PlatformSwitchBar(
                    selected: search.platform,
                    onChanged: (platform) {
                      search.setPlatform(platform);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('search_input_field'),
                          controller: _inputController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitSearch(),
                          decoration: InputDecoration(
                            hintText: isQq
                                ? '搜索 QQ 音乐歌名、歌手、数字 ID、songmid 或链接'
                                : '搜索歌名、歌手、数字 ID 或网易云分享链接',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_inputController.text.isNotEmpty)
                                  IconButton(
                                    key: const Key('search_clear_button'),
                                    tooltip: '清空输入',
                                    onPressed: () {
                                      _inputController.clear();
                                      search.search('');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  ),
                                IconButton(
                                  key: const Key('search_paste_button'),
                                  tooltip: '粘贴剪贴板内容',
                                  onPressed: _pasteFromClipboard,
                                  icon: const Icon(Icons.content_paste_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        key: const Key('search_submit_button'),
                        onPressed: search.isLoading ? null : _submitSearch,
                        icon: search.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.travel_explore_rounded),
                        label: const Text('搜索'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        key: const Key('search_account_status_chip'),
                        avatar: Icon(
                          isCurrentPlatformLoggedIn
                              ? Icons.verified_user_rounded
                              : Icons.person_outline_rounded,
                          size: 16,
                          color: isCurrentPlatformLoggedIn
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        label: Text(currentPlatformAccountLabel),
                        onPressed: widget.onNavigateToAccount,
                      ),
                      ActionChip(
                        key: const Key('search_quality_status_chip'),
                        avatar: Icon(
                          Icons.high_quality_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        label: Text('优先音质：${widget.core.quality.label}'),
                        onPressed: widget.onNavigateToAccount,
                      ),
                      if (search.songs.isNotEmpty)
                        ActionChip(
                          key: const Key('search_play_all_button'),
                          avatar: Icon(
                            Icons.playlist_play_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          label: Text('播放全部 (${search.songs.length})'),
                          onPressed: () {
                            unawaited(
                              widget.core.player.playQueue(
                                search.songs,
                                startIndex: 0,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, search)),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SearchController search) {
    final colorScheme = Theme.of(context).colorScheme;
    final platformLabel = search.platform.label;

    if (search.isLoading && search.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在请求$platformLabel接口解析「${search.query}」…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (search.error != null && search.songs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
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
                      size: 44,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '检索未能完成',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      search.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('search_error_retry_button'),
                      onPressed: () => search.search(search.query),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试搜索'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (search.query.isEmpty && search.songs.isEmpty) {
      final history = widget.core.library.history;
      if (history.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 46,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
                const SizedBox(height: 10),
                Text(
                  '输入歌名、歌手、歌曲 ID 或分享链接即可搜索',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return SingleChildScrollView(
        key: const Key('search_history_section'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '搜索历史',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: const Key('search_history_clear_button'),
                  onPressed: widget.core.library.clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空历史'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in history)
                  InputChip(
                    key: Key('search_history_item_$item'),
                    label: Text(item),
                    onPressed: () => _submitSearch(item),
                    deleteIcon: Icon(
                      Icons.close_rounded,
                      key: Key('search_history_remove_$item'),
                      size: 16,
                    ),
                    onDeleted: () {
                      unawaited(widget.core.library.removeSearch(item));
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }

    if (search.songs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_off_rounded,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '未在$platformLabel找到与「${search.query}」相关的歌曲',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final taskMap = <String, DownloadTask>{
      for (final task in widget.core.downloads.tasks) task.song.key: task,
      for (final task in widget.core.downloads.tasks) task.id: task,
    };

    return ListView.separated(
      key: const Key('search_results_list'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: search.songs.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == search.songs.length) {
          return _buildPaginationFooter(context, search);
        }

        final song = search.songs[index];
        final player = widget.core.player;
        final isCurrentSong = player.currentSong?.key == song.key;
        final isPlayingThis = isCurrentSong && player.isPlaying;
        final isLoadingThis = isCurrentSong && player.isLoading;
        final isTrialThis = isCurrentSong && (player.source?.isTrial ?? false);
        final downloadTask = taskMap[song.key];
        final isFavorite = widget.core.library.isFavorite(song);

        return _SongResultCard(
          song: song,
          isCurrentSong: isCurrentSong,
          isPlaying: isPlayingThis,
          isLoading: isLoadingThis,
          isTrial: isTrialThis,
          isFavorite: isFavorite,
          downloadTask: downloadTask,
          onPlayTap: () => _handlePlayTap(search.songs, index),
          onFavoriteTap: () {
            unawaited(widget.core.library.toggleFavorite(song));
          },
          onDownloadTap: () => _handleDownloadTap(context, song, downloadTask),
        );
      },
    );
  }

  Widget _buildPaginationFooter(BuildContext context, SearchController search) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search.error != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      search.error!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (search.hasMore)
            OutlinedButton.icon(
              key: const Key('search_load_more_button'),
              onPressed: search.isLoadingMore ? null : search.loadMore,
              icon: search.isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                search.isLoadingMore
                    ? '正在加载更多曲目…'
                    : '加载更多结果（已显示 ${search.songs.length} 首）',
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '已加载全部 ${search.songs.length} 首曲目',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlatformSwitchBar extends StatelessWidget {
  const _PlatformSwitchBar({required this.selected, required this.onChanged});

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
                    key: Key('search_platform_${platform.name}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(platform),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 42),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                platform == MusicPlatform.qq
                                    ? Icons.queue_music_rounded
                                    : Icons.cloud_queue_rounded,
                                size: 18,
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

class _SongResultCard extends StatelessWidget {
  const _SongResultCard({
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
        key: Key('song_item_${song.key}'),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SongCover(
                artworkUrl: song.artworkUrl,
                size: 54,
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
                      maxLines: 2,
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
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MetaTag(
                          text: song.platform.label,
                          background: song.platform == MusicPlatform.qq
                              ? colorScheme.tertiaryContainer
                              : colorScheme.secondaryContainer,
                          foreground: song.platform == MusicPlatform.qq
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                        _MetaTag(
                          text: 'ID: ${song.displayId}',
                          background: colorScheme.surfaceContainerHigh,
                          foreground: colorScheme.onSurfaceVariant,
                        ),
                        if (song.duration > Duration.zero)
                          _MetaTag(
                            text: UiFormatters.formatDuration(song.duration),
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (isTrial)
                          _MetaTag(
                            text: '试听片段',
                            background: isDark
                                ? AppTheme.trialSurfaceDark
                                : AppTheme.trialSurfaceLight,
                            foreground: isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight,
                          ),
                        if (downloadTask != null)
                          _MetaTag(
                            text: UiFormatters.downloadStateLabel(
                              downloadTask!.state,
                            ),
                            background: switch (downloadTask!.state) {
                              DownloadState.completed =>
                                colorScheme.secondaryContainer,
                              DownloadState.failed =>
                                colorScheme.errorContainer,
                              _ => colorScheme.primaryContainer,
                            },
                            foreground: switch (downloadTask!.state) {
                              DownloadState.completed =>
                                colorScheme.onSecondaryContainer,
                              DownloadState.failed =>
                                colorScheme.onErrorContainer,
                              _ => colorScheme.onPrimaryContainer,
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: Key('song_favorite_btn_${song.key}'),
                tooltip: isFavorite ? '取消收藏' : '收藏歌曲',
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
                key: Key('song_play_btn_${song.key}'),
                tooltip: isPlaying ? '暂停' : '播放',
                onPressed: isLoading ? null : onPlayTap,
                icon: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_outline_rounded,
                        color: isCurrentSong
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        size: 28,
                      ),
              ),
              IconButton(
                key: Key('song_download_btn_${song.key}'),
                tooltip: switch (downloadTask?.state) {
                  DownloadState.completed => '已下载，查看下载任务',
                  DownloadState.queued ||
                  DownloadState.resolving ||
                  DownloadState.downloading => '正在下载，点击查看进度',
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({
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
