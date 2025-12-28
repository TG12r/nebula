import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

class PlayerRepositoryImpl implements PlayerRepository {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  // Stream Controllers to bridge external streams to domain streams
  final _currentTrackController = StreamController<Track?>.broadcast();

  // Internal State Cache
  Track? _currentTrack;

  PlayerRepositoryImpl() {
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Stream<Duration> get positionStream => _audioPlayer.positionStream;

  @override
  Stream<Duration> get durationStream =>
      _audioPlayer.durationStream.map((d) => d ?? Duration.zero);

  @override
  Stream<bool> get isPlayingStream =>
      _audioPlayer.playerStateStream.map((s) => s.playing);

  @override
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  @override
  Future<String?> play(String videoId) async {
    try {
      debugPrint("Repo: Fetching video info for $videoId...");
      var video = await _yt.videos.get(videoId);

      // Create Track Entity
      _currentTrack = Track(
        id: video.id.value,
        title: video.title,
        artist: video.author,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        duration: video.duration ?? Duration.zero,
      );
      _currentTrackController.add(_currentTrack);

      // Stream Logic
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

      final streamUrl = audioStream.url.toString();

      await _audioPlayer.setUrl(streamUrl);
      await _audioPlayer.play();
      return null;
    } catch (e, stackTrace) {
      debugPrint("Error in Repo play: $e");
      debugPrintStack(stackTrace: stackTrace);
      return "Error: $e";
    }
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  @override
  Future<void> resume() async {
    await _audioPlayer.play();
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

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
    _audioPlayer.dispose();
    _yt.close();
    _currentTrackController.close();
  }
}
