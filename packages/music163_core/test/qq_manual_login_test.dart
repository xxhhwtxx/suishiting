// Explicit manual acceptance only. Secrets remain in process memory.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

class _Diagnostics extends http.BaseClient {
  final http.Client inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    final path = request.url.path;
    if (path == '/check_sig' || path == '/oauth2.0/authorize') {
      final names = RegExp(r'(?:^|,\s*)([\w]+)=')
          .allMatches(response.headers['set-cookie'] ?? '')
          .map((m) => m[1]!)
          .toList();
      final location = Uri.tryParse(response.headers['location'] ?? '');
      final cookieShapes = <Map<String, Object?>>[];
      for (final part in (response.headers['set-cookie'] ?? '').split(
        RegExp(r',(?=\s*[\w-]+=)'),
      )) {
        if (part.trim().isEmpty) continue;
        try {
          final c = Cookie.fromSetCookieValue(part.trim());
          cookieShapes.add({
            'name': c.name,
            'domain': c.domain,
            'nonEmpty': c.value.isNotEmpty,
            'deleted':
                c.maxAge == 0 || c.expires?.isBefore(DateTime.now()) == true,
          });
        } on FormatException {
          /* Diagnostic only. */
        }
      }
      // No URLs with query strings, cookie values, account IDs or tokens.
      stdout.writeln(
        jsonEncode({
          'stage': path,
          'http': response.statusCode,
          'cookieNames': names,
          'redirectHost': location?.host,
          'redirectPath': location?.path,
          'cookieShapes': cookieShapes,
        }),
      );
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    '真实账号手动扫码验收，不保存账号凭据',
    () async {
      const qrPath = String.fromEnvironment('MANUAL_QR_PATH');
      if (qrPath.isEmpty) throw StateError('MANUAL_QR_PATH is required');
      final api = QqApi(client: _Diagnostics());
      try {
        final qr = await api.createQr();
        await File(qrPath).writeAsBytes(qr.bytes, flush: true);
        stdout.writeln('MANUAL_QR_READY');
        var previous = QrStatus.idle;
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (DateTime.now().isBefore(deadline)) {
          final result = await api.checkQr(qr);
          if (result.status != previous) {
            stdout.writeln('MANUAL_QR_STATUS=${result.status.name}');
            previous = result.status;
          }
          if (result.status == QrStatus.authorizing) {
            try {
              final account = await api.authorizeQr(
                result.callbackUrl!,
                session: qr,
              );
              api.credential = account;
              expect(account.valid, isTrue);
              stdout.writeln('MANUAL_MUSIC_CREDENTIAL=SUCCESS');
              try {
                await api.profile(account);
                stdout.writeln('MANUAL_PROFILE=SUCCESS');
              } catch (e) {
                stdout.writeln('MANUAL_PROFILE=UNAVAILABLE');
              }
              final page = await api.search('晴天');
              var playable = false;
              for (final song in page.songs.take(3)) {
                try {
                  final source = await api.source(song, AudioQuality.standard);
                  final mediaClient = http.Client();
                  try {
                    final response = await mediaClient.send(
                      http.Request('GET', source.url)
                        ..headers['Range'] = 'bytes=0-1023',
                    );
                    final contentType = response.headers['content-type'] ?? '';
                    final bytes = await response.stream.first;
                    playable =
                        {200, 206}.contains(response.statusCode) &&
                        bytes.isNotEmpty &&
                        (contentType.startsWith('audio/') ||
                            looksLikeAudio(bytes));
                  } finally {
                    mediaClient.close();
                  }
                  if (playable) break;
                } catch (_) {
                  // A signed CDN URL can appear in transport exceptions. Only
                  // report the outcome; never print an exception with that URL.
                }
              }
              stdout.writeln(
                'MANUAL_AUDIO=${playable ? 'SUCCESS' : 'NO_PERMITTED_SOURCE_IN_SAMPLE'}',
              );
              return;
            } on MusicException catch (e) {
              stdout.writeln('MANUAL_AUTH_FAILED=${e.message}');
              fail(
                'Real QQ music credential exchange failed; do not package yet.',
              );
            }
          }
          if ({QrStatus.expired, QrStatus.refused}.contains(result.status)) {
            fail('Manual QR session ended: ${result.status.name}');
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        fail('Manual scan was not confirmed before timeout');
      } finally {
        api.close();
      }
    },
    skip: !const bool.fromEnvironment('MANUAL_QQ_LOGIN'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
