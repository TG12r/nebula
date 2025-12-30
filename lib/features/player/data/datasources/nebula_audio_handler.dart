import 'dart:async';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class NebulaAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  // Playlist Source
  final _playlist = ConcatenatingAudioSource(children: []);

  NebulaAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Load empty playlist to start (or handle initial load differently)
    // We don't set source here immediately to avoid empty playlist error if not handled
    // But usually we want the player to be ready.
    // For now, we wait for the first 'play' or 'setQueue' to set the source.

    // Broadcast MediaItem (Title, Artist, Art)
    _player.sequenceStateStream.listen((sequenceState) {
      // 1. Update Queue (Force refresh from source of truth)
      _broadcastQueue();

      // 2. Update Current MediaItem
      final tag = sequenceState?.currentSource?.tag as MediaItem?;
      if (tag != null) {
        mediaItem.add(tag);
      }
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

  /// Sets a list of sources as the current queue and plays the first one (or index)
  Future<void> setSourceList(
    List<AudioSource> sources, {
    int initialIndex = 0,
  }) async {
    await _playlist.clear();
    await _playlist.addAll(sources);
    await _player.setAudioSource(
      _playlist,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );
    _broadcastQueue();
  }

  /// Adds a single source to the end of the queue
  Future<void> addAudioSourceToQueue(AudioSource source) async {
    await _playlist.add(source);
    // If player was idle (empty queue), this might need to trigger source setting?
    // If _player has _playlist set, adding to it works dynamically.
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlist);
    }
    _broadcastQueue();
  }

  /// Removes item at index
  @override
  Future<void> removeQueueItemAt(int index) async {
    await _playlist.removeAt(index);
    _broadcastQueue();
  }

  void _broadcastQueue() {
    final sequence = _playlist.sequence;
    // Don't filter empty here, otherwise we can't clear queue in UI
    final newQueue = sequence.map((source) => source.tag as MediaItem).toList();
    queue.add(newQueue);
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

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  Future<void> shuffleStringQueue() async {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null) return;

    final sequence = _playlist.sequence;
    if (currentIndex >= sequence.length - 1) return; // Nothing to shuffle after

    // We can't easily extract "AudioSource" objects back out to move them freely without re-creating them or careful management.
    // However, ConcatenatingAudioSource allows `move(from, to)`.
    // Easier strategy: Get the list of indices to come (currentIndex + 1 to end).
    // Shuffle that list of indices.
    // Apply moves? Moving changes indices, so simple iteration is tricky.

    // Robust Strategy:
    // 1. Snapshot the *tags* (MediaItems) of the upcoming tracks.
    // 2. Clear upcoming tracks.
    // 3. Re-create AudioSources from tags? No, we lose the source reference.

    // Correct Just_Audio strategy for "Hard Shuffle":
    // Use `setShuffleOrder` if we only wanted logical shuffle.
    // But for "Queue Shuffle" (Spotify style where the list changes):
    // We must move items.
    // Let's perform a simple "Fisher-Yates" style shuffle using `move()`.
    // Range: [start, end] = [currentIndex + 1, sequence.length - 1]

    final int start = currentIndex + 1;
    // final int end = sequence.length; // Not used explicitly in loop condition

    // We need to move items around.
    // To safe complexity, we'll try `ShuffleOrder` approach?
    // User asked: "Si empiezo... y lo activo se haga shuffle a la cola".
    // This usually implies the *visible* order changes.

    // Standard workaround:
    // Manual Shuffle by moving each item to a random position in the remaining range.
    // Iterate from start to end-2. Pick random k from i to end. Move k to i.
    for (int i = start; i < sequence.length - 1; i++) {
      int k = i + Random().nextInt(sequence.length - i);
      if (k != i) await _playlist.move(k, i);
    }
  }
}
