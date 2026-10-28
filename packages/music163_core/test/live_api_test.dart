import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

void main() {
  test(
    '真实网易云接口：匿名搜索、歌曲详情、歌词及二维码 key',
    () async {
      final api = NeteaseApi(
        client: http.Client(),
        deviceId: 'music163-flutter-live-test',
      );
      final repository = MusicRepository(api);
      try {
        final result = await repository.search('晴天', limit: 2);
        expect(result.songs, isNotEmpty);
        final song = await repository.song(result.songs.first.id);
        expect(song.id, result.songs.first.id);
        await repository.lyrics(song.id);
        final qr = await api.request('/api/login/qrcode/unikey', {
          'type': '3',
        }, anonymous: true);
        expect(qr.json['unikey'], isA<String>());
      } finally {
        api.close();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_API_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
