import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../data/credentials.dart';
import '../data/qq_api.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class QqAuthController extends SafeNotifier {
  QqAuthController(this._api, this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _api.beforeAuthorizedRequest = ensureFresh;
  }
  final QqApi _api;
  final CredentialStore _store;
  final DateTime Function() _now;
  static const credentialKey = 'qqmusic.credential';
  bool isBusy = false;
  bool get isLoggedIn => profile != null;
  AccountProfile? profile;
  String? error;
  Uint8List? qrBytes;
  QrStatus qrStatus = QrStatus.idle;
  QqQrCode? _qr;
  Timer? _timer;
  bool _polling = false;
  int _generation = 0;
  DateTime? _expiresAt;
  DateTime? get qrExpiresAt => _qr == null ? null : _expiresAt;
  Future<void> _writes = Future.value();
  Future<void>? _refreshing;

  Future<void> restore() async {
    final raw = await _store.read(credentialKey);
    if (raw == null) return;
    try {
      final account = QqCredential.parse(raw);
      _api.credential = account;
      profile = AccountProfile(
        id: int.parse(account.musicId),
        nickname: 'QQ 音乐用户',
      );
      if (account.expiresSoon) {
        await refresh();
      } else {
        // Stored credentials were already confirmed at login. Do not rotate a
        // still-valid music key or block startup on optional account details.
        unawaited(_enrichProfile(account, _generation));
      }
      changed();
    } catch (_) {
      _api.credential = null;
      profile = null;
      error = '保存的 QQ 音乐凭据无法读取，请重新登录。';
    }
  }

  Future<void> _persist(QqCredential? account, int generation) {
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (generation != _generation || closed) return;
      if (account == null) {
        await _store.delete(credentialKey);
      } else {
        await _store.write(credentialKey, jsonEncode(account.fields));
      }
      if (generation == _generation && !closed) _api.credential = account;
    });
    _writes = next;
    return next;
  }

  Future<void> ensureFresh() async {
    if (_api.credential?.expiresSoon != true || closed) return;
    await refresh();
  }

  Future<void> refresh() {
    if (closed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final original = _api.credential;
    if (original == null || isBusy) return;
    final generation = _generation;
    isBusy = true;
    error = null;
    changed();
    try {
      var account = original;
      if (account.canRefresh) {
        account = await _api.refresh(account);
        if (generation != _generation || closed) return;
        await _persist(account, generation);
        if (generation != _generation || closed) return;
        profile ??= AccountProfile(
          id: int.parse(account.musicId),
          nickname: 'QQ 音乐用户',
        );
        await _enrichProfile(account, generation);
        return;
      }
      final user = await _api.profile(account);
      if (generation != _generation || closed) return;
      await _persist(account, generation);
      if (generation == _generation && !closed) profile = user;
    } catch (e) {
      if (generation == _generation && !closed) {
        error = userError(e);
        // Network failures keep the saved account; rejected login loses its UI status.
        if (e is MusicException && {1000, 104401, 104400}.contains(e.code)) {
          profile = null;
        }
      }
    } finally {
      if (generation == _generation && !closed) {
        isBusy = false;
        changed();
      }
    }
  }

  Future<void> importCredential(String input) async {
    if (isBusy || closed) return;
    cancelQr();
    final generation = ++_generation;
    isBusy = true;
    error = null;
    changed();
    try {
      final account = QqCredential.parse(input);
      final user = await _api.profile(account);
      if (generation != _generation || closed) return;
      await _persist(account, generation);
      if (generation == _generation && !closed) {
        profile = user;
        qrStatus = QrStatus.success;
      }
    } catch (e) {
      if (generation == _generation && !closed) error = userError(e);
    } finally {
      if (generation == _generation && !closed) {
        isBusy = false;
        changed();
      }
    }
  }

  Future<void> createQr() async {
    if (isBusy || closed) return;
    cancelQr();
    final generation = ++_generation;
    isBusy = true;
    error = null;
    changed();
    try {
      final qr = await _api.createQr();
      if (generation != _generation || closed) return;
      _qr = qr;
      qrBytes = qr.bytes;
      _expiresAt = _now().add(const Duration(minutes: 2));
      qrStatus = QrStatus.waiting;
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(pollQr()),
      );
    } catch (e) {
      if (generation == _generation && !closed) error = userError(e);
    } finally {
      if (generation == _generation && !closed) {
        isBusy = false;
        changed();
      }
    }
  }

  /// Also callable by deterministic tests; periodic polling uses this same path.
  Future<void> pollQr() async {
    final qr = _qr;
    if (qr == null || _polling || closed) return;
    final generation = _generation;
    _polling = true;
    try {
      final result = await _api.checkQr(qr);
      if (generation != _generation || closed) return;
      qrStatus = result.status;
      error = null;
      // Returning from QQ may happen after the local QR window even when QQ
      // already accepted the login. Ask QQ before expiring a confirmed scan.
      if ({QrStatus.waiting, QrStatus.scanned}.contains(result.status) &&
          _now().isAfter(_expiresAt!)) {
        qrStatus = QrStatus.expired;
      }
      if ({QrStatus.expired, QrStatus.refused}.contains(qrStatus)) {
        _timer?.cancel();
        _qr = null;
        qrBytes = null;
        _expiresAt = null;
      }
      if (result.status == QrStatus.authorizing || result.credential != null) {
        _timer?.cancel();
        _qr = null;
        qrBytes = null;
        _expiresAt = null;
        qrStatus = QrStatus.authorizing;
        isBusy = true;
        changed();
        try {
          final account =
              result.credential ??
              await _api.authorizeQr(result.callbackUrl!, session: qr);
          if (generation != _generation || closed) return;
          await _persist(account, generation);
          if (generation != _generation || closed) return;
          profile = AccountProfile(
            id: int.parse(account.musicId),
            nickname: 'QQ 音乐用户',
          );
          qrStatus = QrStatus.success;
          isBusy = false;
          changed();
          // Music credentials are already confirmed by QQLogin. Optional profile
          // enrichment must never discard them or expire the consumed QR code.
          unawaited(_enrichProfile(account, generation));
        } catch (e) {
          if (generation != _generation || closed) return;
          qrStatus = QrStatus.failed;
          error = e is MusicException ? e.message : 'QQ 音乐登录未完成，请检查网络后重新获取二维码。';
          isBusy = false;
        }
      }
    } catch (e) {
      if (generation == _generation && !closed) {
        error = userError(e);
        // A temporary polling failure is not an expired QR. Keep retrying up
        // to its real deadline; authorization errors are handled separately.
        if (_expiresAt != null && _now().isAfter(_expiresAt!)) {
          _timer?.cancel();
          _qr = null;
          qrBytes = null;
          _expiresAt = null;
          qrStatus = QrStatus.failed;
          error = '暂时无法确认 QQ 扫码结果，请检查网络后重新获取二维码。';
        }
      }
    } finally {
      _polling = false;
      if (generation == _generation && !closed) changed();
    }
  }

  Future<void> _enrichProfile(QqCredential account, int generation) async {
    try {
      final user = await _api.profile(account);
      if (generation != _generation || closed) return;
      profile = user;
      error = null;
    } catch (_) {
      if (generation != _generation || closed) return;
      error = 'QQ 音乐已登录，账号资料暂未同步，可稍后点击刷新。';
    }
    if (generation == _generation && !closed) changed();
  }

  void cancelQr() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _qr = null;
    qrBytes = null;
    _expiresAt = null;
    qrStatus = QrStatus.idle;
    isBusy = false;
    changed();
  }

  Future<void> logout() async {
    cancelQr();
    final generation = _generation;
    _api.credential = null;
    profile = null;
    error = null;
    isBusy = true;
    changed();
    try {
      await _persist(null, generation);
    } catch (_) {
      if (generation == _generation && !closed) error = 'QQ 本地凭据清理失败，请重试退出登录。';
    } finally {
      if (generation == _generation && !closed) {
        isBusy = false;
        changed();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _api.beforeAuthorizedRequest = null;
    super.dispose();
  }
}
