import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/update_models.dart';

class ReleaseApi {
  ReleaseApi({
    this.repository = const String.fromEnvironment(
      'SUISHITING_UPDATE_REPOSITORY',
      defaultValue: 'xxhhwtxx/suishiting',
    ),
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (!RegExp(r'^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const MusicException('更新源配置无效。');
    }
  }
  final String repository;
  final http.Client _client;
  Uri get repositoryUrl => Uri.parse('https://github.com/$repository');
  static const maxApkSize = 256 * 1024 * 1024;

  Future<AppRelease?> latest() async {
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Suishiting-Android',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if ({403, 429}.contains(response.statusCode)) {
      throw const MusicException('更新检查暂时受限，请稍后重试。');
    }
    if (response.statusCode != 200) {
      throw const MusicException('暂时无法检查更新，请稍后重试。');
    }
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const MusicException('更新信息过大，请稍后重试。');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final version = (json['tag_name'] as String? ?? '').replaceFirst(
      RegExp(r'^v'),
      '',
    );
    try {
      compareReleaseVersions(version, version);
    } on FormatException {
      throw const MusicException('新版版本号无法识别，请查看发布页。');
    }
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .where(
          (a) =>
              a['state'] == 'uploaded' &&
              (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
        )
        .toList();
    if (assets.isEmpty) return null;
    final exact = assets
        .where(
          (a) =>
              (a['name'] as String).toLowerCase() ==
              'suishiting-$version.apk'.toLowerCase(),
        )
        .firstOrNull;
    final universal = assets
        .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
        .firstOrNull;
    final asset =
        exact ?? universal ?? (assets.length == 1 ? assets.single : null);
    if (asset == null) throw const MusicException('发布页有多个安装包，请等待发布通用安装包。');
    final size = (asset['size'] as num?)?.toInt() ?? 0;
    final assetId = (asset['id'] as num?)?.toInt() ?? 0;
    final digest = asset['digest'] as String? ?? '';
    if (size <= 0 ||
        size > maxApkSize ||
        assetId <= 0 ||
        !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)) {
      throw const MusicException('新版安装包缺少完整校验信息，请等待发布者重新上传。');
    }
    final url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.toLowerCase().startsWith(
          '/${repository.toLowerCase()}/releases/download/',
        ) ||
        url.userInfo.isNotEmpty) {
      throw const MusicException('更新下载地址无效。');
    }
    final notes = json['body'] as String? ?? '';
    return AppRelease(
      version: version,
      notes: notes.length > 8000 ? notes.substring(0, 8000) : notes,
      size: size,
      pageUrl: Uri.parse(
        'https://github.com/$repository/releases/tag/${Uri.encodeComponent(json['tag_name'] as String)}',
      ),
      downloadUrl: url,
      sha256: digest.substring(7).toLowerCase(),
      assetId: assetId,
    );
  }

  void close() => _client.close();
}
