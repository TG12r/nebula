import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
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

  PlayerRepositoryImpl(
    this._audioHandler,
    this._downloadRepository,
    this._settingsRepository,
    this._scRepository,
  );

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
  Stream<List<Track>> get queueStream => _audioHandler.queue.map((items) {
    return items.map((item) => _mediaItemToTrack(item)).toList();
  });

  @override
  Stream<AudioProcessingState> get processingStateStream => _audioHandler
      .playbackState
      .map((state) => state.processingState)
      .distinct();

  @override
  Future<String?> play(Track track) async {
    try {
      final source = await _createAudioSource(track);
      if (source == null) return "Could not extract audio URL";

      await _audioHandler.setSourceList([source]);
      await _audioHandler.play();
      return null;
    } catch (e) {
      debugPrint("Error in Repo play: $e");
      return "Error: $e";
    }
  }

  int _queueGenerationId = 0;

  @override
  Future<void> setQueue(List<Track> tracks, {int initialIndex = 0}) async {
    // Increment ID to cancel any previous background loading
    _queueGenerationId++;
    final currentId = _queueGenerationId;

    if (tracks.isEmpty) return;

    // 1. Immediate: Load ONLY the requested start track to play ASAP
    final startTrack = tracks[initialIndex];
    final startSource = await _createAudioSource(startTrack);

    if (startSource != null) {
      // Set the initial source (clearing previous queue)
      await _audioHandler.setSourceList([startSource], initialIndex: 0);

      // 2. Background: Load the rest of the queue
      // We start this immediately but don't await it, so it runs in parallel with playback start
      _loadRemainingQueue(tracks, initialIndex, currentId);

      await _audioHandler.play();
    } else {
      // Even if start source fails, try to load others? Or just abort.
      // Usually if start fails, we might want to try next one.
      _loadRemainingQueue(tracks, initialIndex, currentId);
    }
  }

  Future<void> _loadRemainingQueue(
    List<Track> tracks,
    int initialIndex,
    int generationId,
  ) async {
    try {
      // We'll process the remaining tracks in batches to speed up loading
      // without hitting rate limits too hard.
      final remainingTracks = <Track>[];

      // Add tracks AFTER the initial index
      for (int i = initialIndex + 1; i < tracks.length; i++) {
        remainingTracks.add(tracks[i]);
      }

      final int batchSize = 3;

      for (var i = 0; i < remainingTracks.length; i += batchSize) {
        if (_queueGenerationId != generationId) return;

        final end = (i + batchSize < remainingTracks.length)
            ? i + batchSize
            : remainingTracks.length;
        final batch = remainingTracks.sublist(i, end);

        // Process batch in parallel
        final futures = batch.map((track) async {
          if (_queueGenerationId != generationId) return null;
          return await _createAudioSource(track);
        });

        final sources = await Future.wait(futures);

        // Add valid sources to queue
        for (final source in sources) {
          if (_queueGenerationId != generationId) return;
          if (source != null) {
            await _audioHandler.addAudioSourceToQueue(source);
          }
        }
      }
    } catch (e) {
      debugPrint("Error in _loadRemainingQueue: $e");
    }
  }

  @override
  Future<void> addToQueue(Track track) async {
    final source = await _createAudioSource(track);
    if (source != null) {
      await _audioHandler.addAudioSourceToQueue(source);
    }
  }

  @override
  Future<void> removeFromQueue(int index) async {
    await _audioHandler.removeQueueItemAt(index);
  }

  @override
  Future<void> shuffleQueue() async {
    // We delegate this complex logic to the Audio Handler which has direct access to indices
    await _audioHandler.shuffleStringQueue();
  }

  @override
  Future<void> skipToNext() => _audioHandler.skipToNext();

  @override
  Future<void> skipToPrevious() => _audioHandler.skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _audioHandler.skipToQueueItem(index);

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
    _yt.close();
    _audioHandler.stop();
  }

  // Helper
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
        // Validate the file is actual audio, not a corrupt HLS manifest
        final file = File(localPath);
        final fileSize = await file.length();
        
        if (fileSize < 1024) {
          // File is suspiciously small, likely corrupt or an HLS manifest
          debugPrint("Warning: Downloaded file too small (${fileSize}B), re-streaming: ${track.title}");
        } else {
          // Quick check: read first bytes to detect M3U8/HLS manifest
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
        // YouTube Stream
        final manifest = await _yt.videos.streamsClient.getManifest(
          track.rawId,
          ytClients: [yt_lib.YoutubeApiClient.androidVr],
        );

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
