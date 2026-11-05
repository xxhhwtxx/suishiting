import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music163_core/music163_core.dart';
import 'package:music163_app/ui/widgets/player_bar.dart';

class _Store implements CredentialStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _Audio implements AudioBackend {
  final updates = StreamController<AudioEvent>.broadcast();
  bool playing = false;
  void emit() => updates.add(
    AudioEvent(
      playing: playing,
      loading: false,
      completed: false,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    ),
  );
  @override
  Stream<AudioEvent> get events => updates.stream;
  @override
  Stream<Object> get errors => const Stream.empty();
  @override
  Future<void> load(Uri url) async {
    emit();
  }

  @override
  Future<void> play() async {
    playing = true;
    emit();
  }

  @override
  Future<void> pause() async {
    playing = false;
    emit();
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> close() => updates.close();
}

void main() {
  testWidgets('正在播放时打开完整播放页，歌词同步不会把大封面滚出屏幕', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory directory;
    late Music163Core core;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('suishiting_cover_');
      core = await Music163Core.create(
        credentialStore: _Store(),
        audioBackend: _Audio(),
        downloadDirectory: directory,
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 200,
                'lrc': {'lyric': '[00:00.00]第一句\n[00:12.00]第二句\n[00:24.00]第三句'},
              }),
            ),
            200,
          ),
        ),
      );
      final audioFile = File('${directory.path}/test.mp3');
      await audioFile.writeAsBytes([73, 68, 51, 0]);
      await core.player.playLocal(
        const Song(id: 1, name: '界面验证', artists: '歌手', album: '专辑'),
        audioFile.path,
      );
      await Future<void>.delayed(Duration.zero);
    });
    try {
      expect(core.player.isPlaying, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => NowPlayingSheet(core: core),
                ),
                child: const Text('打开播放器'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开播放器'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      final artwork = find.byKey(const Key('now_playing_large_artwork'));
      expect(artwork, findsOneWidget);
      expect(tester.getRect(artwork).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(artwork).bottom, lessThanOrEqualTo(844));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await core.close();
        await directory.delete(recursive: true);
      });
    }
  });
}
