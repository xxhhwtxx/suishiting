import 'dart:convert';
import 'dart:async';
import 'dart:io' show Cookie;
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

int qqHash(String value, [int seed = 0]) {
  var hash = seed;
  for (final c in value.codeUnits) {
    hash = (hash * 33 + c) & 0x7fffffff;
  }
  return hash;
}

class QqCredential {
  QqCredential(Map<String, dynamic> fields) : fields = Map.unmodifiable(fields);
  final Map<String, dynamic> fields;
  String get musicId {
    final stringId = '${fields['str_musicid'] ?? ''}';
    return (int.tryParse(stringId) ?? 0) > 0
        ? stringId
        : '${fields['musicid'] ?? '0'}';
  }

  String get musicKey => fields['musickey'] as String? ?? '';
  int get loginType =>
      ((fields['loginType'] ?? fields['login_type']) as num?)?.toInt() ??
      (musicKey.startsWith('W_X') ? 1 : 2);
  bool get valid =>
      (int.tryParse(musicId) ?? 0) > 0 &&
      musicKey.isNotEmpty &&
      !RegExp(r'[\s;,\r\n]').hasMatch(musicKey);
  bool get canRefresh =>
      '${fields['refresh_token'] ?? ''}'.isNotEmpty ||
      '${fields['refresh_key'] ?? ''}'.isNotEmpty;
  String get cookie =>
      'uin=$musicId; qqmusic_uin=$musicId; qqmusic_key=$musicKey; '
      'qm_keyst=$musicKey; tmeLoginType=$loginType';
  bool get expiresSoon {
    final created =
        ((fields['musickeyCreateTime'] ?? fields['musickey_create_time'])
                as num?)
            ?.toInt() ??
        0;
    final duration =
        ((fields['keyExpiresIn'] ?? fields['key_expires_in']) as num?)
            ?.toInt() ??
        0;
    return created > 0 &&
        duration > 0 &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >=
            created + duration - 300;
  }

  static QqCredential parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty || raw.length > 32768) {
      throw const MusicException('请输入 QQ 音乐 Cookie 或凭据 JSON。');
    }
    Map<String, dynamic> fields;
    try {
      if (raw.startsWith('{')) {
        fields = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (fields['credential'] is Map) {
          fields = Map<String, dynamic>.from(fields['credential'] as Map);
        }
      } else {
        final cookies = <String, String>{};
        for (final part in raw.split(';')) {
          final i = part.indexOf('=');
          if (i > 0) {
            cookies[part.substring(0, i).trim()] = part.substring(i + 1).trim();
          }
        }
        final uin = cookies['qqmusic_uin'] ?? cookies['uin'] ?? '0';
        fields = {
          'str_musicid': uin.replaceFirst(RegExp(r'^o0*'), ''),
          'musickey': cookies['qqmusic_key'] ?? cookies['qm_keyst'] ?? '',
          if (int.tryParse(cookies['tmeLoginType'] ?? '') case final int type)
            'loginType': type,
        };
      }
      // Normalize numeric identifiers before constructing request cookies.
      final stringId = '${fields['str_musicid'] ?? ''}';
      final id = (int.tryParse(stringId) ?? 0) > 0
          ? stringId
          : '${fields['musicid'] ?? '0'}';
      fields['str_musicid'] = '${int.tryParse(id) ?? 0}';
      fields['musicid'] = int.tryParse(id) ?? 0;
      final result = QqCredential(fields);
      if (!result.valid) throw const FormatException();
      return result;
    } catch (_) {
      throw const MusicException(
        '凭据格式无效，需要 QQ 音乐的 musicid 与 musickey；普通 QQ Cookie 不适用。',
      );
    }
  }
}

class QqQrCode {
  QqQrCode(this.bytes, this.sig, {Map<String, String>? cookies})
    : cookies = {...?cookies, 'qrsig': sig};
  final Uint8List bytes;
  final String sig;
  final Map<String, String> cookies;
}

class QqQrResult {
  QqQrResult(this.status, {this.credential, this.callbackUrl});
  final QrStatus status;
  final QqCredential? credential;
  final String? callbackUrl;
}

