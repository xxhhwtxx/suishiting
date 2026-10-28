import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'logic_test.dart' show MemoryStore;

void main() {
  testWidgets('扫码成功后自动验证账号并保存凭据', (tester) async {
    var polls = 0;
    final store = MemoryStore();
    final api = NeteaseApi(
      deviceId: 'test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/unikey')) {
          expectSync(request.headers['Cookie'], isNot(contains('MUSIC_U')));
          return http.Response('{"code":200,"unikey":"test-key"}', 200);
        }
        if (request.url.path.endsWith('/client/login')) {
          polls++;
          return http.Response(
            '{"code":803}',
            200,
            headers: {
              'set-cookie': 'a=1; Path=/, MUSIC_U=qr-token; Path=/; HttpOnly',
            },
          );
        }
        expectSync(request.headers['Cookie'], contains('MUSIC_U=qr-token'));
        return http.Response(
          jsonEncode({
            'code': 200,
            'profile': {'userId': 2, 'nickname': 'test'},
          }),
          200,
        );
      }),
    );
    final auth = AuthController(api, store);
    await auth.createQr();
    expect(auth.qrSession!.loginUrl, contains('codekey=test-key'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(polls, 1);
    expect(auth.error, isNull);
    expect(auth.qrStatus, QrStatus.success);
    expect(auth.isLoggedIn, isTrue);
    expect(store.values[AuthController.credentialKey], 'qr-token');
    await tester.pump(const Duration(seconds: 9));
    expect(polls, 1);
    auth.dispose();
    api.close();
  });

  testWidgets('二维码过期停止轮询，取消后不再发请求', (tester) async {
    var polls = 0;
    final api = NeteaseApi(
      deviceId: 'test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/unikey')) {
          return http.Response('{"code":200,"unikey":"key"}', 200);
        }
        polls++;
        return http.Response('{"code":800}', 200);
      }),
    );
    final auth = AuthController(api, MemoryStore());
    await auth.createQr();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(auth.qrStatus, QrStatus.expired);
    expect(polls, 1);
    await tester.pump(const Duration(seconds: 9));
    expect(polls, 1);
    await auth.createQr();
    auth.cancelQr();
    await tester.pump(const Duration(seconds: 6));
    expect(polls, 1);
    expect(auth.qrStatus, QrStatus.idle);
    auth.dispose();
    api.close();
  });
}
