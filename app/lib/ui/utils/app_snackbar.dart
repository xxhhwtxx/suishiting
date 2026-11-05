import 'dart:async';

import 'package:flutter/material.dart';

/// 统一短提示管理：
/// 1. 连续触发前先清理旧提示；
/// 2. 显式使用 [Timer] 定时关闭，确保即使包含 [SnackBarAction] 且系统开启无障碍导航
///    （`accessibleNavigation: true`）时也会在约 2 秒后自动消失；
/// 3. 支持在宿主销毁时调用 [cancel] 释放定时器，避免测试环境残留未完成 Timer。
abstract final class AppSnackBar {
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    _dismissTimer?.cancel();
    _dismissTimer = null;
    messenger.clearSnackBars();

    final controller = messenger.showSnackBar(
      SnackBar(content: Text(message), action: action, duration: duration),
    );

    final timer = Timer(duration, () {
      try {
        controller.close();
      } catch (_) {}
    });
    _dismissTimer = timer;

    unawaited(
      controller.closed.whenComplete(() {
        if (identical(_dismissTimer, timer)) {
          _dismissTimer?.cancel();
          _dismissTimer = null;
        }
      }),
    );
  }

  static void cancel() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }
}
