// Optional local visual QA; no network, no real account, no platform plugins.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_app/main.dart';
import 'package:music163_core/music163_core.dart' hide SearchController;

class _Store implements CredentialStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Audio implements AudioBackend {
  @override
  Stream<AudioEvent> get events => const Stream.empty();
  @override
  Stream<Object> get errors => const Stream.empty();
  @override
  Future<void> load(Uri url) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('手机浅深色、大字体及平板布局截图', (tester) async {
    final key = GlobalKey();
    Directory? temp;
    Music163Core? core;
    const output = String.fromEnvironment(
      'PREVIEW_DIR',
      defaultValue: '../previews',
    );
    await tester.runAsync(() async {
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            r'C:\Windows\Fonts\msyh.ttc',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      final fallback = FontLoader('Ahem')
        ..addFont(
          File(
            r'C:\Windows\Fonts\msyh.ttc',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await fallback.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            r'D:\flutter-sdk\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
      temp = await Directory.systemTemp.createTemp('music163_visual_');
      await Directory(output).create(recursive: true);
      core = await Music163Core.create(
        credentialStore: _Store(),
        audioBackend: _Audio(),
        downloadDirectory: temp,
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 200,
                'result': {
                  'songCount': 2,
                  'hasMore': false,
                  'songs': [
                    {
                      'id': 1,
                      'name': '海边的晚风（界面测试曲目）',
                      'ar': [
                        {'name': '示例歌手'},
                      ],
                      'al': {'name': '界面检查'},
                      'dt': 216000,
                    },
                    {
                      'id': 2,
                      'name': '漫长旅途里的短暂休息',
                      'ar': [
                        {'name': '示例乐队'},
                      ],
                      'al': {'name': '测试专辑'},
                      'dt': 198000,
                    },
                  ],
                },
              }),
            ),
            200,
          ),
        ),
      );
    });
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MyApp(core: core),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '$output/phone-light-search.png');
      await core!.search.search('海边');
      await tester.pumpAndSettle();
      await _capture(tester, key, '$output/phone-light-results.png');
      await tester.tap(find.byKey(const Key('nav_tab_account')));
      await tester.pumpAndSettle();
      await _capture(tester, key, '$output/phone-light-account.png');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      await tester.pumpAndSettle();
      await _capture(tester, key, '$output/phone-dark-large-text.png');
      tester.view.physicalSize = const Size(900, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      await _capture(tester, key, '$output/tablet-dark-account.png');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await core?.close();
        await temp?.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
  }, skip: !const bool.fromEnvironment('UI_PREVIEW'));
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
