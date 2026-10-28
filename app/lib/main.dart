import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import 'ui/shell/home_shell.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

typedef Music163App = MyApp;

/// 应用根组件：支持直接注入已创建的 [Music163Core]，
/// 或通过 [coreLoader]（默认 [Music163Core.create]）异步初始化并提供失败重试界面。
class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.core,
    this.coreLoader = Music163Core.create,
    this.shareFile,
    this.openExternalUrl,
    this.closeExternalCoreOnDispose = false,
  });

  final Music163Core? core;
  final Future<Music163Core> Function() coreLoader;
  final Future<void> Function(DownloadTask task)? shareFile;
  final Future<bool> Function(Uri url)? openExternalUrl;
  final bool closeExternalCoreOnDispose;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Music163Core? _ownedCore;
  bool _isInitializing = false;
  Object? _initError;
  ThemeMode _themeMode = ThemeMode.system;

  Music163Core? get _activeCore => widget.core ?? _ownedCore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.core == null) {
      unawaited(_initializeCore());
    }
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.core != oldWidget.core && widget.core != null) {
      final previousOwned = _ownedCore;
      _ownedCore = null;
      _initError = null;
      _isInitializing = false;
      if (previousOwned != null) {
        unawaited(previousOwned.close());
      }
    } else if (widget.core == null &&
        oldWidget.core != null &&
        _ownedCore == null &&
        !_isInitializing) {
      unawaited(_initializeCore());
    }
  }

  Future<void> _initializeCore() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _initError = null;
    });
    try {
      final created = await widget.coreLoader();
      if (!mounted) {
        await created.close();
        return;
      }
      setState(() {
        _ownedCore = created;
        _isInitializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initError = error;
        _isInitializing = false;
      });
    }
  }

  void _cycleThemeMode() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      final coreToClose =
          _ownedCore ??
          (widget.closeExternalCoreOnDispose ? widget.core : null);
      if (coreToClose != null) {
        unawaited(coreToClose.close());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final coreToClose =
        _ownedCore ?? (widget.closeExternalCoreOnDispose ? widget.core : null);
    if (coreToClose != null) {
      unawaited(coreToClose.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCore = _activeCore;

    return MaterialApp(
      title: '随时听',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: activeCore != null
          ? HomeShell(
              core: activeCore,
              shareFile: widget.shareFile,
              openExternalUrl: widget.openExternalUrl,
              themeMode: _themeMode,
              onCycleThemeMode: _cycleThemeMode,
            )
          : _BootstrapScreen(
              isInitializing: _isInitializing,
              error: _initError,
              onRetry: _initializeCore,
            ),
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen({
    required this.isInitializing,
    required this.error,
    required this.onRetry,
  });

  final bool isInitializing;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: isInitializing
                      ? Column(
                          key: const Key('bootstrap_loading_view'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            const Text(
                              '正在打开随时听…',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '首次启动可能需要几秒。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const Key('bootstrap_error_view'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 32,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '核心服务初始化失败',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              error?.toString() ?? '未知初始化错误，请检查存储权限或系统音频服务。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.42,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const Key('bootstrap_retry_button'),
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('重试初始化'),
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
    );
  }
}
