import 'dart:async';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class NebulaAudioHandler extends BaseAudioHandler {
  static const String jamKeepaliveMediaId = '__nebula_jam_keepalive__';

  final _player = AudioPlayer();

  // Playlist Source
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  bool _isJamSessionActive = false;
  String? _activeJamCode;

  NebulaAudioHandler() {
    _init();
  }

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _player.playing;
    final queueIndex = event?.currentIndex ?? _player.currentIndex;
    final rawState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState]!;

    // Keep Android Foreground Service & WakeLock active while in a Jam session
    // even when no song is playing yet (ProcessingState.idle).
    final effectiveState = (_isJamSessionActive &&
            rawState == AudioProcessingState.idle)
        ? AudioProcessingState.ready
        : rawState;

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
        processingState: effectiveState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex,
      ),
    );
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

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

    // Listen to all relevant streams (with onError so Windows native E_ABORT /
    // "Operación anulada" events on track switches or clearQueue never crash the app)
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint(
          'NebulaAudioHandler: playbackEventStream error (handled): $e',
        );
      },
    );
    _player.playingStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) {},
    );
    _player.processingStateStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) {},
    );
  }

  /// Activates or deactivates background Foreground Service keepalive for Jam sessions.
  void setJamSessionActive(bool active, {String? jamCode}) {
    _isJamSessionActive = active;
    _activeJamCode = jamCode;

    if (active) {
      if (mediaItem.value == null) {
        mediaItem.add(
          MediaItem(
            id: jamKeepaliveMediaId,
            title: 'Jam Session (${jamCode ?? "LIVE"})',
            artist: 'Connected in background',
          ),
        );
      }
    } else {
      if (mediaItem.value?.id == jamKeepaliveMediaId) {
        mediaItem.add(null);
      }
    }
    _broadcastState();
  }

  // --- Public Methods for Repository ---

  AudioPlayer get internalPlayer => _player;

  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  int? get currentIndex => _player.currentIndex;

  bool get hasAudioSource => _player.audioSource != null;

  int get sequenceLength => _player.sequence?.length ?? 0;

  /// Sets a list of sources as the current queue and plays the first one (or index)
  Future<void> setSourceList(
    List<AudioSource> sources, {
    int initialIndex = 0,
  }) async {
    if (sources.isNotEmpty &&
        initialIndex >= 0 &&
        initialIndex < sources.length) {
      final src = sources[initialIndex];
      if (src is IndexedAudioSource && src.tag is MediaItem) {
        mediaItem.add(src.tag as MediaItem);
      }
    }

    // Create a fresh ConcatenatingAudioSource so just_audio_windows performs a
    // single clean load instead of mutating an attached playlist (removeRange +
    // insertAll) and immediately aborting it with a second load() call.
    final nextPlaylist = ConcatenatingAudioSource(
      children: List<AudioSource>.from(sources),
    );
    _playlist = nextPlaylist;

    try {
      await _player.setAudioSource(
        nextPlaylist,
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('abort') || msg.contains('anulada')) {
        debugPrint(
          'NebulaAudioHandler: setSourceList superseded/aborted cleanly: $e',
        );
        return;
      }
      rethrow;
    }
    _broadcastQueue();
  }

  /// Adds a single source to the end of the queue
  Future<void> addAudioSourceToQueue(AudioSource source) async {
    try {
      await _playlist.add(source);
      if (_player.audioSource == null) {
        await _player.setAudioSource(_playlist);
      }
      _broadcastQueue();
    } catch (e) {
      debugPrint('NebulaAudioHandler: addAudioSourceToQueue error: $e');
    }
  }

  /// Removes item at index
  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index >= 0 && index < _playlist.length) {
      try {
        await _playlist.removeAt(index);
        _broadcastQueue();
      } catch (e) {
        debugPrint('NebulaAudioHandler: removeQueueItemAt error: $e');
      }
    }
  }

  /// Removes all pre-buffered sources after [internalIndex] without interrupting the active track.
  Future<void> removeUpcomingSourcesAfter(int internalIndex) async {
    if (internalIndex < 0) return;
    try {
      while (_playlist.length > internalIndex + 1) {
        await _playlist.removeAt(_playlist.length - 1);
      }
      _broadcastQueue();
    } catch (e) {
      debugPrint('NebulaAudioHandler: removeUpcomingSourcesAfter error: $e');
    }
  }

  /// Clears all items from the playlist and stops playback.
  Future<void> clearPlaylist() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('NebulaAudioHandler: stop() during clearPlaylist ignored: $e');
    }
    try {
      await _playlist.clear();
    } catch (e) {
      debugPrint(
        'NebulaAudioHandler: playlist.clear() during clearPlaylist ignored: $e',
      );
    }
    if (_isJamSessionActive) {
      mediaItem.add(
        MediaItem(
          id: jamKeepaliveMediaId,
          title: 'Jam Session (${_activeJamCode ?? "LIVE"})',
          artist: 'Connected in background',
        ),
      );
    } else {
      mediaItem.add(null);
    }
    _broadcastQueue();
    _broadcastState();
  }

  void _broadcastQueue() {
    final sequence = _playlist.sequence;
    // Don't filter empty here, otherwise we can't clear queue in UI
    final newQueue = sequence.map((source) => source.tag as MediaItem).toList();
    queue.add(newQueue);
  }

  // --- BaseAudioHandler Overrides (System Controls) ---

  @override
  Future<void> play() async {
    // AudioPlayer.play() in just_audio returns a Future that only completes
    // when playback finishes or is paused/stopped. Using unawaited ensures
    // callers (setQueue, playTrack, Jam sync) do not deadlock for the track duration.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    if (_player.audioSource == null) return;
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint("Warning: seek failed on internal player: $e");
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  Future<void> shuffleStringQueue() async {
    final currentIndex = _player.currentIndex;
    if (currentIndex == null) return;

    final sequence = _playlist.sequence;
    if (currentIndex >= sequence.length - 1) return; // Nothing to shuffle after

    final int start = currentIndex + 1;
    for (int i = start; i < sequence.length - 1; i++) {
      int k = i + Random().nextInt(sequence.length - i);
      if (k != i) await _playlist.move(k, i);
    }
  }
}
