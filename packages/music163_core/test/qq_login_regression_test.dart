import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart' show MemoryStore;
import 'qq_test.dart' show credential, rpc, requestBody;

class LoginApi extends QqApi {
  LoginApi() : super(client: MockClient((_) async => http.Response('{}', 500)));
  int polls = 0;
  int authorizations = 0;
  Future<QqQrResult> Function()? onPoll;
  Future<QqCredential> Function()? onAuthorize;
  Future<AccountProfile> Function()? onProfile;
  @override
  Future<QqQrCode> createQr() async => QqQrCode(
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
    'test_sig',
  );
  @override
  Future<QqQrResult> checkQr(QqQrCode qr) async {
    polls++;
    return onPoll == null
        ? QqQrResult(
            QrStatus.authorizing,
            callbackUrl:
                'https://ssl.ptlogin2.qq.com/check_sig?uin=12345&ptsigx=test',
          )
        : await onPoll!();
  }

  @override
  Future<QqCredential> authorizeQr(String callback, {QqQrCode? session}) async {
    authorizations++;
    return onAuthorize == null
        ? QqCredential.parse(credential)
        : await onAuthorize!();
  }

  @override
  Future<AccountProfile> profile(QqCredential account) async =>
      onProfile == null
      ? const AccountProfile(id: 12345, nickname: 'QQ测试用户')
      : await onProfile!();
}

