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
import 'package:nebula/core/services/innertube_search_service.dart';
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';

class PlayerRepositoryImpl implements PlayerRepository {
  final NebulaAudioHandler _audioHandler;
  final DownloadRepository _downloadRepository;
  final SettingsRepository _settingsRepository;
  final SoundCloudRepository _scRepository;
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();
  final InnerTubeSearchService _innerTube = InnerTubeSearchService();

  // Full logical queue tracked for UI and Jam sessions
  List<Track> _logicalQueue = [];
  int _currentLogicalIndex = 0;
  int _startLogicalOffset = 0;
  int _bufferedLogicalIndex = 0;
  int _queueGenerationId = 0;
  bool _isSettingQueue = false;

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
    _audioHandler.currentIndexStream.listen((playerIndex) {
      if (_isSettingQueue) return;
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
    if (item == null || item.id == NebulaAudioHandler.jamKeepaliveMediaId) {
      return null;
    }
    return _mediaItemToTrack(item);
  });

  @override
  Stream<List<Track>> get queueStream => _queueController.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => _audioHandler
      .playbackState
      .map((state) => state.processingState)
      .distinct();

  bool _isLocalFileSource(AudioSource source) {
    return source is UriAudioSource && source.uri.isScheme('file');
  }

  Uri? _parseArtUri(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    return Uri.tryParse(trimmed);
  }

  @override
  Future<String?> play(Track track, {bool autoPlay = true}) async {
    try {
      _queueGenerationId++;
      final currentId = _queueGenerationId;
      _isSettingQueue = true;
      _logicalQueue = [track];
      _currentLogicalIndex = 0;
      _startLogicalOffset = 0;
      _bufferedLogicalIndex = 0;
      _queueController.add(List.unmodifiable(_logicalQueue));

      AudioSource? source = await _createAudioSource(track);
      if (_queueGenerationId != currentId) return null;
      if (source == null) return "Could not extract audio URL";

      try {
        await _audioHandler.setSourceList([source]);
      } catch (e) {
        if (_isLocalFileSource(source)) {
          debugPrint(
            "Local file playback failed for ${track.title} ($e). Deleting corrupted download and falling back to online stream.",
          );
          await _downloadRepository.deleteTrack(track.id);
          if (_queueGenerationId != currentId) return null;
          source = await _createAudioSource(track, allowLocal: false);
          if (_queueGenerationId != currentId) return null;
          if (source == null) return "Could not extract audio URL";
          await _audioHandler.setSourceList([source]);
        } else {
          rethrow;
        }
      }

      if (autoPlay) {
        await _audioHandler.play();
      } else {
        await _audioHandler.pause();
      }
      return null;
    } catch (e) {
      debugPrint("Error in Repo play: $e");
      return "Error: $e";
    } finally {
      _isSettingQueue = false;
    }
  }

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    _queueGenerationId++;
    final currentId = _queueGenerationId;

    if (tracks.isEmpty) return;

    _isSettingQueue = true;
    _logicalQueue = List.from(tracks);
    _currentLogicalIndex = initialIndex.clamp(0, tracks.length - 1);
    _startLogicalOffset = _currentLogicalIndex;
    _bufferedLogicalIndex = _currentLogicalIndex;
    _queueController.add(List.unmodifiable(_logicalQueue));

