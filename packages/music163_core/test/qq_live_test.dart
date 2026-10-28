import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

void main() {
  test(
    '真实QQ接口：搜索、翻页、详情、歌词、登录二维码',
    () async {
      final api = QqApi(client: http.Client());
      try {
        final first = await api.search('晴天');
        expect(first.songs, isNotEmpty);
        expect(first.songs.first.platform, MusicPlatform.qq);
        final detail = await api.song(first.songs.first.mid!);
        expect(detail.mid, first.songs.first.mid);
        final second = await api.search('晴天', offset: first.nextOffset!);
        expect(second.songs, isNotEmpty);
        expect(
          second.songs.map((s) => s.key).toList(),
          isNot(first.songs.map((s) => s.key).toList()),
        );
        final lrc = await api.lyrics(detail);
        expect(lrc, contains('['));
        final qr = await api.createQr();
        expect(qr.bytes.length, greaterThan(100));
        final status = await api.checkQr(qr);
        expect(status.status, QrStatus.waiting);
      } finally {
        api.close();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_QQ_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
