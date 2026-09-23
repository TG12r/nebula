import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';

class PlayerRepositoryImpl implements PlayerRepository {
  final NebulaAudioHandler _audioHandler;
  final DownloadRepository _downloadRepository;
  final SettingsRepository _settingsRepository;
  final SoundCloudRepository _scRepository;
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  // Full logical queue tracked for UI and Jam sessions
  List<Track> _logicalQueue = [];
  int _currentLogicalIndex = 0;
  int _startLogicalOffset = 0;
  int _bufferedLogicalIndex = 0;
  int _queueGenerationId = 0;

  final BehaviorSubject<List<Track>> _queueController =
      BehaviorSubject<List<Track>>.seeded([]);

  PlayerRepositoryImpl(
    this._audioHandler,
    this._downloadRepository,
    this._settingsRepository,
    this._scRepository,
  ) {
    _initIndexListener();
  }

  void _initIndexListener() {
    _audioHandler.internalPlayer.currentIndexStream.listen((playerIndex) {
      if (playerIndex != null && _logicalQueue.isNotEmpty) {
        final newLogical = _startLogicalOffset + playerIndex;
        if (newLogical >= 0 && newLogical < _logicalQueue.length) {
          _currentLogicalIndex = newLogical;
          _ensureNextBuffered(newLogical, _queueGenerationId);
        }
      }
    });
  }

  @override
  Stream<Duration> get positionStream => AudioService.position;

  @override
  Stream<Duration> get durationStream =>
      _audioHandler.mediaItem.map((item) => item?.duration ?? Duration.zero);

  @override
  Stream<bool> get isPlayingStream =>
      _audioHandler.playbackState.map((state) => state.playing).distinct();

  @override
  Stream<Track?> get currentTrackStream => _audioHandler.mediaItem.map((item) {
    if (item == null) return null;
    return _mediaItemToTrack(item);
  });

  @override
  Stream<List<Track>> get queueStream => _queueController.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => _audioHandler
      .playbackState
      .map((state) => state.processingState)
      .distinct();

