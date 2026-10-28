import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:music163_core/music163_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/account_settings_page.dart';
import '../pages/downloads_page.dart';
import '../pages/search_page.dart';
import '../widgets/player_bar.dart';

/// 主界面导航骨架：支持手机竖屏底部导航栏与宽屏/横屏侧边导航栏，
/// 并在底部常驻展示迷你播放控制条。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.core,
    this.shareFile,
    this.openExternalUrl,
    this.themeMode = ThemeMode.system,
    this.onCycleThemeMode,
  });

  static final Uri githubProfileUri = Uri.parse('https://github.com/xxhhwtxx');

  final Music163Core core;
  final Future<void> Function(DownloadTask task)? shareFile;
  final Future<bool> Function(Uri url)? openExternalUrl;
  final ThemeMode themeMode;
  final VoidCallback? onCycleThemeMode;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _handleOpenGitHub(BuildContext context) async {
    final uri = HomeShell.githubProfileUri;
    var opened = false;
    try {
      if (widget.openExternalUrl != null) {
        opened = await widget.openExternalUrl!(uri);
      } else {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) {
          opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      }
    } catch (_) {
      opened = false;
    }

    if (!opened && context.mounted) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 GitHub 链接：${uri.toString()}')),
      );
    }
  }

  IconData get _themeIcon => switch (widget.themeMode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  String get _themeTooltip => switch (widget.themeMode) {
    ThemeMode.system => '主题：跟随系统（点击切换）',
    ThemeMode.light => '主题：浅色模式（点击切换）',
    ThemeMode.dark => '主题：深色模式（点击切换）',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.downloads,
        widget.core.auth,
        widget.core.qqAuth,
      ]),
      builder: (context, _) {
        final activeDownloads = widget.core.downloads.tasks
            .where((t) => t.isActive)
            .length;
        final totalDownloads = widget.core.downloads.tasks.length;
        final isLoggedIn =
            widget.core.auth.isLoggedIn || widget.core.qqAuth.isLoggedIn;
        final colorScheme = Theme.of(context).colorScheme;

        final pages = <Widget>[
          SearchPageView(
            core: widget.core,
            onNavigateToDownloads: () => _selectTab(1),
            onNavigateToAccount: () => _selectTab(2),
          ),
          DownloadsPageView(
            core: widget.core,
            onNavigateToSearch: () => _selectTab(0),
            shareFile: widget.shareFile,
          ),
          AccountSettingsPageView(core: widget.core),
        ];

        Widget buildDownloadIcon({required bool selected}) {
          final icon = Icon(
            selected
                ? Icons.download_for_offline_rounded
                : Icons.download_for_offline_outlined,
          );
          if (activeDownloads > 0) {
            return Badge.count(count: activeDownloads, child: icon);
          }
          if (totalDownloads > 0) {
            return Badge(
              backgroundColor: colorScheme.secondary,
              smallSize: 7,
              child: icon,
            );
          }
          return icon;
        }

        Widget buildAccountIcon({required bool selected}) {
          final icon = Icon(
            selected ? Icons.person_rounded : Icons.person_outline_rounded,
          );
          if (isLoggedIn) {
            return Badge(
              backgroundColor: Colors.green.shade600,
              smallSize: 8,
              child: icon,
            );
          }
          return icon;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final useRail = constraints.maxWidth >= 640;

            return Scaffold(
              appBar: AppBar(
                title: const _BrandTitle(),
                actions: [
                  IconButton(
                    key: const Key('app_bar_github_button'),
                    tooltip: '访问 GitHub 主页 (xxhhwtxx)',
                    onPressed: () => _handleOpenGitHub(context),
                    icon: const _GitHubBadgeIcon(),
                  ),
                  if (widget.onCycleThemeMode != null)
                    IconButton(
                      key: const Key('app_bar_theme_toggle'),
                      tooltip: _themeTooltip,
                      onPressed: widget.onCycleThemeMode,
                      icon: Icon(_themeIcon),
                    ),
                ],
              ),
              body: SafeArea(
                bottom: false,
                child: useRail
                    ? Row(
                        children: [
                          NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: _selectTab,
                            destinations: [
                              const NavigationRailDestination(
                                icon: Icon(Icons.search_rounded),
                                selectedIcon: Icon(Icons.manage_search_rounded),
                                label: Text('搜索', key: Key('nav_tab_search')),
                              ),
                              NavigationRailDestination(
                                icon: buildDownloadIcon(selected: false),
                                selectedIcon: buildDownloadIcon(selected: true),
                                label: const Text(
                                  '下载',
                                  key: Key('nav_tab_downloads'),
                                ),
                              ),
                              NavigationRailDestination(
                                icon: buildAccountIcon(selected: false),
                                selectedIcon: buildAccountIcon(selected: true),
                                label: const Text(
                                  '账号与设置',
                                  key: Key('nav_tab_account'),
                                ),
                              ),
                            ],
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: pages,
                            ),
                          ),
                        ],
                      )
                    : IndexedStack(index: _selectedIndex, children: pages),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MiniPlayerBar(
                      core: widget.core,
                      onOpenQueueOrDownloads: () => _selectTab(1),
                    ),
                    if (!useRail)
                      NavigationBar(
                        key: const Key('main_navigation_bar'),
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectTab,
                        destinations: [
                          const NavigationDestination(
                            key: Key('nav_tab_search'),
                            icon: Icon(Icons.search_rounded),
                            selectedIcon: Icon(Icons.manage_search_rounded),
                            label: '搜索',
                          ),
                          NavigationDestination(
                            key: Key('nav_tab_downloads'),
                            icon: buildDownloadIcon(selected: false),
                            selectedIcon: buildDownloadIcon(selected: true),
                            label: '下载',
                          ),
                          NavigationDestination(
                            key: Key('nav_tab_account'),
                            icon: buildAccountIcon(selected: false),
                            selectedIcon: buildAccountIcon(selected: true),
                            label: '账号与设置',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 顶部导航栏左侧品牌标题：「随时听 Anytime Music」（中文粗体 + 衬线斜体英文）。
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '随时听',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Anytime Music',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              fontFamily: 'serif',
              fontFamilyFallback: const [
                'Georgia',
                'Times New Roman',
                'Noto Serif',
                'serif',
              ],
              letterSpacing: 0.35,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部导航栏右侧的圆形 GitHub 线条猫图标（还原用户指定样式）。
class _GitHubBadgeIcon extends StatelessWidget {
  const _GitHubBadgeIcon();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final badgeBackground = isDark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFEBE5DA);
    final strokeColor = isDark
        ? colorScheme.onSurface
        : const Color(0xFF141B2D);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: badgeBackground, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(18, 18),
        painter: _GitHubCatPainter(color: strokeColor),
      ),
    );
  }
}

class _GitHubCatPainter extends CustomPainter {
  const _GitHubCatPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bodyPath = Path()
      ..moveTo(15, 22)
      ..lineTo(15, 18)
      ..arcToPoint(
        const Offset(14, 14.5),
        radius: const Radius.circular(4.8),
        clockwise: false,
      )
      ..cubicTo(17, 14.5, 20, 12.5, 20, 9)
      ..cubicTo(20.08, 7.75, 19.73, 6.52, 19, 5.5)
      ..cubicTo(19.28, 4.35, 19.28, 3.15, 19, 2)
      ..cubicTo(19, 2, 18, 2, 16, 3.5)
      ..cubicTo(13.36, 3.0, 10.64, 3.0, 8, 3.5)
      ..cubicTo(6, 2, 5, 2, 5, 2)
      ..cubicTo(4.7, 3.15, 4.7, 4.35, 5, 5.5)
      ..arcToPoint(
        const Offset(4, 9),
        radius: const Radius.circular(5.403),
        clockwise: false,
      )
      ..cubicTo(4, 12.5, 7, 14.5, 10, 14.5)
      ..cubicTo(9.61, 14.99, 9.32, 15.55, 9.15, 16.15)
      ..cubicTo(8.98, 16.75, 8.93, 17.38, 9, 18)
      ..lineTo(9, 22);

    final tailPath = Path()
      ..moveTo(9, 18)
      ..cubicTo(4.49, 20, 4, 16, 2, 16);

    canvas.drawPath(bodyPath, paint);
    canvas.drawPath(tailPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GitHubCatPainter oldDelegate) =>
      oldDelegate.color != color;
}
