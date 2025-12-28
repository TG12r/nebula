import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class NebulaAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  NebulaAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Broadcast MediaItem (Title, Artist, Art)
    _player.sequenceStateStream.listen((sequenceState) {
      final sequence = sequenceState?.sequence;
      if (sequence == null || sequence.isEmpty) return;
      final tag = sequenceState!.currentSource!.tag as MediaItem;
      mediaItem.add(tag);
    });

    // Unified State Broadcaster
    void broadcastState([PlaybackEvent? event]) {
      final playing = _player.playing;
      final queueIndex = event?.currentIndex ?? _player.currentIndex;

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: queueIndex,
        ),
      );
    }

    // Listen to all relevant streams
    _player.playbackEventStream.listen(broadcastState);
    _player.playingStream.listen((_) => broadcastState());
    _player.processingStateStream.listen((_) => broadcastState());
  }

  // --- Public Methods for Repository ---

  AudioPlayer get internalPlayer => _player;

  Future<void> setSource(AudioSource source) async {
    await _player.setAudioSource(source);
  }

  // --- BaseAudioHandler Overrides (System Controls) ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();
}
