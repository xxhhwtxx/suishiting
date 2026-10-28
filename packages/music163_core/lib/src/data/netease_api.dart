// EAPI protocol ported from XiaoMengXinX/Music163Api-Go (GPL-3.0).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../domain/models.dart';

String encodeEapi(String path, Map<String, dynamic> payload) {
  final json = jsonEncode(payload);
  final digest = md5.convert(
    utf8.encode('nobody${path}use${json}md5forencrypt'),
  );
  final text = '$path-36cd479b6b5-$json-36cd479b6b5-$digest';
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    ECBBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters<KeyParameter, Null>(
      KeyParameter(Uint8List.fromList(utf8.encode('e82ckenh8dichen8'))),
      null,
    ),
  );
  return cipher
      .process(Uint8List.fromList(utf8.encode(text)))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

class ApiReply {
  const ApiReply(this.json, this.setCookie);
  final Map<String, dynamic> json;
  final String? setCookie;
}

class NeteaseApi {
  NeteaseApi({
    required this._client,
    required this.deviceId,
    this.timeout = const Duration(seconds: 20),
  });
  final http.Client _client;
  final String deviceId;
  final Duration timeout;
  String? musicU;

  Future<ApiReply> request(
    String path,
    Map<String, dynamic> payload, {
    bool anonymous = false,
    String? credential,
    Set<int> allowedCodes = const {200},
  }) async {
    if (!path.startsWith('/api/')) throw ArgumentError('Invalid API path');
    final cookies = <String, String>{
      'os': 'Android',
      'appver': '9.3.40',
      'deviceId': deviceId,
      'resolution': '1920x1080',
    };
    final token = credential ?? musicU;
    if (!anonymous && token != null) cookies['MUSIC_U'] = token;
    try {
      final abort = Completer<void>();
      final request = http.AbortableRequest(
        'POST',
        Uri.https('music.163.com', '/eapi${path.substring(4)}'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': 'https://music.163.com/',
        'User-Agent':
            'NeteaseMusic/9.3.40.1753206443(164);Dalvik/2.1.0 (Linux; U; Android 9)',
        'Cookie': cookies.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('; '),
      });
      request.body = 'params=${encodeEapi(path, payload)}';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('API request timed out');
            },
          );
      if (response.statusCode != 200) {
        throw MusicException(
          '网易云请求失败（HTTP ${response.statusCode}），请稍后重试。',
          code: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final code = (decoded['code'] as num?)?.toInt();
      if (code == null || !allowedCodes.contains(code)) {
        if (code == 301 || code == 302) {
          throw MusicException('网易云登录已失效，请重新登录。', code: code);
        }
        if (code == -462 || code == 405) {
          throw MusicException('网易云暂时限制了请求，请稍后重试或切换网络。', code: code);
        }
        throw MusicException('网易云未能完成请求（${code ?? "未知状态"}），请重试。', code: code);
      }
      return ApiReply(decoded, response.headers['set-cookie']);
    } on TimeoutException {
      throw const MusicException('请求超时，请检查网络后重试。');
    } on SocketException {
      throw const MusicException('无法连接网易云，请检查网络。');
    } on http.ClientException {
      throw const MusicException('网络连接中断，请重试。');
    } on FormatException {
      throw const MusicException('网易云返回的数据格式异常，请稍后重试。');
    }
  }

  Future<Uri> resolveShortLink(Uri link) async {
    var current = link;
    for (var i = 0; i < 6; i++) {
      if (!isMusicLink(current)) throw const MusicException('此链接不是网易云音乐链接。');
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await _client.send(request).timeout(timeout);
      final location = response.headers['location'];
      // Cancel the body rather than buffering arbitrary redirect pages.
      await response.stream.listen((_) {}).cancel();
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null) {
        current = current.resolve(location);
        continue;
      }
      return current;
    }
    throw const MusicException('分享链接跳转次数过多，请粘贴歌曲 ID 或完整链接。');
  }

  void close() => _client.close();
}

bool isMusicLink(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.userInfo.isEmpty &&
    (uri.host == 'music.163.com' ||
        uri.host.endsWith('.music.163.com') ||
        uri.host == '163cn.tv' ||
        uri.host == '163cn.link');

int? songIdFromInput(String input) {
  final text = input.trim();
  if (RegExp(r'^\d{1,16}$').hasMatch(text)) {
    final id = int.tryParse(text);
    return id != null && id > 0 ? id : null;
  }
  final match = RegExp(r'https?://[^\s<>"“”]+').firstMatch(text);
  if (match == null) return null;
  final uri = Uri.tryParse(match.group(0)!);
  if (uri == null || !isMusicLink(uri)) return null;
  final fragment = Uri.tryParse(uri.fragment);
  final route = uri.path.contains('song') ? uri : fragment;
  if (route == null || !RegExp(r'(^|/)song/?$').hasMatch(route.path)) {
    return null;
  }
  final id = int.tryParse(route.queryParameters['id'] ?? '');
  return id != null && id > 0 ? id : null;
}
