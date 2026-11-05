import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:music163_core/music163_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/song_cover.dart';
import '../widgets/update_card.dart';

/// 账号登录（网易云音乐 + QQ 音乐双平台独立登录）与优先音质设置页。
class AccountSettingsPageView extends StatefulWidget {
  const AccountSettingsPageView({super.key, required this.core});

  final Music163Core core;

  @override
  State<AccountSettingsPageView> createState() =>
      _AccountSettingsPageViewState();
}

class _AccountSettingsPageViewState extends State<AccountSettingsPageView> {
  final TextEditingController _musicUController = TextEditingController();
  final TextEditingController _qqCredentialController = TextEditingController();
  bool _obscureMusicU = true;
  bool _obscureQqCredential = true;

  @override
  void initState() {
    super.initState();
    _musicUController.addListener(_onTextChanged);
    _qqCredentialController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _musicUController.removeListener(_onTextChanged);
    _qqCredentialController.removeListener(_onTextChanged);
    _musicUController.dispose();
    _qqCredentialController.dispose();
    super.dispose();
  }

  Future<void> _pasteMusicU() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _musicUController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _pasteQqCredential() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _qqCredentialController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _submitMusicU() async {
    FocusScope.of(context).unfocus();
    final input = _musicUController.text;
    await widget.core.auth.importMusicU(input);
    if (!mounted) return;
    if (widget.core.auth.isLoggedIn && widget.core.auth.error == null) {
      _musicUController.clear();
      AppSnackBar.show(
        context,
        message:
            '网易云音乐登录成功，欢迎 ${widget.core.auth.profile?.nickname ?? '网易云用户'}',
      );
    }
  }

  Future<void> _submitQqCredential() async {
    FocusScope.of(context).unfocus();
    final input = _qqCredentialController.text;
    await widget.core.qqAuth.importCredential(input);
    if (!mounted) return;
    if (widget.core.qqAuth.isLoggedIn) {
      _qqCredentialController.clear();
      AppSnackBar.show(
        context,
        message:
            'QQ 音乐登录成功，欢迎 ${widget.core.qqAuth.profile?.nickname ?? 'QQ 音乐用户'}',
      );
    }
  }

