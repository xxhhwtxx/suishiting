import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'controllers/auth_controller.dart';
import 'controllers/qq_auth_controller.dart';
import 'controllers/update_controller.dart';
import 'controllers/base_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/player_controller.dart';
import 'controllers/search_controller.dart';
import 'data/audio_backend.dart';
import 'data/credentials.dart';
import 'data/music_repository.dart';
import 'data/netease_api.dart';
import 'data/qq_api.dart';
import 'domain/models.dart';

class Music163Core extends SafeNotifier {
  Music163Core._({
    required this.repository,
    required this.search,
    required this.auth,
    required this.qqAuth,
    required this.updates,
    required this.player,
    required this.downloads,
    required this._store,
  });
  final MusicRepository repository;
  final SearchController search;
  final AuthController auth;
  final QqAuthController qqAuth;
  final UpdateController updates;
  final PlayerController player;
  final DownloadController downloads;
  final CredentialStore _store;
  AudioQuality get quality => repository.quality;

  static Future<Music163Core> create({
    CredentialStore? credentialStore,
    http.Client? client,
    http.Client? qqClient,
    UpdateController? updater,
    AudioBackend? audioBackend,
    Directory? downloadDirectory,
  }) async {
    final store = credentialStore ?? SecureCredentialStore();
    var deviceId = await store.read('music163.device_id');
    if (deviceId == null) {
      final random = Random.secure();
      deviceId = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      await store.write('music163.device_id', deviceId);
    }
    final api = NeteaseApi(client: client ?? http.Client(), deviceId: deviceId);
    final qqApi = QqApi(client: qqClient ?? client ?? http.Client());
    AudioBackend? backend;
    Music163Core? core;
    try {
      final repository = MusicRepository(api, qqApi: qqApi);
      final savedQuality = await store.read('music163.quality');
      repository.quality =
          AudioQuality.values
              .where((q) => q.name == savedQuality)
              .firstOrNull ??
          AudioQuality.higher;
      backend = audioBackend ?? await JustAudioBackend.create();
      final directory =
          downloadDirectory ??
          Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'music163_downloads',
            ),
          );
      core = Music163Core._(
        repository: repository,
        search: SearchController(repository),
        auth: AuthController(api, store),
        qqAuth: QqAuthController(qqApi, store),
        updates: updater ?? UpdateController(),
        player: PlayerController(repository, backend),
        downloads: DownloadController(repository, directory),
        store: store,
      );
      await core.downloads.restore();
      await core.auth.restore();
      await core.qqAuth.restore();
      return core;
    } catch (_) {
      if (core != null) {
        await core.close();
      } else {
        await backend?.close();
        api.close();
        qqApi.close();
      }
      rethrow;
    }
  }

  Future<void> _settingsWrites = Future.value();
  Future<void> setQuality(AudioQuality value) {
    if (closed) return Future.value();
    final next = _settingsWrites.catchError((Object _) {}).then((_) async {
      if (closed) return;
      try {
        await _store.write('music163.quality', value.name);
      } catch (_) {
        throw const MusicException('音质设置保存失败，请重试。');
      }
      if (!closed) {
        repository.quality = value;
        changed();
      }
    });
    _settingsWrites = next;
    return next;
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _settingsWrites.catchError((Object _) {});
    auth.dispose();
    qqAuth.dispose();
    await updates.close();
    search.dispose();
    await player.close();
    await downloads.close();
    repository.api.close();
    repository.qqApi?.close();
    dispose();
  }
}
