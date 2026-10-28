import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import '../utils/formatters.dart';

/// 应用版本检查与 APK 更新安装卡片（仅调用 [UpdateController] 契约接口）。
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, required this.core});

  final Music163Core core;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.core.updates.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.core.updates,
      builder: (context, _) {
        final updates = widget.core.updates;
        final status = updates.status;
        final release = updates.release;
        final currentVersion = updates.currentVersionName;
        final colorScheme = Theme.of(context).colorScheme;

        final (statusTitle, statusSubtitle) = switch (status) {
          UpdateStatus.idle => (
            '检查 GitHub Releases 更新',
            updates.message ?? '点击下方「检查更新」获取最新发布版本信息。',
          ),
          UpdateStatus.checking => (
            '正在检查更新…',
            updates.message ?? '正在连接 GitHub Releases 查询最新版本，请稍候。',
          ),
          UpdateStatus.noRelease => (
            updates.message ?? '暂无可用更新',
            '当前 GitHub Releases 仓库暂未发布稳定版安装包。',
          ),
          UpdateStatus.upToDate => (
            updates.message ?? '已是最新版本',
            '当前安装版本已是最新正式版本，无需更新。',
          ),
          UpdateStatus.available => (
            '发现新版本 ${release?.version ?? ''}'.trim(),
            updates.message ?? '可下载新版 APK 安装包并调起系统安装器完成升级。',
          ),
          UpdateStatus.downloading => (
            '正在下载新版本 ${release?.version ?? ''}…'.trim(),
            UiFormatters.formatByteProgress(
              updates.downloadedBytes,
              updates.totalBytes,
            ),
          ),
          UpdateStatus.ready => (
            '新版安装包已就绪${release != null ? '（${release.version}）' : ''}',
            updates.message ?? '下载已完成，点击「安装新版」将调起系统安装器确认安装。',
          ),
          UpdateStatus.permissionRequired => (
            updates.message ?? '请允许随时听安装应用',
            '需要先在系统设置中授予「安装未知应用」权限，开启后返回本页点击「重试安装」。',
          ),
          UpdateStatus.installing => (
            '正在打开系统安装器…',
            updates.message ?? '请在系统安装界面中确认完成安装。',
          ),
          UpdateStatus.failed => (
            '更新操作未完成',
            updates.message ?? '请查看下方错误原因并重试检查或下载。',
          ),
        };

        final isWarningOrError =
            status == UpdateStatus.failed ||
            status == UpdateStatus.permissionRequired;

        return Card(
          key: const Key('app_update_card'),
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '应用更新',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      key: const Key('update_current_version_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '当前版本：${currentVersion != null && currentVersion.isNotEmpty ? currentVersion : '读取中…'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (updates.isBusy) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  key: const Key('update_status_container'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: status == UpdateStatus.permissionRequired
                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.65)
                        : colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        key: const Key('update_status_title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isWarningOrError
                              ? (status == UpdateStatus.failed
                                    ? colorScheme.error
                                    : colorScheme.onTertiaryContainer)
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusSubtitle,
                        key: const Key('update_status_subtitle'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: status == UpdateStatus.permissionRequired
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (status == UpdateStatus.downloading) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            key: const Key('update_download_progress_bar'),
                            minHeight: 6,
                            value: updates.progress,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (updates.error != null &&
                    updates.error!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('update_error_banner'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
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
                            updates.error!,
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
                if (release != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '最新版本：${release.version}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (release.size > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '大小：${UiFormatters.formatBytes(release.size)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (release.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('update_release_notes'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '版本说明',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            release.notes.trim(),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.42,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _buildActionButtons(updates, status, release),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActionButtons(
    UpdateController updates,
    UpdateStatus status,
    AppRelease? release,
  ) {
    if (status == UpdateStatus.downloading) {
      return [
        OutlinedButton.icon(
          key: const Key('update_cancel_download_button'),
          onPressed: updates.cancelDownload,
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('取消下载'),
        ),
      ];
    }

    if (status == UpdateStatus.permissionRequired) {
      return [
        FilledButton.icon(
          key: const Key('update_open_settings_button'),
          onPressed: updates.isBusy ? null : updates.openInstallSettings,
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('去设置'),
        ),
        FilledButton.tonalIcon(
          key: const Key('update_retry_install_button'),
          onPressed: updates.isBusy ? null : updates.install,
          icon: const Icon(Icons.install_mobile_rounded, size: 18),
          label: const Text('重试安装'),
        ),
      ];
    }

    if (status == UpdateStatus.ready || status == UpdateStatus.installing) {
      return [
        FilledButton.icon(
          key: const Key('update_install_button'),
          onPressed: updates.isBusy ? null : updates.install,
          icon: const Icon(Icons.install_mobile_rounded, size: 18),
          label: Text(status == UpdateStatus.installing ? '重试安装' : '安装新版'),
        ),
        OutlinedButton.icon(
          key: const Key('update_check_button'),
          onPressed: updates.isBusy ? null : updates.check,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重新检查'),
        ),
      ];
    }

    if (status == UpdateStatus.available) {
      return [
        FilledButton.icon(
          key: const Key('update_download_button'),
          onPressed: updates.isBusy ? null : updates.download,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(updates.hasDownloadedFile ? '重新下载 APK' : '下载新版 APK'),
        ),
        if (updates.hasDownloadedFile)
          FilledButton.tonalIcon(
            key: const Key('update_install_button'),
            onPressed: updates.isBusy ? null : updates.install,
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text('安装新版'),
          ),
        OutlinedButton.icon(
          key: const Key('update_check_button'),
          onPressed: updates.isBusy ? null : updates.check,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重新检查'),
        ),
      ];
    }

    if (status == UpdateStatus.failed) {
      return [
        if (updates.hasDownloadedFile)
          FilledButton.icon(
            key: const Key('update_install_button'),
            onPressed: updates.isBusy ? null : updates.install,
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text('重试安装'),
          ),
        if (release != null)
          FilledButton.tonalIcon(
            key: const Key('update_download_button'),
            onPressed: updates.isBusy ? null : updates.download,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('重试下载'),
          ),
        OutlinedButton.icon(
          key: const Key('update_check_button'),
          onPressed: updates.isBusy ? null : updates.check,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重试检查'),
        ),
      ];
    }

    return [
      FilledButton.tonalIcon(
        key: const Key('update_check_button'),
        onPressed: updates.isBusy ? null : updates.check,
        icon: const Icon(Icons.sync_rounded, size: 18),
        label: Text(status == UpdateStatus.idle ? '检查更新' : '重新检查'),
      ),
    ];
  }
}
