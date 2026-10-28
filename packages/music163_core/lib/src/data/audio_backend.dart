import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as audio;

class AudioEvent {
  const AudioEvent({
    required this.playing,
    required this.loading,
    required this.completed,
    required this.position,
    required this.duration,
  });
  final bool playing;
  final bool loading;
  final bool completed;
  final Duration position;
  final Duration duration;
}

abstract interface class AudioBackend {
  Stream<AudioEvent> get events;
  Stream<Object> get errors;
  Future<void> load(Uri url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> close();
}

class JustAudioBackend implements AudioBackend {
  JustAudioBackend._(this._player) {
    _subscriptions.add(_player.playerStateStream.listen((_) => _emit()));
    _subscriptions.add(_player.positionStream.listen((_) => _emit()));
    _subscriptions.add(_player.durationStream.listen((_) => _emit()));
  }
  static Future<JustAudioBackend> create() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    return JustAudioBackend._(audio.AudioPlayer());
  }

  final audio.AudioPlayer _player;
  final _events = StreamController<AudioEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  void _emit() {
    if (_events.isClosed) return;
    _events.add(
      AudioEvent(
        playing: _player.playing,
        loading: {
          audio.ProcessingState.loading,
          audio.ProcessingState.buffering,
        }.contains(_player.processingState),
        completed: _player.processingState == audio.ProcessingState.completed,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
      ),
    );
  }

  @override
  Stream<AudioEvent> get events => _events.stream;
  @override
  Stream<Object> get errors => _player.errorStream;
  @override
  Future<void> load(Uri url) async {
    await _player.setUrl(url.toString());
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _events.close();
  }
}