/// QQ music protocol runs on the device; credentials only go to QQ endpoints.
/// Protocol reference: L-1124/QQMusicApi (GPL-3.0-or-later).
class QqApi {
  QqApi({required this._client});
  final http.Client _client;
  QqCredential? credential;
  Future<void> Function()? beforeAuthorizedRequest;
  final Map<(String, int), Map<String, dynamic>> _searchPages = {};
  static const _referer = 'https://y.qq.com/';
  static const _jump = 'https://graph.qq.com/oauth2.0/login_jump';
  static const _redirect =
      'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/123.0.0.0 Safari/537.36';

  Future<Map<String, dynamic>> call(
    String module,
    String method,
    Map<String, dynamic> param, {
    QqCredential? account,
    bool anonymous = false,
    bool mobile = false,
    int? loginType,
    String? loginCookies,
  }) async {
    final active = anonymous ? null : account ?? credential;
    final gtk = qqHash(active?.musicKey ?? '', 5381);
    final comm = <String, dynamic>{
      'ct': mobile ? 11 : 24,
      'cv': mobile ? 14090008 : 4747474,
      'platform': 'yqq.json',
      'format': 'json',
      'inCharset': 'utf-8',
      'outCharset': 'utf-8',
      'notice': 0,
      'needNewCode': 1,
      'g_tk': gtk,
      'g_tk_new_20200303': gtk,
      'uin': active?.musicId ?? '0',
      if (active != null) ...{'qq': active.musicId, 'authst': active.musicKey},
      if (loginType != null || active != null)
        'tmeLoginType': loginType ?? active!.loginType,
      if (mobile) ...{
        'v': 14090008,
        'chid': '10003505',
        'tmeAppID': 'qqmusic',
        'os_ver': '15',
        'phonetype': 'Android',
        'udid': '0',
        'OpenUDID': '0',
        'QIMEI36': '0',
      },
    };
    final response = await _client
        .post(
          Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: {
            'Content-Type': 'application/json',
            'Referer': _referer,
            'Origin': 'https://y.qq.com',
            'User-Agent': _ua,
            if (active != null)
              'Cookie': active.cookie
            else
              'Cookie': ?loginCookies,
          },
          body: jsonEncode({
            'comm': comm,
            'req_0': {'module': module, 'method': method, 'param': param},
          }),
        )
        .timeout(const Duration(seconds: 20));
    _checkHttp(response);
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final topCode = (root['code'] as num?)?.toInt() ?? -1;
    final item = root['req_0'] as Map<String, dynamic>?;
    final code = (item?['code'] as num?)?.toInt() ?? -1;
    if (topCode != 0 || code != 0) {
      throw MusicException(
        'QQ 音乐请求未获通过（${topCode != 0 ? topCode : code}），请检查登录或稍后重试。',
        code: topCode != 0 ? topCode : code,
      );
    }
    return item?['data'] as Map<String, dynamic>? ?? {};
  }

  Future<SearchPage> search(
    String query, {
    int offset = 0,
    int limit = 20,
  }) async {
    final cursor = offset <= 0 ? null : _searchPages[(query, offset)];
    final data = await call('music.adaptor.SearchAdaptor', 'do_search_v2', {
      'searchid': cursor?['sid'] ?? '${DateTime.now().microsecondsSinceEpoch}',
      'search_type': 100,
      'page_num': limit,
      'query': query,
      'page_id': offset <= 0 ? 1 : offset,
      'highlight': 0,
      'grp': 1,
      if (cursor?['start'] != null) 'page_start': cursor!['start'],
    });
    final body = data['body'] as Map<String, dynamic>? ?? {};
    final group =
        (body['item_song'] ?? data['song']) as Map<String, dynamic>? ?? {};
    final raw = (group['items'] ?? group['list']) as List<dynamic>? ?? [];
    final songs = raw.whereType<Map<String, dynamic>>().map(parseSong).toList();
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final total =
        ((group['total_num'] ?? group['totalnum'] ?? meta['sum']) as num?)
            ?.toInt() ??
        offset + songs.length;
    final next = (meta['nextpage'] as num?)?.toInt();
    if (next != null && next > 0) {
      if (_searchPages.length >= 64) {
        _searchPages.remove(_searchPages.keys.first);
      }
      _searchPages[(query, next)] = {
        'sid': meta['sid'],
        'start': meta['nextpage_start'],
      };
    }
    return SearchPage(
      songs: songs,
      hasMore:
          songs.isNotEmpty && (next == null ? songs.length >= limit : next > 0),
      total: total,
      nextOffset: next ?? (offset <= 0 ? 2 : offset + 1),
    );
  }

