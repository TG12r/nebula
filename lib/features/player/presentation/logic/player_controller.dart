import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

class PlayerController extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  bool _isPlaying = false;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentThumbnail;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  bool get isPlaying => _isPlaying;
  String? get currentTitle => _currentTitle;
  String? get currentArtist => _currentArtist;
  String? get currentThumbnail => _currentThumbnail;
  Duration get duration => _duration;
  Duration get position => _position;

  AudioPlayer get audioPlayer => _audioPlayer;

  PlayerController() {
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      _audioPlayer.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = Duration.zero;
        }
        notifyListeners();
      });

      _audioPlayer.positionStream.listen((pos) {
        _position = pos;
        notifyListeners();
      });

      _audioPlayer.durationStream.listen((d) {
        _duration = d ?? Duration.zero;
        notifyListeners();
      });

      debugPrint("Audio player initialized.");
    } catch (e) {
      debugPrint("Error initializing audio player: $e");
    }
  }

  Future<String?> playYoutubeVideo(String videoId) async {
    try {
      debugPrint(
        "Starting playYoutubeVideo (Direct Stream) on: ${Platform.operatingSystem}",
      );

      // Get Video Info
      debugPrint("Fetching video info for $videoId...");
      var video = await _yt.videos.get(videoId);

      _currentTitle = video.title;
      _currentArtist = video.author;
      _currentThumbnail = video.thumbnails.mediumResUrl;
      notifyListeners();

      // Get Manifest with AndroidVR client (User Fix)
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [yt_lib.YoutubeApiClient.androidVr],
      );

      // Select Audio Stream: Prefer MP4/M4A for better ExoPlayer compatibility
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
      debugPrint("Streaming URL directly: $streamUrl");

      await _audioPlayer.setUrl(streamUrl);
      await _audioPlayer.play();
      return null;
    } catch (e, stackTrace) {
      debugPrint("Error playing video: $e");
      debugPrintStack(stackTrace: stackTrace);
      return "Error: $e";
    }
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _yt.close();
    super.dispose();
  }
}