  String _formatExpireTime(DateTime expiresAt) {
    final hh = expiresAt.hour.toString().padLeft(2, '0');
    final mm = expiresAt.minute.toString().padLeft(2, '0');
    final ss = expiresAt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.library,
        widget.core.auth,
        widget.core.qqAuth,
      ]),
      builder: (context, _) {
        final auth = widget.core.auth;
        final qqAuth = widget.core.qqAuth;
        final colorScheme = Theme.of(context).colorScheme;

        return SingleChildScrollView(
          key: const Key('account_settings_scroll_view'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAccountCard(context, auth, colorScheme),
              const SizedBox(height: 16),
              if (!auth.isLoggedIn) ...[
                _buildQrLoginCard(context, auth, colorScheme),
                const SizedBox(height: 16),
                _buildMusicUImportCard(context, auth, colorScheme),
                const SizedBox(height: 16),
              ],
              _buildQqAccountCard(context, qqAuth, colorScheme),
              const SizedBox(height: 16),
              if (!qqAuth.isLoggedIn) ...[
                _buildQqQrLoginCard(context, qqAuth, colorScheme),
                const SizedBox(height: 16),
                _buildQqCredentialImportCard(context, qqAuth, colorScheme),
                const SizedBox(height: 16),
              ],
              _buildQualityCard(context, colorScheme),
              const SizedBox(height: 16),
              _buildPreferencesCard(context, colorScheme),
              const SizedBox(height: 16),
              UpdateCard(core: widget.core),
              const SizedBox(height: 16),
              _buildHelpAndGuideCard(context, colorScheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    AuthController auth,
    ColorScheme colorScheme,
  ) {
    final profile = auth.profile;

    return Card(
      key: const Key('netease_account_card'),
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
                  Icons.account_circle_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '网易云音乐账号状态',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (auth.isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (auth.error != null) ...[
              Container(
                key: const Key('auth_error_banner'),
                margin: const EdgeInsets.only(bottom: 14),
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
                        auth.error!,
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
            if (profile != null) ...[
              Row(
                children: [
                  AccountAvatar(
                    avatarUrl: profile.avatarUrl,
                    nickname: profile.nickname,
                    size: 60,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.nickname,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UID: ${profile.id}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                            '已登录本机安全凭据',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const Key('auth_refresh_button'),
                    onPressed: auth.isBusy ? null : auth.refresh,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('刷新状态'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('auth_logout_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                    onPressed: auth.isBusy ? null : auth.logout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('退出登录'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '当前处于匿名访问模式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQrLoginCard(
    BuildContext context,
    AuthController auth,
    ColorScheme colorScheme,
  ) {
    final session = auth.qrSession;
    final status = auth.qrStatus;

    return Card(
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
                  Icons.qr_code_scanner_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '网易云音乐 · 扫码登录',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    UiFormatters.qrStatusLabel(status),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: status == QrStatus.expired
                          ? colorScheme.error
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (session != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '有效期至 ${_formatExpireTime(session.expiresAt)} · 自动轮询检查登录状态',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('qr_code_container'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: session.loginUrl,
                        size: 196,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('qr_create_button'),
                        onPressed: auth.isBusy ? null : auth.createQr,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: Text(session == null ? '生成登录二维码' : '重新生成二维码'),
                      ),
                      if (session != null)
                        OutlinedButton.icon(
                          key: const Key('qr_cancel_button'),
                          onPressed: auth.cancelQr,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('取消扫码'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicUImportCard(
    BuildContext context,
    AuthController auth,
    ColorScheme colorScheme,
  ) {
    return Card(
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
                Icon(Icons.key_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '网易云音乐 · 导入 MUSIC_U 凭据',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('music_u_input_field'),
              controller: _musicUController,
              obscureText: _obscureMusicU,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitMusicU(),
              decoration: InputDecoration(
                labelText: 'MUSIC_U 或 Cookie',
                hintText: '粘贴 MUSIC_U 值或 MUSIC_U=xxx;',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('music_u_visibility_toggle'),
                      tooltip: _obscureMusicU ? '显示输入内容' : '遮挡输入内容',
                      onPressed: () {
                        setState(() {
                          _obscureMusicU = !_obscureMusicU;
                        });
                      },
                      icon: Icon(
                        _obscureMusicU
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    if (_musicUController.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空',
                        onPressed: _musicUController.clear,
                        icon: const Icon(Icons.clear_rounded),
                      )
                    else
                      IconButton(
                        tooltip: '从剪贴板粘贴',
                        onPressed: _pasteMusicU,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('music_u_import_button'),
                onPressed: auth.isBusy ? null : _submitMusicU,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('验证并导入 MUSIC_U'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQqAccountCard(
    BuildContext context,
    QqAuthController qqAuth,
    ColorScheme colorScheme,
  ) {
    final profile = qqAuth.profile;

    return Card(
      key: const Key('qq_account_card'),
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
                  Icons.queue_music_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'QQ 音乐账号状态',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (qqAuth.isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (qqAuth.error != null &&
                (qqAuth.isLoggedIn || qqAuth.qrStatus == QrStatus.idle)) ...[
              Container(
                key: const Key('qq_auth_error_banner'),
                margin: const EdgeInsets.only(bottom: 14),
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
                        qqAuth.error!,
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
            if (qqAuth.isLoggedIn) ...[
              Row(
                children: [
                  AccountAvatar(
                    avatarUrl: profile?.avatarUrl,
                    nickname: profile?.nickname ?? 'QQ',
                    size: 60,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.nickname ?? '已登录，账号资料暂未同步',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile != null
                              ? 'QQ 音乐 ID: ${profile.id}'
                              : '已登录，账号资料暂未同步',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            profile != null ? 'QQ 音乐已登录本机安全凭据' : '已登录，账号资料暂未同步',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const Key('qq_auth_refresh_button'),
                    onPressed: qqAuth.isBusy ? null : qqAuth.refresh,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('刷新 QQ 状态'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('qq_auth_logout_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                    onPressed: qqAuth.isBusy ? null : qqAuth.logout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('退出 QQ 登录'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'QQ 音乐当前未登录',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQqQrLoginCard(
    BuildContext context,
    QqAuthController qqAuth,
    ColorScheme colorScheme,
  ) {
    final qrBytes = qqAuth.qrBytes;
    final status = qqAuth.qrStatus;
    final expiresAt = qqAuth.qrExpiresAt;
    final isAuthorizing = status == QrStatus.authorizing;
    final isErrorStatus =
        status == QrStatus.expired ||
        status == QrStatus.failed ||
        status == QrStatus.refused;
    final showQrAndExpiry = qrBytes != null && !isAuthorizing;

    return Card(
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
                  Icons.qr_code_2_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'QQ 音乐 · 手机 QQ 扫码登录',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    UiFormatters.qrStatusLabel(
                      status,
                      platform: MusicPlatform.qq,
                    ),
                    key: const Key('qq_qr_status_label'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isErrorStatus
                          ? colorScheme.error
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (!qqAuth.isLoggedIn &&
                      status != QrStatus.idle &&
                      qqAuth.error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const Key('qq_qr_error_banner'),
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
                              qqAuth.error!,
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
                  if (isAuthorizing) ...[
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ],
                  if (showQrAndExpiry) ...[
                    if (expiresAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '有效期至 ${_formatExpireTime(expiresAt)} · 自动轮询检查登录状态',
                        key: const Key('qq_qr_expiry_text'),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      key: const Key('qq_qr_code_container'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Image.memory(
                        qrBytes,
                        key: const Key('qq_qr_image'),
                        width: 196,
                        height: 196,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('qq_qr_create_button'),
                        onPressed: (qqAuth.isBusy || isAuthorizing)
                            ? null
                            : qqAuth.createQr,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(
                          (showQrAndExpiry || isErrorStatus)
                              ? '重新生成 QQ 二维码'
                              : '生成 QQ 登录二维码',
                        ),
                      ),
                      if (showQrAndExpiry)
                        OutlinedButton.icon(
                          key: const Key('qq_qr_cancel_button'),
                          onPressed: qqAuth.cancelQr,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('取消扫码'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQqCredentialImportCard(
    BuildContext context,
    QqAuthController qqAuth,
    ColorScheme colorScheme,
  ) {
    return Card(
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
                  Icons.vpn_key_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'QQ 音乐 · 导入 Cookie 或凭据 JSON',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('qq_credential_input_field'),
              controller: _qqCredentialController,
              obscureText: _obscureQqCredential,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitQqCredential(),
              decoration: InputDecoration(
                labelText: 'QQ 音乐 Cookie 或凭据 JSON',
                hintText: '粘贴 uin=...; qqmusic_key=...; 或 {"musicid":...}',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('qq_credential_visibility_toggle'),
                      tooltip: _obscureQqCredential ? '显示输入内容' : '遮挡输入内容',
                      onPressed: () {
                        setState(() {
                          _obscureQqCredential = !_obscureQqCredential;
                        });
                      },
                      icon: Icon(
                        _obscureQqCredential
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    if (_qqCredentialController.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空',
                        onPressed: _qqCredentialController.clear,
                        icon: const Icon(Icons.clear_rounded),
                      )
                    else
                      IconButton(
                        tooltip: '从剪贴板粘贴',
                        onPressed: _pasteQqCredential,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('qq_credential_import_button'),
                onPressed: qqAuth.isBusy ? null : _submitQqCredential,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('验证并导入 QQ 音乐凭据'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityCard(BuildContext context, ColorScheme colorScheme) {
    final currentQuality = widget.core.quality;

    return Card(
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
                Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '优先请求音质设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final quality in AudioQuality.values) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: currentQuality == quality
                      ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: Key('quality_option_${quality.name}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.core.setQuality(quality),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: currentQuality == quality
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                          width: currentQuality == quality ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            currentQuality == quality
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: currentQuality == quality
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  quality.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: currentQuality == quality
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  UiFormatters.qualitySubtitle(quality),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(BuildContext context, ColorScheme colorScheme) {
    final library = widget.core.library;
    final currentTheme = library.themePreference;

    return Card(
      key: const Key('app_preferences_card'),
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
                  Icons.palette_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '外观与歌词下载设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (library.error != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('library_error_banner'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  library.error!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '外观主题',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pref in AppThemePreference.values)
                  ChoiceChip(
                    key: Key('theme_option_${pref.name}'),
                    label: Text(UiFormatters.themePreferenceLabel(pref)),
                    selected: currentTheme == pref,
                    onSelected: (_) {
                      unawaited(library.setTheme(pref));
                    },
                  ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              key: const Key('download_lyrics_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '下载歌曲时同步保存 LRC 歌词',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '开启后下载音频会同时保存 .lrc 歌词文件，离线播放也能同步展示歌词',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: library.downloadLyrics,
              onChanged: (value) {
                unawaited(library.setDownloadLyrics(value));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpAndGuideCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      key: const Key('settings_help_card'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('settings_help_and_guide_tile'),
          leading: Icon(Icons.help_outline_rounded, color: colorScheme.primary),
          title: const Text(
            '搜索教程与使用说明',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '点击展开搜索语法、音源权限、离线歌词与客户端说明',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 16),
            Text(
              '1. 搜索与链接解析语法\n'
              '• 关键词：直接输入歌名、歌手或专辑名称搜索网易云音乐或 QQ 音乐。\n'
              '• 网易云直达：支持纯数字歌曲 ID（如 186016）及 music.163.com / 163cn.tv 单曲分享链接。\n'
              '• QQ 音乐直达：支持数字 songid、14 位字母数字 songmid（如 0039MnYb0qxYhV）及 y.qq.com 单曲链接。\n\n'
              '2. 账号登录与凭据格式\n'
              '• 匿名模式可检索曲目与歌词；完整音源及更高音质可扫码或导入凭据登录（双平台账号相互独立）。\n'
              '• 扫码登录：使用网易云音乐 App 或手机 QQ 扫描对应二维码并在手机端确认授权。\n'
              '• 凭据导入：网易云支持粘贴 MUSIC_U 值或含该值的 Cookie；QQ 音乐支持包含 uin / qqmusic_key 的 Cookie 或包含 musicid / musickey 的 JSON。\n\n'
              '3. 音源权限、本地下载与离线歌词\n'
              '• 优先音质设置仅代表向平台接口发起的请求档位，实际返回音质与试听片段受平台接口及当前登录账号权限决定。\n'
              '• 下载的音频与 .lrc 歌词保存在应用私有目录，支持系统分享导出；已完成任务即使离线也能通过本地文件播放并同步滚动 LRC 歌词。\n\n'
              '4. 账号与隐私安全\n'
              '• 随时听直接连接音乐平台官方接口，不经过任何第三方中转服务器，不打印 Cookie 日志，登录凭据仅加密保存在本机安全存储中。',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
