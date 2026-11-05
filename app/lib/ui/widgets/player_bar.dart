import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:music163_core/music163_core.dart';

import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import 'song_cover.dart';

/// 底部常驻迷你播放控制栏。
/// 点击曲目区域打开参考 YouTube Music 大专辑图与简洁控制布局的完整播放界面。
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
      builder: (sheetContext) =>
          NowPlayingSheet(core: core, onOpenDownloads: onOpenQueueOrDownloads),
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
      listenable: Listenable.merge([
        core,
        core.player,
        core.downloads,
        core.library,
      ]),
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
                                      label:
                                          UiFormatters.formatMediaSourceBadge(
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
                        if (player.queue.length > 1)
                          IconButton(
                            key: const Key('mini_player_next_button'),
                            tooltip: '下一首',
                            onPressed: player.next,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        IconButton(
                          key: const Key('mini_player_expand_button'),
                          tooltip: '展开完整播放页',
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

/// 完整播放控制与同步 LRC 歌词界面（大专辑图、清晰歌名与简洁控制）。
class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key, required this.core, this.onOpenDownloads});

  final Music163Core core;
  final VoidCallback? onOpenDownloads;

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  final ScrollController _lyricsScrollController = ScrollController();
  double? _dragPositionMs;
  String? _lyricsSongKey;
  bool _loadingLyrics = false;
  String? _lyricsError;
  String _rawLyrics = '';
  List<LrcLine> _parsedLyrics = const [];
  List<GlobalKey> _lyricKeys = const [];
  int _lastScrolledLyricIdx = -1;

  @override
  void initState() {
    super.initState();
    widget.core.player.addListener(_onPlayerChanged);
    _syncLyricsIfNeeded();
  }

  @override
  void dispose() {
    widget.core.player.removeListener(_onPlayerChanged);
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final currentSong = widget.core.player.currentSong;
    if (currentSong != null && _lyricsSongKey != currentSong.key) {
      _fetchLyrics(currentSong);
    }
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
      _lyricKeys = const [];
      _lastScrolledLyricIdx = -1;
    });
    try {
      final raw = await widget.core.repository.lyricsFor(song);
      if (!mounted || _lyricsSongKey != targetKey) return;
      final parsed = UiFormatters.parseLrc(raw);
      setState(() {
        _rawLyrics = raw;
        _parsedLyrics = parsed;
        _lyricKeys = List.generate(parsed.length, (_) => GlobalKey());
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

  void _scrollToActiveLyricIfNeeded(int activeIdx) {
    if (activeIdx < 0 ||
        activeIdx >= _lyricKeys.length ||
        activeIdx == _lastScrolledLyricIdx) {
      return;
    }
    _lastScrolledLyricIdx = activeIdx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_lyricsScrollController.hasClients ||
          activeIdx >= _lyricKeys.length) {
        return;
      }
      final targetContext = _lyricKeys[activeIdx].currentContext;
      if (targetContext == null) return;
      final renderObject = targetContext.findRenderObject();
      if (renderObject == null) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      _lyricsScrollController.position.ensureVisible(
        renderObject,
        alignment: 0.35,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copyFullLyrics(BuildContext context) async {
    final plain = UiFormatters.plainLyricsText(_rawLyrics);
    if (plain.isEmpty) {
      AppSnackBar.show(context, message: '当前暂无可复制的歌词文本');
      return;
    }
    await Clipboard.setData(ClipboardData(text: plain));
    if (!context.mounted) return;
    AppSnackBar.show(context, message: '已复制完整歌词');
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

  IconData _modeIcon(PlaybackMode mode) {
    return switch (mode) {
      PlaybackMode.sequence => Icons.playlist_play_rounded,
      PlaybackMode.repeatAll => Icons.repeat_rounded,
      PlaybackMode.repeatOne => Icons.repeat_one_rounded,
      PlaybackMode.shuffle => Icons.shuffle_rounded,
    };
  }

  void _openQueueSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => _PlaybackQueueSheet(core: widget.core),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.player,
        widget.core.downloads,
        widget.core.library,
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

        if (_lyricsSongKey != song.key) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncLyricsIfNeeded();
          });
        }

        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final artworkSize = math.min(math.max(screenWidth - 48, 180.0), 420.0);

        final source = player.source;
        final isTrial = source?.isTrial ?? false;
        final isFavorite = widget.core.library.isFavorite(song);

        final durationMs = player.duration.inMilliseconds;
        final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
        final currentMs =
            (_dragPositionMs ?? player.position.inMilliseconds.toDouble())
                .clamp(0.0, maxMs);
        final displayPosition = Duration(milliseconds: currentMs.round());

        final downloadTask = widget.core.downloads.tasks
            .where((t) => t.id == song.key || t.song.key == song.key)
            .firstOrNull;

        final activeLyricIdx = UiFormatters.activeLyricIndex(
          _parsedLyrics,
          player.position,
        );
        if (activeLyricIdx >= 0 && player.isPlaying) {
          _scrollToActiveLyricIfNeeded(activeLyricIdx);
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.94,
          minChildSize: 0.6,
          maxChildSize: 0.98,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('now_playing_close_button'),
                        tooltip: '收起播放页',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
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
                            if (source != null)
                              _SmallBadge(
                                label: UiFormatters.formatMediaSourceBadge(
                                  source,
                                ),
                                backgroundColor: colorScheme.secondaryContainer,
                                foregroundColor:
                                    colorScheme.onSecondaryContainer,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('now_playing_queue_button'),
                        tooltip: '播放队列 (${player.queue.length})',
                        onPressed: () => _openQueueSheet(context),
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isTrial)
                    Container(
                      key: const Key('now_playing_trial_banner'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.trialSurfaceDark
                            : AppTheme.trialSurfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              (isDark
                                      ? AppTheme.trialAmberDark
                                      : AppTheme.trialAmberLight)
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '试听片段：当前仅返回试听音源（非完整歌曲）',
                              style: TextStyle(
                                fontSize: 12.5,
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
                      margin: const EdgeInsets.only(bottom: 12),
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
                  Center(
                    child: Container(
                      key: const Key('now_playing_large_artwork'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.38 : 0.14,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: SongCover(
                        artworkUrl: song.artworkUrl,
                        size: artworkSize,
                        borderRadius: 24,
                        isPlaying: player.isPlaying,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.22,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                song.artists.isEmpty ? '未知歌手' : song.artists,
                                if (song.album.isNotEmpty) song.album,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('now_playing_favorite_button'),
                        tooltip: isFavorite ? '取消本机收藏' : '加入本机收藏',
                        onPressed: () {
                          unawaited(widget.core.library.toggleFavorite(song));
                        },
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      IconButton(
                        key: const Key('now_playing_mode_button'),
                        tooltip:
                            '播放模式：${UiFormatters.playbackModeLabel(player.mode)}（点击切换）',
                        onPressed: () {
                          final nextMode = UiFormatters.nextPlaybackMode(
                            player.mode,
                          );
                          unawaited(player.setMode(nextMode));
                        },
                        icon: Icon(
                          _modeIcon(player.mode),
                          color: player.mode == PlaybackMode.sequence
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.primary,
                        ),
                      ),
                      IconButton.filledTonal(
                        key: const Key('now_playing_prev_button'),
                        tooltip: '上一首',
                        onPressed: player.queue.isEmpty
                            ? null
                            : player.previous,
                        icon: const Icon(Icons.skip_previous_rounded, size: 26),
                      ),
                      FilledButton.icon(
                        key: const Key('now_playing_play_pause_button'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                        ),
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
                                size: 26,
                              ),
                        label: Text(
                          player.isLoading
                              ? '加载中…'
                              : (player.isPlaying ? '暂停播放' : '开始播放'),
                        ),
                      ),
                      IconButton.filledTonal(
                        key: const Key('now_playing_next_button'),
                        tooltip: '下一首',
                        onPressed: player.queue.isEmpty ? null : player.next,
                        icon: const Icon(Icons.skip_next_rounded, size: 26),
                      ),
                      IconButton(
                        tooltip: '停止播放',
                        onPressed: () async {
                          await player.stop();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        key: const Key('now_playing_mode_chip'),
                        avatar: Icon(_modeIcon(player.mode), size: 16),
                        label: Text(
                          UiFormatters.playbackModeLabel(player.mode),
                        ),
                        onPressed: () {
                          final nextMode = UiFormatters.nextPlaybackMode(
                            player.mode,
                          );
                          unawaited(player.setMode(nextMode));
                        },
                      ),
                      ActionChip(
                        key: const Key('now_playing_open_queue_chip'),
                        avatar: const Icon(Icons.queue_music_rounded, size: 16),
                        label: Text('播放队列 (${player.queue.length})'),
                        onPressed: () => _openQueueSheet(context),
                      ),
                      OutlinedButton.icon(
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
                                  if (context.mounted) {
                                    AppSnackBar.show(
                                      context,
                                      message: '已重新开始下载「${song.name}」',
                                    );
                                  }
                                } else if (downloadTask == null) {
                                  await widget.core.downloads.enqueue(song);
                                  if (context.mounted) {
                                    AppSnackBar.show(
                                      context,
                                      message: '已将「${song.name}」加入下载任务',
                                    );
                                  }
                                } else if (widget.onOpenDownloads != null) {
                                  Navigator.of(context).pop();
                                  widget.onOpenDownloads!();
                                }
                              },
                        icon: Icon(switch (downloadTask?.state) {
                          DownloadState.completed =>
                            Icons.download_done_rounded,
                          DownloadState.queued ||
                          DownloadState.resolving ||
                          DownloadState.downloading =>
                            Icons.downloading_rounded,
                          DownloadState.failed ||
                          DownloadState.cancelled => Icons.refresh_rounded,
                          null => Icons.download_rounded,
                        }, size: 18),
                        label: Text(
                          isTrial
                              ? '试听不可下载'
                              : switch (downloadTask?.state) {
                                  DownloadState.completed => '已下载',
                                  DownloadState.queued ||
                                  DownloadState.resolving ||
                                  DownloadState.downloading =>
                                    UiFormatters.downloadStateLabel(
                                      downloadTask!.state,
                                    ),
                                  DownloadState.failed ||
                                  DownloadState.cancelled => '重试下载',
                                  null => '下载歌曲',
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lyrics_outlined,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '同步歌词 (LRC)',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_rawLyrics.trim().isNotEmpty)
                                  TextButton.icon(
                                    key: const Key(
                                      'now_playing_copy_lyrics_button',
                                    ),
                                    onPressed: () => _copyFullLyrics(context),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('复制全文'),
                                  ),
                                IconButton(
                                  key: const Key(
                                    'now_playing_refresh_lyrics_button',
                                  ),
                                  tooltip: '刷新歌词',
                                  onPressed: _loadingLyrics
                                      ? null
                                      : () => _fetchLyrics(song),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_loadingLyrics)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
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
                          ConstrainedBox(
                            key: const Key('now_playing_lyrics_scroll_box'),
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: SingleChildScrollView(
                              controller: _lyricsScrollController,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < _parsedLyrics.length; i++)
                                    _LyricRow(
                                      key: i < _lyricKeys.length
                                          ? _lyricKeys[i]
                                          : null,
                                      line: _parsedLyrics[i],
                                      isActive: i == activeLyricIdx,
                                      reduceMotion: reduceMotion,
                                      onTap:
                                          _parsedLyrics[i].timestamp == null ||
                                              source == null
                                          ? null
                                          : () => player.seek(
                                              _parsedLyrics[i].timestamp!,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PlaybackQueueSheet extends StatelessWidget {
  const _PlaybackQueueSheet({required this.core});

  final Music163Core core;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: core.player,
      builder: (context, _) {
        final player = core.player;
        final queue = player.queue;
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.queue_music_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '播放队列 (${queue.length}) · ${UiFormatters.playbackModeLabel(player.mode)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (queue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('当前播放队列为空')),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      key: const Key('playback_queue_list'),
                      shrinkWrap: true,
                      itemCount: queue.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = queue[index];
                        final isCurrent = index == player.currentIndex;
                        return ListTile(
                          key: Key('queue_song_item_${item.key}'),
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: isCurrent
                              ? colorScheme.primaryContainer.withValues(
                                  alpha: 0.45,
                                )
                              : colorScheme.surfaceContainerLow,
                          leading: Icon(
                            isCurrent
                                ? Icons.equalizer_rounded
                                : Icons.music_note_rounded,
                            color: isCurrent
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isCurrent
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${item.artists} · ${item.platform.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            unawaited(
                              player.playQueue(queue, startIndex: index),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    super.key,
    required this.line,
    required this.isActive,
    required this.reduceMotion,
    this.onTap,
  });

  final LrcLine line;
  final bool isActive;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final animDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: animDuration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
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
              child: AnimatedDefaultTextStyle(
                duration: animDuration,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: isActive ? 15.5 : 14,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
                child: Text(line.text),
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