  @override
  Future<String?> play(Track track, {bool autoPlay = true}) async {
    try {
      _queueGenerationId++;
      _logicalQueue = [track];
      _currentLogicalIndex = 0;
      _startLogicalOffset = 0;
      _bufferedLogicalIndex = 0;
      _queueController.add(List.unmodifiable(_logicalQueue));

      final source = await _createAudioSource(track);
      if (source == null) return "Could not extract audio URL";

      await _audioHandler.setSourceList([source]);
      if (autoPlay) {
        await _audioHandler.play();
      }
      return null;
    } catch (e) {
      debugPrint("Error in Repo play: $e");
      return "Error: $e";
    }
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int initialIndex = 0}) async {
    _queueGenerationId++;
    final currentId = _queueGenerationId;

    if (tracks.isEmpty) return;

    _logicalQueue = List.from(tracks);
    _currentLogicalIndex = initialIndex.clamp(0, tracks.length - 1);
    _startLogicalOffset = _currentLogicalIndex;
    _bufferedLogicalIndex = _currentLogicalIndex;
    _queueController.add(List.unmodifiable(_logicalQueue));

    // 1. Immediate: Load ONLY the start track to play ASAP (minimal startup latency & CPU)
    final startTrack = _logicalQueue[_currentLogicalIndex];
    final startSource = await _createAudioSource(startTrack);

    if (_queueGenerationId != currentId) return;

    if (startSource != null) {
      await _audioHandler.setSourceList([startSource], initialIndex: 0);

      // 2. Pre-buffer up to 2 tracks ahead (sliding window) to maintain gapless playback
      _preloadUpcomingWindow(_currentLogicalIndex, currentId);

      await _audioHandler.play();
    }
  }

  /// Lazily preloads a small lookahead window (2 tracks ahead)
  Future<void> _preloadUpcomingWindow(int baseIndex, int generationId) async {
    for (int offset = 1; offset <= 2; offset++) {
      final targetIndex = baseIndex + offset;
      if (targetIndex >= _logicalQueue.length) break;
      if (_queueGenerationId != generationId) return;

      final track = _logicalQueue[targetIndex];
      final source = await _createAudioSource(track);
      if (_queueGenerationId != generationId) return;

      if (source != null) {
        await _audioHandler.addAudioSourceToQueue(source);
        _bufferedLogicalIndex = targetIndex;
      }
    }
  }

  /// Incremental buffering as the player advances
  Future<void> _ensureNextBuffered(int currentLogical, int generationId) async {
    final targetIndex = currentLogical + 2;
    if (targetIndex < _logicalQueue.length && targetIndex > _bufferedLogicalIndex) {
      final track = _logicalQueue[targetIndex];
      final source = await _createAudioSource(track);
      if (_queueGenerationId == generationId && source != null) {
        await _audioHandler.addAudioSourceToQueue(source);
        _bufferedLogicalIndex = targetIndex;
      }
    }
  }

  @override
  Future<void> addToQueue(Track track) async {
    _logicalQueue.add(track);
    _queueController.add(List.unmodifiable(_logicalQueue));

    // If queue is near the end, buffer it into player
    if (_logicalQueue.length - 1 <= _currentLogicalIndex + 2) {
      final source = await _createAudioSource(track);
      if (source != null) {
        await _audioHandler.addAudioSourceToQueue(source);
        _bufferedLogicalIndex = _logicalQueue.length - 1;
      }
    }
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _logicalQueue.length) {
      _logicalQueue.removeAt(index);
      _queueController.add(List.unmodifiable(_logicalQueue));

      final internalOffset = index - _startLogicalOffset;
      if (internalOffset >= 0 && internalOffset < _audioHandler.queue.value.length) {
        await _audioHandler.removeQueueItemAt(internalOffset);
      }
    }
  }

  @override
  Future<void> shuffleQueue() async {
    if (_logicalQueue.length <= _currentLogicalIndex + 1) return;

    final upcoming = _logicalQueue.sublist(_currentLogicalIndex + 1)..shuffle();
    _logicalQueue = [
      ..._logicalQueue.sublist(0, _currentLogicalIndex + 1),
      ...upcoming,
    ];
    _queueController.add(List.unmodifiable(_logicalQueue));

    // Re-seed lookahead buffer from the new shuffled order
    _queueGenerationId++;
    await setQueue(_logicalQueue, initialIndex: _currentLogicalIndex);
  }

  @override
  Future<void> skipToNext() async {
    final nextLogical = _currentLogicalIndex + 1;
    if (nextLogical < _logicalQueue.length) {
      final internalIndex = _audioHandler.internalPlayer.currentIndex;
      final sequenceLength = _audioHandler.internalPlayer.sequence?.length ?? 0;
      if (internalIndex != null && internalIndex + 1 < sequenceLength) {
        await _audioHandler.skipToNext();
      } else {
        await setQueue(_logicalQueue, initialIndex: nextLogical);
      }
    } else {
      await _audioHandler.skipToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final prevLogical = _currentLogicalIndex - 1;
    if (prevLogical >= 0) {
      final internalIndex = _audioHandler.internalPlayer.currentIndex;
      if (internalIndex != null && internalIndex > 0) {
        await _audioHandler.skipToPrevious();
      } else {
        await setQueue(_logicalQueue, initialIndex: prevLogical);
      }
    } else {
      await _audioHandler.skipToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _logicalQueue.length) {
      await setQueue(_logicalQueue, initialIndex: index);
    } else {
      await _audioHandler.skipToQueueItem(index);
    }
  }

  @override
  Future<void> pause() => _audioHandler.pause();

  @override
  Future<void> resume() => _audioHandler.play();

  @override
  Future<void> seek(Duration position) => _audioHandler.seek(position);

  @override
  Future<List<Track>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final preferredSource = _settingsRepository.searchSource;

    if (preferredSource == TrackSource.soundcloud) {
      return _scRepository.searchTracks(query);
    }

    try {
      final results = await _yt.search.search(query);
      return results
          .map(
            (v) => Track(
              id: v.id.value,
              title: v.title,
              artist: v.author,
              thumbnailUrl: v.thumbnails.mediumResUrl,
              duration: v.duration ?? Duration.zero,
              source: TrackSource.youtube,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint("Error searching: $e");
      return [];
    }
  }

  @override
  void dispose() {
    _queueController.close();
    _yt.close();
    _audioHandler.stop();
  }

  Track _mediaItemToTrack(MediaItem item) {
    return Track(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown',
      thumbnailUrl: item.artUri.toString(),
      duration: item.duration ?? Duration.zero,
      source: TrackSource.fromId(item.id),
    );
  }

  Future<AudioSource?> _createAudioSource(Track track) async {
    try {
      // 1. Check Offline File
      final localPath = _downloadRepository.getLocalPath(track.id);
      if (localPath != null && File(localPath).existsSync()) {
        final file = File(localPath);
        final fileSize = await file.length();

        if (fileSize < 1024) {
          debugPrint("Warning: Downloaded file too small (${fileSize}B), re-streaming: ${track.title}");
        } else {
          final firstBytes = await file.openRead(0, 10).fold<List<int>>(
            [],
            (prev, chunk) => prev..addAll(chunk),
          );
          final header = String.fromCharCodes(firstBytes).trim();

          if (header.startsWith('#EXTM3U')) {
            debugPrint("Warning: Downloaded file is HLS manifest, re-streaming: ${track.title}");
          } else {
            return AudioSource.file(
              localPath,
              tag: MediaItem(
                id: track.storageId,
                title: track.title,
                artist: track.artist,
                artUri: Uri.parse(track.thumbnailUrl),
                duration: track.duration,
              ),
            );
          }
        }
      }

      // 2. Stream Online
      String? streamUrl;

      if (track.source == TrackSource.soundcloud) {
        streamUrl = await _scRepository.getStreamUrl(track.id);
      } else {
        final manifest = await _yt.videos.streamsClient.getManifest(track.rawId);

        yt_lib.AudioOnlyStreamInfo? audioStream;
        final highQuality = _settingsRepository.highAudioQuality;

        if (highQuality) {
          audioStream = manifest.audioOnly.withHighestBitrate();
        } else {
          final sorted = manifest.audioOnly.sortByBitrate();
          if (sorted.isNotEmpty) {
            audioStream = sorted.first;
          }
        }
        audioStream ??= manifest.audioOnly.withHighestBitrate();
        streamUrl = audioStream.url.toString();
      }

      if (streamUrl == null) return null;

      return AudioSource.uri(
        Uri.parse(streamUrl),
        tag: MediaItem(
          id: track.storageId,
          title: track.title,
          artist: track.artist,
          artUri: Uri.parse(track.thumbnailUrl),
          duration: track.duration,
        ),
      );
    } catch (e) {
      debugPrint("Error extracting audio for ${track.title} (${track.source}): $e");
      return null;
    }
  }
}