    try {
      // 1. Immediate: Load ONLY the start track to play ASAP (minimal startup latency & CPU)
      bool loaded = false;

      while (!loaded && _currentLogicalIndex < _logicalQueue.length) {
        if (_queueGenerationId != currentId) return;
        final startTrack = _logicalQueue[_currentLogicalIndex];
        final startSource = await _createAudioSource(startTrack);
        if (_queueGenerationId != currentId) return;

        if (startSource != null) {
          try {
            _startLogicalOffset = _currentLogicalIndex;
            await _audioHandler.setSourceList([startSource], initialIndex: 0);
            loaded = true;
          } catch (e) {
            if (_isLocalFileSource(startSource)) {
              debugPrint(
                "Local file playback failed for ${startTrack.title} ($e). Deleting corrupted download and falling back to online stream.",
              );
              await _downloadRepository.deleteTrack(startTrack.id);
              if (_queueGenerationId != currentId) return;
              final onlineSource = await _createAudioSource(
                startTrack,
                allowLocal: false,
              );
              if (_queueGenerationId != currentId) return;
              if (onlineSource != null) {
                try {
                  _startLogicalOffset = _currentLogicalIndex;
                  await _audioHandler.setSourceList(
                    [onlineSource],
                    initialIndex: 0,
                  );
                  loaded = true;
                } catch (onlineErr) {
                  debugPrint(
                    "Online fallback also failed for ${startTrack.title}: $onlineErr",
                  );
                }
              }
            } else {
              debugPrint("Failed to load source for ${startTrack.title}: $e");
            }
          }
        }

        if (!loaded) {
          if (_currentLogicalIndex < _logicalQueue.length - 1) {
            _currentLogicalIndex++;
            _startLogicalOffset = _currentLogicalIndex;
            _bufferedLogicalIndex = _currentLogicalIndex;
            debugPrint(
              'Track unplayable, advancing to next in queue: ${_logicalQueue[_currentLogicalIndex].title}',
            );
          } else {
            break;
          }
        }
      }

      if (_queueGenerationId != currentId) return;

      if (loaded) {
        // 2. Pre-buffer up to 2 tracks ahead (sliding window) to maintain gapless playback
        _preloadUpcomingWindow(_currentLogicalIndex, currentId);

        if (autoPlay) {
          await _audioHandler.play();
        } else {
          await _audioHandler.pause();
        }
      }
    } finally {
      if (_queueGenerationId == currentId) {
        _isSettingQueue = false;
      }
    }
  }

  @override
  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  }) async {
    if (tracks.isEmpty) {
      await clearQueue();
      return;
    }

    final clampedIdx = currentIndex.clamp(0, tracks.length - 1);
    final currentInternal = _audioHandler.internalPlayer.currentIndex;

    if (_audioHandler.internalPlayer.audioSource != null && currentInternal != null) {
      _queueGenerationId++;
      final currentId = _queueGenerationId;
      _logicalQueue = List.from(tracks);
      _currentLogicalIndex = clampedIdx;
      _startLogicalOffset = clampedIdx - currentInternal;
      _bufferedLogicalIndex = clampedIdx;
      _queueController.add(List.unmodifiable(_logicalQueue));

      await _audioHandler.removeUpcomingSourcesAfter(currentInternal);
      _preloadUpcomingWindow(_currentLogicalIndex, currentId);
    } else {
      await setQueue(tracks, initialIndex: clampedIdx);
    }
  }

  /// Lazily preloads a small lookahead window based on user settings
  Future<void> _preloadUpcomingWindow(int baseIndex, int generationId) async {
    if (_settingsRepository.dataSaver) return;

    final maxLookahead = _settingsRepository.lookaheadTracks;
    if (maxLookahead <= 0) return;

    for (int offset = 1; offset <= maxLookahead; offset++) {
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
    if (_settingsRepository.dataSaver) return;

    final maxLookahead = _settingsRepository.lookaheadTracks;
    if (maxLookahead <= 0) return;

    final targetIndex = currentLogical + maxLookahead;
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
      final internalOffset = index - _startLogicalOffset;
      _logicalQueue.removeAt(index);

      if (_logicalQueue.isEmpty) {
        _currentLogicalIndex = 0;
        _startLogicalOffset = 0;
        _bufferedLogicalIndex = 0;
        _queueController.add(const []);
        await _audioHandler.clearPlaylist();
        return;
      }

      if (index < _currentLogicalIndex) {
        _currentLogicalIndex--;
      } else if (_currentLogicalIndex >= _logicalQueue.length) {
        _currentLogicalIndex = _logicalQueue.length - 1;
      }

      if (index < _startLogicalOffset && _startLogicalOffset > 0) {
        _startLogicalOffset--;
      }
      if (index <= _bufferedLogicalIndex && _bufferedLogicalIndex > 0) {
        _bufferedLogicalIndex--;
      }

      _queueController.add(List.unmodifiable(_logicalQueue));

      if (internalOffset >= 0 && internalOffset < _audioHandler.queue.value.length) {
        await _audioHandler.removeQueueItemAt(internalOffset);
      }

      _ensureNextBuffered(_currentLogicalIndex, _queueGenerationId);
    }
  }

  @override
  Future<void> clearQueue() async {
    _queueGenerationId++;
    _logicalQueue = [];
    _currentLogicalIndex = 0;
    _startLogicalOffset = 0;
    _bufferedLogicalIndex = 0;
    _queueController.add(const []);
    await _audioHandler.clearPlaylist();
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

    // Re-seed lookahead buffer from the new shuffled order without restarting current track
    _queueGenerationId++;
    final currentId = _queueGenerationId;
    final currentInternal = _audioHandler.internalPlayer.currentIndex;

    if (_audioHandler.internalPlayer.audioSource != null && currentInternal != null) {
      _bufferedLogicalIndex = _currentLogicalIndex;
      await _audioHandler.removeUpcomingSourcesAfter(currentInternal);
      _preloadUpcomingWindow(_currentLogicalIndex, currentId);
    } else {
      await setQueue(_logicalQueue, initialIndex: _currentLogicalIndex);
    }
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

    // 1. Primary: Fast, non-redirecting InnerTube JSON API
    try {
      final innerTubeResults = await _innerTube.search(query);
      if (innerTubeResults.isNotEmpty) {
        return innerTubeResults
            .map(
              (v) => Track(
                id: v.id,
                title: v.title,
                artist: v.artist,
                thumbnailUrl: v.thumbnailUrl,
                duration: v.duration,
                source: TrackSource.youtube,
              ),
            )
            .toList();
      }
    } catch (e) {
      debugPrint("InnerTube search error: $e");
    }

    // 2. Secondary: Fallback to YoutubeExplode
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
      thumbnailUrl: item.artUri?.toString() ?? '',
      duration: item.duration ?? Duration.zero,
      source: TrackSource.fromId(item.id),
    );
  }

  Future<AudioSource?> _createAudioSource(
    Track track, {
    bool allowLocal = true,
  }) async {
    try {
      // 1. Check Offline File
      if (allowLocal) {
        final localPath = _downloadRepository.getLocalPath(track.id);
        if (localPath != null && File(localPath).existsSync()) {
          final file = File(localPath);
          final fileSize = await file.length();

          if (fileSize < 10240) {
            debugPrint(
              "Warning: Downloaded file too small (${fileSize}B), deleting and re-streaming: ${track.title}",
            );
            await _downloadRepository.deleteTrack(track.id);
          } else {
            final firstBytes = await file.openRead(0, 10).fold<List<int>>(
              [],
              (prev, chunk) => prev..addAll(chunk),
            );
            final header = String.fromCharCodes(firstBytes).trim();

            if (header.startsWith('#EXTM3U')) {
              debugPrint(
                "Warning: Downloaded file is HLS manifest, deleting and re-streaming: ${track.title}",
              );
              await _downloadRepository.deleteTrack(track.id);
            } else {
              return AudioSource.file(
                localPath,
                tag: MediaItem(
                  id: track.storageId,
                  title: track.title,
                  artist: track.artist,
                  artUri: _parseArtUri(track.thumbnailUrl),
                  duration: track.duration,
                ),
              );
            }
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
        final isDataSaver = _settingsRepository.dataSaver;
        final highQuality = _settingsRepository.highAudioQuality;

        if (isDataSaver) {
          // Data Saver mode: pick lowest viable bitrate (~50-70kbps) to conserve cellular data
          final sorted = manifest.audioOnly.sortByBitrate();
          if (sorted.isNotEmpty) {
            audioStream = sorted.first;
          }
        } else if (highQuality) {
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

      final uri = Uri.parse(streamUrl);
      final mediaTag = MediaItem(
        id: track.storageId,
        title: track.title,
        artist: track.artist,
        artUri: _parseArtUri(track.thumbnailUrl),
        duration: track.duration,
      );

      // Use native AudioSource.uri across all platforms so ExoPlayer (Android)
      // and native players handle HTTP Range requests on long 20+ minute tracks
      // and HLS manifests directly without proxy stalls.
      return AudioSource.uri(uri, tag: mediaTag);
    } catch (e) {
      debugPrint("Error extracting audio for ${track.title} (${track.source}): $e");
      return null;
    }
  }
}
