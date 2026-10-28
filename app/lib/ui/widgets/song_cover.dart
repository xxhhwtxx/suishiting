import 'package:flutter/material.dart';

/// 歌曲封面组件：优先加载网络封面，加载失败或无地址时展示黑胶唱片视觉占位。
/// 使用 [Image.network] 的 [errorBuilder] 避免测试环境或离线环境下抛出未捕获图片异常。
class SongCover extends StatelessWidget {
  const SongCover({
    super.key,
    required this.artworkUrl,
    this.size = 52,
    this.borderRadius = 12,
    this.isPlaying = false,
  });

  final String? artworkUrl;
  final double size;
  final double borderRadius;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = artworkUrl?.trim();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isPlaying
              ? colorScheme.primary.withValues(alpha: 0.65)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: isPlaying ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _VinylFallback(size: size),
            )
          else
            _VinylFallback(size: size),
          if (isPlaying)
            Container(
              color: Colors.black.withValues(alpha: 0.32),
              alignment: Alignment.center,
              child: Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: (size * 0.44).clamp(18.0, 36.0),
              ),
            ),
        ],
      ),
    );
  }
}

class _VinylFallback extends StatelessWidget {
  const _VinylFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surfaceContainerHighest,
            const Color(0xFF1B1618),
          ],
          stops: const [0.18, 0.52, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.album_rounded,
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.88),
          size: (size * 0.48).clamp(20.0, 48.0),
        ),
      ),
    );
  }
}

/// 账号头像组件：安全加载网络头像，失败或为空时回退至默认头像图标。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.avatarUrl,
    required this.nickname,
    this.size = 56,
  });

  final String? avatarUrl;
  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = avatarUrl?.trim();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _AvatarFallback(nickname: nickname, size: size),
            )
          : _AvatarFallback(nickname: nickname, size: size),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.nickname, required this.size});

  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = nickname.trim();
    final initial = trimmed.isNotEmpty
        ? String.fromCharCode(trimmed.runes.first).toUpperCase()
        : '随';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: (size * 0.42).clamp(16.0, 28.0),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
