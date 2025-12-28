import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

class PlayerRepositoryImpl implements PlayerRepository {
  final NebulaAudioHandler _audioHandler;
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  List<Track> _queue = [];
  int _currentIndex = 0;
  StreamSubscription? _playbackStateSubscription;

  PlayerRepositoryImpl(this._audioHandler) {
    _initAutoAdvance();
  }

  void _initAutoAdvance() {
    _playbackStateSubscription = _audioHandler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.completed) {
        skipToNext();
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
    return Track(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown',
      thumbnailUrl: item.artUri.toString(),
      duration: item.duration ?? Duration.zero,
    );
  });

  @override
  Stream<AudioProcessingState> get processingStateStream => _audioHandler
      .playbackState
      .map((state) => state.processingState)
      .distinct();

  @override
  Future<String?> play(Track track) async {
    // 1. Immediate UI Update (Optimistic)
    final mediaItem = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artUri: Uri.parse(track.thumbnailUrl),
      duration: track.duration,
    );
    _audioHandler.mediaItem.add(mediaItem);

    // 2. Treat as queue of 1 for consistency
    _queue = [track];
    _currentIndex = 0;

    try {
      // 3. Extract Stream URL (Async/Heavy)
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

      // 4. Create Source
      final source = AudioSource.uri(
        Uri.parse(audioStream.url.toString()),
        tag: mediaItem,
      );

      await _audioHandler.setSource(source);
      await _audioHandler.play();
      return null;
    } catch (e) {
      debugPrint("Error in Repo play: $e");
      return "Error: $e";
    }
  }

  @override
  Future<String?> setQueue(List<Track> tracks, {int initialIndex = 0}) async {
    _queue = tracks;
    _currentIndex = initialIndex;

    // Update AudioService queue for UI/System
    final mediaItems = tracks
        .map(
          (t) => MediaItem(
            id: t.id,
            title: t.title,
            artist: t.artist,
            artUri: Uri.parse(t.thumbnailUrl),
            duration: t.duration,
          ),
        )
        .toList();
    await _audioHandler.updateQueue(mediaItems);

    if (_queue.isNotEmpty && _currentIndex < _queue.length) {
      return await _playTrack(_queue[_currentIndex]);
    }
    return null;
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _playTrack(_queue[_currentIndex]);
    } else {
      // Loop or stop? For now stop or loop to start
      // _currentIndex = 0; // Loop
      // await _playTrack(_queue[_currentIndex]);
      await _audioHandler.stop();
      await _audioHandler.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playTrack(_queue[_currentIndex]);
    } else {
      await _audioHandler.seek(Duration.zero);
    }
  }

  Future<String?> _playTrack(Track track) async {
    try {
      final String videoId = track.id;

      // Extract Stream URL
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
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

      // Create AudioSource with MediaItem (Vital for Notifications)
      final source = AudioSource.uri(
        Uri.parse(audioStream.url.toString()),
        tag: MediaItem(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artUri: Uri.parse(track.thumbnailUrl),
          duration: track.duration,
        ),
      );

      await _audioHandler.setSource(source);
      await _audioHandler.play();
      return null;
    } catch (e) {
      debugPrint("Error in Repo playTrack: $e");
      return "Error: $e";
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
    _playbackStateSubscription?.cancel();
    _yt.close();
    _audioHandler.stop();
  }
}