class FailingStore extends MemoryStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('simulated storage failure');
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('重启恢复已确认凭据，资料暂不可用不丢登录或无故刷新凭据', () async {
    final store = MemoryStore()
      ..values[QqAuthController.credentialKey] = credential;
    final api = LoginApi()
      ..onProfile = () async => throw TimeoutException('test timeout');
    final auth = QqAuthController(api, store);
    try {
      await auth.restore();
      await flush();
      expect(auth.isLoggedIn, isTrue);
      expect(api.credential?.musicId, '12345');
      expect(auth.qrStatus, QrStatus.idle);
      expect(auth.error, contains('资料暂未同步'));
    } finally {
      auth.dispose();
      api.close();
    }
  });
  test('QQ成功回复含空str_musicid时使用真实数字musicid', () {
    final account = QqCredential.parse(
      '{"musicid":12345,"str_musicid":"","musickey":"test_key"}',
    );
    expect(account.valid, isTrue);
    expect(account.musicId, '12345');
  });

  test('手机确认后进入授权中，原二维码期限不能覆盖授权结果', () async {
    var now = DateTime(2026, 10, 28, 12);
    final gate = Completer<QqCredential>();
    final api = LoginApi()..onAuthorize = () => gate.future;
    final auth = QqAuthController(api, MemoryStore(), now: () => now);
    try {
      await auth.createQr();
      expect(auth.qrExpiresAt, now.add(const Duration(minutes: 2)));
      final pending = auth.pollQr();
      await flush();
      expect(auth.qrStatus, QrStatus.authorizing);
      expect(auth.isBusy, isTrue);
      expect(auth.qrBytes, isNull);
      expect(auth.qrExpiresAt, isNull);
      now = now.add(const Duration(minutes: 3));
      await auth.pollQr();
      expect(api.polls, 1);
      expect(auth.qrStatus, QrStatus.authorizing);
      gate.complete(QqCredential.parse(credential));
      await pending;
      await flush();
      expect(auth.qrStatus, QrStatus.success);
      expect(auth.isLoggedIn, isTrue);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('成功取得音乐凭据后资料超时不会丢登录，也不显示过期', () async {
    final store = MemoryStore();
    final api = LoginApi()
      ..onProfile = () async => throw TimeoutException('test timeout');
    final auth = QqAuthController(api, store);
    try {
      await auth.createQr();
      await auth.pollQr();
      await flush();
      expect(auth.qrStatus, QrStatus.success);
      expect(auth.isLoggedIn, isTrue);
      expect(api.credential?.musicId, '12345');
      expect(store.values[QqAuthController.credentialKey], isNotNull);
      expect(auth.error, contains('已登录'));
      expect(auth.error, isNot(contains('过期')));
      await auth.pollQr();
      expect(api.polls, 1);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('轮询网络失败保留二维码并重试，不等于过期', () async {
    var calls = 0;
    final api = LoginApi()
      ..onPoll = () async {
        calls++;
        if (calls == 1) throw TimeoutException('test timeout');
        return QqQrResult(QrStatus.authorizing, callbackUrl: 'test');
      };
    final auth = QqAuthController(api, MemoryStore());
    try {
      await auth.createQr();
      await auth.pollQr();
      expect(auth.qrStatus, QrStatus.waiting);
      expect(auth.qrBytes, isNotNull);
      expect(auth.qrExpiresAt, isNotNull);
      await auth.pollQr();
      await flush();
      expect(auth.qrStatus, QrStatus.success);
      expect(auth.error, isNull);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('授权失败显示失败和真实错误，不能伪装成二维码过期', () async {
    final api = LoginApi()
      ..onAuthorize = () async =>
          throw const MusicException('QQ 音乐凭据获取失败（1000）', code: 1000);
    final auth = QqAuthController(api, MemoryStore());
    try {
      await auth.createQr();
      await auth.pollQr();
      expect(auth.qrStatus, QrStatus.failed);
      expect(auth.error, contains('1000'));
      expect(auth.isLoggedIn, isFalse);
      expect(auth.isBusy, isFalse);
      expect(auth.qrBytes, isNull);
      await auth.pollQr();
      expect(api.authorizations, 1);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('凭据保存失败不报告成功或过期', () async {
    final api = LoginApi();
    final auth = QqAuthController(api, FailingStore());
    try {
      await auth.createQr();
      await auth.pollQr();
      expect(auth.qrStatus, QrStatus.failed);
      expect(auth.isLoggedIn, isFalse);
      expect(api.credential, isNull);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('实际等待超过期限才进入过期，取消授权单独显示', () async {
    var now = DateTime(2026, 10, 28, 12);
    final api = LoginApi()..onPoll = () async => QqQrResult(QrStatus.waiting);
    final auth = QqAuthController(api, MemoryStore(), now: () => now);
    try {
      await auth.createQr();
      now = now.add(const Duration(seconds: 121));
      await auth.pollQr();
      expect(auth.qrStatus, QrStatus.expired);
      expect(api.polls, 1);
      expect(auth.qrBytes, isNull);
      api.onPoll = () async => QqQrResult(QrStatus.refused);
      await auth.createQr();
      await auth.pollQr();
      expect(auth.qrStatus, QrStatus.refused);
      expect(auth.qrBytes, isNull);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('从QQ返回超过本地倒计时，服务端已确认的扫码仍完成登录', () async {
    var now = DateTime(2026, 10, 28, 12);
    final api = LoginApi();
    final auth = QqAuthController(api, MemoryStore(), now: () => now);
    try {
      await auth.createQr();
      now = now.add(const Duration(minutes: 3));
      await auth.pollQr();
      await flush();
      expect(api.polls, 1);
      expect(auth.qrStatus, QrStatus.success);
      expect(auth.isLoggedIn, isTrue);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('退出登录时授权和资料的迟到响应不能恢复账号', () async {
    final authGate = Completer<QqCredential>();
    final api = LoginApi()..onAuthorize = () => authGate.future;
    final store = MemoryStore();
    final auth = QqAuthController(api, store);
    try {
      await auth.createQr();
      final pending = auth.pollQr();
      await flush();
      await auth.logout();
      authGate.complete(QqCredential.parse(credential));
      await pending;
      expect(auth.isLoggedIn, isFalse);
      expect(api.credential, isNull);
      expect(store.values[QqAuthController.credentialKey], isNull);
      final profileGate = Completer<AccountProfile>();
      api.onAuthorize = null;
      api.onProfile = () => profileGate.future;
      await auth.createQr();
      await auth.pollQr();
      expect(auth.isLoggedIn, isTrue);
      await auth.logout();
      profileGate.complete(const AccountProfile(id: 12345, nickname: '迟到用户'));
      await flush();
      expect(auth.profile, isNull);
      expect(api.credential, isNull);
    } finally {
      auth.dispose();
      api.close();
    }
  });

  test('刷新成功的新凭据不因后续资料服务失败丢失', () async {
    final api = QqApi(
      client: MockClient((r) async {
        final req = requestBody(r)['req_0'] as Map;
        if (req['method'] == 'Login') {
          return rpc({
            'musicid': 12345,
            'musickey': 'refreshed_key',
            'str_musicid': '',
          });
        }
        return rpc({}, code: 1000);
      }),
    )..credential = QqCredential.parse(credential);
    final store = MemoryStore();
    final auth = QqAuthController(api, store);
    try {
      await auth.refresh();
      expect(api.credential?.musicKey, 'refreshed_key');
      expect(
        store.values[QqAuthController.credentialKey],
        contains('refreshed_key'),
      );
      expect(auth.isLoggedIn, isTrue);
      expect(auth.error, contains('资料暂未同步'));
    } finally {
      auth.dispose();
      api.close();
    }
  });
}
