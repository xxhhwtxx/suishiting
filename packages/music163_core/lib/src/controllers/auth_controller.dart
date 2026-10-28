import 'dart:async';
import '../data/credentials.dart';
import '../data/netease_api.dart';
import '../domain/models.dart';
import 'base_controller.dart';

class AuthController extends SafeNotifier {
  AuthController(this._api, this._store);
  final NeteaseApi _api;
  final CredentialStore _store;
  static const credentialKey = 'music163.music_u';
  bool isBusy = false;
  bool get isLoggedIn => profile != null;
  AccountProfile? profile;
  String? error;
  QrSession? qrSession;
  QrStatus qrStatus = QrStatus.idle;
  Timer? _timer;
  bool _polling = false;
  int _generation = 0;
  Future<void> _writes = Future.value();

  Future<void> restore() async {
    _api.musicU = await _store.read(credentialKey);
    if (_api.musicU != null) await refresh();
  }

  Future<void> refresh() async {
    if (isBusy) return;
    final generation = _generation;
    isBusy = true;
    error = null;
    changed();
    try {
      final result = await _profile();
      if (generation == _generation) profile = result;
    } catch (e) {
      if (generation == _generation) {
        error = userError(e);
        if (e is MusicException && {301, 302}.contains(e.code)) profile = null;
      }
    } finally {
      if (generation == _generation) {
        isBusy = false;
        changed();
      }
    }
  }

  Future<AccountProfile> _profile({String? credential}) async {
    final response = await _api.request(
      '/api/w/nuser/account/get',
      {},
      credential: credential,
    );
    final body =
        response.json['data'] as Map<String, dynamic>? ?? response.json;
    final value = body['profile'] as Map<String, dynamic>?;
    if (value == null || (value['userId'] as num? ?? 0) == 0) {
      throw const MusicException('网易云登录已失效，请重新登录。', code: 301);
    }
    return AccountProfile(
      id: (value['userId'] as num).toInt(),
      nickname: value['nickname'] as String? ?? '网易云用户',
      avatarUrl: value['avatarUrl'] as String?,
    );
  }

  Future<void> _persist(String? value, int generation) {
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (generation != _generation) return;
      if (value == null) {
        await _store.delete(credentialKey);
      } else {
        await _store.write(credentialKey, value);
      }
      if (generation == _generation) _api.musicU = value;
    });
    _writes = next;
    return next;
  }

  Future<void> importMusicU(String input) async {
    if (isBusy || closed) return;
    cancelQr();
    final generation = ++_generation;
    isBusy = true;
    error = null;
    changed();
    try {
      final cookieMatch = RegExp(
        r'(?:^|;\s*)MUSIC_U=([^;\s]+)',
      ).firstMatch(input.trim());
      final value = cookieMatch?.group(1) ?? input.trim();
      if (value.isEmpty ||
          value.length > 8192 ||
          RegExp(r'[\s;,\r\n]').hasMatch(value)) {
        throw const MusicException('请输入有效的 MUSIC_U 值或包含 MUSIC_U 的 Cookie。');
      }
      final account = await _profile(credential: value);
      if (generation != _generation || closed) return;
      await _persist(value, generation);
      if (generation == _generation) {
        profile = account;
        qrStatus = QrStatus.success;
      }
    } catch (e) {
      if (generation == _generation) error = userError(e);
    } finally {
      if (generation == _generation) {
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
      final result = await _api.request('/api/login/qrcode/unikey', {
        'type': '3',
      }, anonymous: true);
      final key = result.json['unikey'] as String?;
      if (key == null || key.isEmpty) {
        throw const MusicException('获取登录二维码失败，请重试。');
      }
      if (generation != _generation || closed) return;
      qrSession = QrSession(
        key: key,
        loginUrl:
            'https://music.163.com/login?codekey=${Uri.encodeComponent(key)}',
        expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      );
      qrStatus = QrStatus.waiting;
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        unawaited(_poll(generation));
      });
    } catch (e) {
      if (generation == _generation) error = userError(e);
    } finally {
      if (generation == _generation) {
        isBusy = false;
        changed();
      }
    }
  }

  Future<void> _poll(int generation) async {
    if (_polling || generation != _generation || qrSession == null || closed) {
      return;
    }
    if (DateTime.now().isAfter(qrSession!.expiresAt)) {
      _timer?.cancel();
      qrStatus = QrStatus.expired;
      changed();
      return;
    }
    _polling = true;
    try {
      final reply = await _api.request(
        '/api/login/qrcode/client/login',
        {'key': qrSession!.key, 'type': '3'},
        anonymous: true,
        allowedCodes: {800, 801, 802, 803},
      );
      if (generation != _generation || closed) return;
      error = null;
      switch (reply.json['code']) {
        case 800:
          _timer?.cancel();
          qrStatus = QrStatus.expired;
        case 801:
          qrStatus = QrStatus.waiting;
        case 802:
          qrStatus = QrStatus.scanned;
        case 803:
          _timer?.cancel();
          final value = RegExp(
            r'(?:^|[,;]\s*)MUSIC_U=([^;,\s]+)',
          ).firstMatch(reply.setCookie ?? '')?.group(1);
          if (value == null || value.isEmpty) {
            throw const MusicException('登录响应未包含凭据，请重新扫码。');
          }
          final account = await _profile(credential: value);
          if (generation != _generation || closed) return;
          await _persist(value, generation);
          if (generation != _generation || closed) return;
          profile = account;
          qrStatus = QrStatus.success;
          qrSession = null;
      }
      changed();
    } catch (e) {
      if (generation == _generation) {
        error = userError(e);
        changed();
      }
    } finally {
      _polling = false;
    }
  }

  void cancelQr() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    qrSession = null;
    qrStatus = QrStatus.idle;
    isBusy = false;
    changed();
  }

  Future<void> logout() async {
    cancelQr();
    final generation = _generation;
    // Remove in-memory credentials immediately, even if disk deletion fails.
    _api.musicU = null;
    profile = null;
    error = null;
    isBusy = true;
    changed();
    try {
      await _persist(null, generation);
    } catch (_) {
      if (generation == _generation) error = '本地凭据清理失败，请重试退出登录。';
    } finally {
      if (generation == _generation) {
        isBusy = false;
        changed();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
