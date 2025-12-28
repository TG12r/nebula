import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

import 'package:nebula/features/downloads/domain/repositories/download_repository.dart'; // Added

class PlayerRepositoryImpl implements PlayerRepository {
  final NebulaAudioHandler _audioHandler;
  final DownloadRepository _downloadRepository; // Added
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  PlayerRepositoryImpl(
    this._audioHandler,
    this._downloadRepository,
  ); // Updated constructor

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

  @override
  Future<void> setQueue(List<Track> tracks, {int initialIndex = 0}) async {
    // This might be slow for many tracks as we extract URLs one by one?
    // TODO: Improve by using lazy loading or generic URIs if possible.
    // For now, let's extract ONLY the first few or just the initial one?
    // Actually, extracting ALL URLs upfront for a playlist is bad UX (slow).
    // Better approach: Just add MediaItems to queue and resolve URL on play?
    // NebulaAudioHandler needs AudioSources.
    // We will extract all for now as per current simple architecture.
    // Optimization: Parallel extraction.

    final sources = <AudioSource>[];
    for (var track in tracks) {
      // Optimization: Don't wait for audio URL for creating source if not immediate?
      // But just_audio needs uri.
      // We'll extract sequentially for safety for now, or parallel.
      final source = await _createAudioSource(track);
      if (source != null) sources.add(source);
    }

    if (sources.isNotEmpty) {
      await _audioHandler.setSourceList(sources, initialIndex: initialIndex);
      await _audioHandler.play();
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
  Future<void> skipToNext() => _audioHandler.skipToNext();

  @override
  Future<void> skipToPrevious() => _audioHandler.skipToPrevious();

  @override
  Future<void> pause() => _audioHandler.pause();

  @override
  Future<void> resume() => _audioHandler.play();

  @override
  Future<void> seek(Duration position) => _audioHandler.seek(position);

  @override
  Future<List<Track>> search(String query) async {
    if (query.trim().isEmpty) return [];
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
    );
  }

  Future<AudioSource?> _createAudioSource(Track track) async {
    try {
      // 1. Check Offline File
      final localPath = _downloadRepository.getLocalPath(track.id);
      if (localPath != null && File(localPath).existsSync()) {
        return AudioSource.file(
          localPath,
          tag: MediaItem(
            id: track.id,
            title: track.title,
            artist: track.artist,
            artUri: Uri.parse(track.thumbnailUrl),
            duration: track.duration,
          ),
        );
      }

      // 2. Stream Online
      final manifest = await _yt.videos.streamsClient.getManifest(
        track.id,
        ytClients: [yt_lib.YoutubeApiClient.androidVr],
      );

      yt_lib.AudioOnlyStreamInfo? audioStream;
      try {
        audioStream = manifest.audioOnly.firstWhere(
          (s) =>
              s.container.name.toLowerCase() == 'mp4' ||
              s.container.name.toLowerCase() == 'm4a',
        );
      } catch (_) {}
      audioStream ??= manifest.audioOnly.withHighestBitrate();

      return AudioSource.uri(
        Uri.parse(audioStream.url.toString()),
        tag: MediaItem(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artUri: Uri.parse(track.thumbnailUrl),
          duration: track.duration,
        ),
      );
    } catch (e) {
      debugPrint("Error extracting audio for ${track.title}: $e");
      return null;
    }
  }
}