  static Song parseSong(Map<String, dynamic> data) {
    final album = data['album'] as Map<String, dynamic>? ?? {};
    final mid = (data['mid'] ?? data['songmid']) as String?;
    if (mid == null || !RegExp(r'^[a-zA-Z0-9]{1,64}$').hasMatch(mid)) {
      throw const MusicException('QQ 音乐返回了无效的歌曲标识。');
    }
    final file = data['file'] as Map<String, dynamic>? ?? {};
    final mediaMid = (file['media_mid'] ?? file['strMediaMid']) as String?;
    final albumMid = (album['mid'] ?? data['albummid']) as String?;
    return Song(
      id: ((data['id'] ?? data['songid']) as num?)?.toInt() ?? 0,
      platform: MusicPlatform.qq,
      mid: mid,
      mediaMid: mediaMid == null || mediaMid.isEmpty ? null : mediaMid,
      songType: (data['type'] as num?)?.toInt() ?? 0,
      name: (data['name'] ?? data['songname']) as String? ?? '未命名歌曲',
      artists: (data['singer'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((a) => a['name'] ?? '')
          .join(' / '),
      album: (album['name'] ?? data['albumname']) as String? ?? '',
      artworkUrl: albumMid == null || albumMid.isEmpty
          ? null
          : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
      duration: Duration(seconds: (data['interval'] as num?)?.toInt() ?? 0),
    );
  }

  Future<Song> song(String value) async {
    final data = await call('music.pf_song_detail_svr', 'get_song_detail_yqq', {
      if (int.tryParse(value) != null)
        'song_id': int.parse(value)
      else
        'song_mid': value,
    });
    return parseSong(data['track_info'] as Map<String, dynamic>? ?? {});
  }

  Future<MediaSource> source(
    Song song,
    AudioQuality quality, {
    bool download = false,
  }) async {
    await beforeAuthorizedRequest?.call();
    final types = switch (quality) {
      AudioQuality.standard => [('M500', 'mp3', 'standard', 128000)],
      AudioQuality.higher => [
        ('M800', 'mp3', 'higher', 320000),
        ('M500', 'mp3', 'standard', 128000),
      ],
      AudioQuality.lossless || AudioQuality.hires => [
        ('F000', 'flac', 'lossless', 0),
        ('M800', 'mp3', 'higher', 320000),
        ('M500', 'mp3', 'standard', 128000),
      ],
    };
    MusicException? lastError;
    for (final type in types) {
      try {
        final data = await call('music.vkey.GetVkey', 'UrlGetVkey', {
          'uin': credential?.musicId ?? '0',
          'filename': [
            '${type.$1}${song.mediaMid ?? '${song.mid}${song.mid}'}.${type.$2}',
          ],
          'guid': '${Random.secure().nextInt(1 << 31)}',
          'songmid': [song.mid],
          'songtype': [song.songType],
          'ctx': 0,
        });
        final info = (data['midurlinfo'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .firstOrNull;
        final path = info?['purl'] as String? ?? '';
        if (path.isEmpty || (info?['result'] as num? ?? 0) != 0) continue;
        final sip = (data['sip'] as List<dynamic>? ?? [])
            .whereType<String>()
            .firstOrNull;
        final url = Uri.parse(
          sip ?? 'https://isure.stream.qqmusic.qq.com/',
        ).resolve(path);
        if (!['https', 'http'].contains(url.scheme) ||
            !url.host.endsWith('.qq.com')) {
          throw const MusicException('QQ 音乐返回的音源地址不受支持。');
        }
        final trial =
            path.split('/').last.startsWith('RS02') || info?['isTry'] == 1;
        if (download && trial) {
          throw const MusicException('此 QQ 音源仅供试听，不能下载为完整歌曲。');
        }
        return MediaSource(
          url: url.replace(scheme: 'https'),
          extension: type.$2,
          level: type.$3,
          bitrate: type.$4,
          isTrial: trial,
        );
      } on MusicException catch (e) {
        lastError = e;
        if (e.code != null && !{1000, 104401, 104400}.contains(e.code)) rethrow;
      }
    }
    if (credential == null) {
      throw const MusicException('该 QQ 曲目没有可用音源，请在设置中登录 QQ 音乐后重试。');
    }
    throw MusicException(
      'QQ 音乐没有返回可用音源，请确认曲目和账号权限，或重新登录。',
      code: lastError?.code,
    );
  }

  Future<String> lyrics(Song song) async {
    final response = await _client
        .get(
          Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
            'songmid': song.mid!,
            'format': 'json',
            'nobase64': '1',
            'g_tk': '5381',
            'inCharset': 'utf-8',
            'outCharset': 'utf-8',
          }),
          headers: {'Referer': _referer, 'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 20));
    _checkHttp(response);
    var text = utf8.decode(response.bodyBytes);
    final start = text.indexOf('{'), end = text.lastIndexOf('}');
    if (start < 0 || end < start) throw const MusicException('QQ 歌词暂时不可用。');
    final data =
        jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    if (data['code'] != 0) throw const MusicException('QQ 歌词暂时不可用。');
    text = data['lyric'] as String? ?? '';
    return text
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m[1]!);
          return code != null && code <= 0x10ffff
              ? String.fromCharCode(code)
              : '';
        });
  }

  Future<AccountProfile> profile(QqCredential account) async {
    final data = await call(
      'music.UserInfo.userInfoServer',
      'GetLoginUserInfo',
      {},
      account: account,
      mobile: true,
    );
    if ((data['code'] as num? ?? 0) != 0) {
      throw const MusicException('QQ 音乐登录已失效，请重新登录。', code: 104401);
    }
    final user =
        (data['userInfo'] ?? data['user_info'] ?? data) as Map<String, dynamic>;
    return AccountProfile(
      id: int.parse(account.musicId),
      nickname:
          (user['nick'] ?? user['nickname'] ?? user['nickName']) as String? ??
          'QQ 音乐用户',
      avatarUrl: (user['headurl'] ?? user['avatarUrl']) as String?,
    );
  }

  QqCredential _loginCredential(
    Map<String, dynamic> data, {
    QqCredential? previous,
  }) {
    if ((data['code'] as num? ?? 0) != 0) {
      throw const MusicException('QQ 音乐登录未获通过，请重新扫码。');
    }
    final fields = data['data'] as Map<String, dynamic>? ?? data;
    // Login replies can omit unchanged OAuth fields on refresh.
    return QqCredential.parse(jsonEncode({...?previous?.fields, ...fields}));
  }

  Future<QqCredential> refresh(QqCredential account) async {
    final f = account.fields;
    final data = await call(
      'music.login.LoginServer',
      'Login',
      {
        for (final k in [
          'openid',
          'refresh_token',
          'refresh_key',
          'access_token',
          'unionid',
        ])
          k: f[k] ?? '',
        'musickey': account.musicKey,
        'musicid': int.parse(account.musicId),
        'str_musicid': account.musicId,
        'expired_in': f['expired_at'] ?? 0,
        'loginMode': 2,
      },
      account: account,
      mobile: true,
    );
    return _loginCredential(data, previous: account);
  }

  Future<QqQrCode> createQr() async {
    final response = await _client
        .get(
          Uri.https('ssl.ptlogin2.qq.com', '/ptqrshow', {
            'appid': '716027609',
            'e': '2',
            'l': 'M',
            's': '3',
            'd': '72',
            'v': '4',
            't': '${Random.secure().nextDouble()}',
            'daid': '383',
            'pt_3rd_aid': '100497308',
          }),
          headers: {
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'User-Agent': _ua,
          },
        )
        .timeout(const Duration(seconds: 20));
    _checkHttp(response);
    final sig = _cookies(response)['qrsig'];
    if (sig == null ||
        response.bodyBytes.length < 8 ||
        !response.bodyBytes
            .take(4)
            .toList()
            .asMap()
            .entries
            .every((e) => e.value == [137, 80, 78, 71][e.key])) {
      throw const MusicException('获取 QQ 登录二维码失败，请重试。');
    }
    return QqQrCode(response.bodyBytes, sig, cookies: _cookies(response));
  }

  Future<QqQrResult> checkQr(QqQrCode qr) async {
    final response = await _client
        .get(
          Uri.https('ssl.ptlogin2.qq.com', '/ptqrlogin', {
            'u1': _jump,
            'ptqrtoken': '${qqHash(qr.sig)}',
            'ptredirect': '0',
            'h': '1',
            't': '1',
            'g': '1',
            'from_ui': '1',
            'ptlang': '2052',
            'action': '0-0-${DateTime.now().millisecondsSinceEpoch}',
            'js_ver': '20102616',
            'js_type': '1',
            'pt_uistyle': '40',
            'aid': '716027609',
            'daid': '383',
            'pt_3rd_aid': '100497308',
            'has_onekey': '1',
          }),
          headers: {
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'Cookie': _cookieHeader(qr.cookies),
            'User-Agent': _ua,
          },
        )
        .timeout(const Duration(seconds: 20));
    _checkHttp(response);
    qr.cookies.addAll(_cookies(response));
    final values = RegExp(
      "'([^']*)'",
    ).allMatches(response.body).map((m) => m[1]!).toList();
    if (values.isEmpty) throw const MusicException('无法读取 QQ 扫码状态，请重新生成二维码。');
    return switch (values.first) {
      '66' => QqQrResult(QrStatus.waiting),
      '67' => QqQrResult(QrStatus.scanned),
      '65' => QqQrResult(QrStatus.expired),
      '68' => QqQrResult(QrStatus.refused),
      '0' when values.length >= 3 => QqQrResult(
        QrStatus.authorizing,
        callbackUrl: values[2],
      ),
      _ => throw const MusicException('QQ 扫码未完成，请重新生成二维码。'),
    };
  }

  Future<http.Response> _noRedirect(http.Request request) async {
    request.followRedirects = false;
    return http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 20)),
    ).timeout(const Duration(seconds: 20));
  }

  Future<QqCredential> authorizeQr(String callback, {QqQrCode? session}) async {
    final uri = Uri.tryParse(callback);
    final uin = uri?.queryParameters['uin'],
        sig = uri?.queryParameters['ptsigx'];
    if (uin == null || sig == null) {
      throw const MusicException('QQ 授权响应不完整，请重试。');
    }
    // Construct a fixed endpoint; never follow the callback URL or leak cookies to redirects.
    final check =
        http.Request(
            'GET',
            Uri.https('ssl.ptlogin2.graph.qq.com', '/check_sig', {
              'uin': uin,
              'pttype': '1',
              'service': 'ptqrlogin',
              'nodirect': '0',
              'ptsigx': sig,
              's_url': _jump,
              'ptlang': '2052',
              'ptredirect': '100',
              'aid': '716027609',
              'daid': '383',
              'j_later': '0',
              'low_login_hour': '0',
              'regmaster': '0',
              'pt_login_type': '3',
              'pt_aid': '0',
              'pt_aaid': '16',
              'pt_light': '0',
              'pt_3rd_aid': '100497308',
            }),
          )
          ..headers.addAll({
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'User-Agent': _ua,
            if (session != null) 'Cookie': _cookieHeader(session.cookies),
          });
    final response = await _authorizationStage(
      '登录态校验',
      () => _noRedirect(check),
    );
    final cookies = {
      ...?session?.cookies,
      ..._cookies(response, forHost: 'graph.qq.com'),
    };
    final skey = cookies['p_skey'];
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw MusicException('QQ 登录态校验失败（HTTP ${response.statusCode}），请重新扫码。');
    }
    if (skey == null || skey.isEmpty) {
      throw const MusicException('QQ 授权未返回登录凭据，请重新扫码。');
    }
    final auth =
        http.Request(
            'POST',
            Uri.parse('https://graph.qq.com/oauth2.0/authorize'),
          )
          ..headers.addAll({
            'Cookie': _cookieHeader(cookies),
            'Referer': _jump,
            'Origin': 'https://graph.qq.com',
            'User-Agent': _ua,
          })
          ..bodyFields = {
            'response_type': 'code',
            'client_id': '100497308',
            'redirect_uri': _redirect,
            'scope': 'get_user_info,get_app_friends',
            'state': 'state',
            'switch': '',
            'from_ptlogin': '1',
            'src': '1',
            'update_auth': '1',
            'openapi': '1010_1030',
            'g_tk': '${qqHash(skey, 5381)}',
            'auth_time': '${DateTime.now().millisecondsSinceEpoch}',
            'ui': _uuid(),
          };
    final authorized = await _authorizationStage(
      '音乐授权',
      () => _noRedirect(auth),
    );
    cookies.addAll(_cookies(authorized));
    final code = Uri.tryParse(
      authorized.headers['location'] ?? '',
    )?.queryParameters['code'];
    if (code == null || ![301, 302, 303].contains(authorized.statusCode)) {
      throw const MusicException('QQ 音乐授权失败，请重新扫码并确认授权。');
    }
    return _authorizationStage(
      '音乐凭据获取',
      () async => _loginCredential(
        await call(
          'QQConnectLogin.LoginServer',
          'QQLogin',
          {'code': code},
          anonymous: true,
          loginType: 2,
          loginCookies: _cookieHeader(cookies),
        ),
      ),
    );
  }

  Future<T> _authorizationStage<T>(
    String stage,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on MusicException catch (e) {
      throw MusicException('QQ $stage失败：${e.message}', code: e.code);
    } on TimeoutException {
      throw MusicException('QQ $stage请求超时，请重新获取二维码再试。');
    } on http.ClientException {
      throw MusicException('QQ $stage网络请求失败，请检查网络后重试。');
    } on FormatException {
      throw MusicException('QQ $stage响应无法识别，请重新扫码。');
    }
  }

  String _cookieHeader(Map<String, String> cookies) => cookies.entries
      .where(
        (e) => !{
          'path',
          'domain',
          'expires',
          'max-age',
          'samesite',
        }.contains(e.key.toLowerCase()),
      )
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Map<String, String> _cookies(http.Response response, {String? forHost}) {
    final origin = response.request?.url.host ?? forHost ?? '';
    final target = (forHost ?? origin).toLowerCase();
    final scoped = <(String, String, String), Cookie>{};
    // A folded Set-Cookie contains commas inside Expires. Split only at a new
    // cookie name. A deletion for .qq.com must not erase a live p_skey scoped
    // to .graph.qq.com, even though their names are identical.
    for (final raw in (response.headers['set-cookie'] ?? '').split(
      RegExp(r',(?=\s*[\w-]+=)'),
    )) {
      if (raw.trim().isEmpty) continue;
      try {
        final cookie = Cookie.fromSetCookieValue(raw.trim());
        final domain = (cookie.domain ?? origin).toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        scoped[(cookie.name, domain, cookie.path ?? '/')] = cookie;
      } on FormatException {
        /* Ignore an invalid attribute, not other cookies. */
      }
    }
    final eligible = scoped.entries.where((e) {
      final cookie = e.value, domain = e.key.$2;
      final matches =
          target.isEmpty ||
          domain.isEmpty ||
          target == domain ||
          cookie.domain != null && target.endsWith('.$domain');
      return matches &&
          cookie.value.isNotEmpty &&
          (cookie.maxAge == null || cookie.maxAge! > 0) &&
          (cookie.expires == null || cookie.expires!.isAfter(DateTime.now()));
    }).toList()..sort((a, b) => a.key.$2.length.compareTo(b.key.$2.length));
    return {for (final entry in eligible) entry.value.name: entry.value.value};
  }

  void _checkHttp(http.Response response) {
    if (response.statusCode != 200) {
      throw MusicException('QQ 音乐网络请求失败（${response.statusCode}）。');
    }
  }

  void close() => _client.close();
}
