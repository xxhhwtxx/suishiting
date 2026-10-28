import 'package:flutter_test/flutter_test.dart';
import 'package:music163_core/music163_core.dart';

void main() {
  test(
    '真实GitHub更新源可访问，尚无Release时返回空',
    () async {
      final api = ReleaseApi();
      try {
        final release = await api.latest();
        expect(release == null || release.version.isNotEmpty, isTrue);
      } finally {
        api.close();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_UPDATE_TEST'),
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
