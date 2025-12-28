import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlayerController extends ChangeNotifier {
  // Use singleton pattern for global access if needed, or just Provider
  final AudioPlayer _audioPlayer = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();

  // State
  bool _isPlaying = false;
  String? _currentTitle;
  String? _currentArtist;
  String? _currentThumbnail;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // Getters
  bool get isPlaying => _isPlaying;
  String? get currentTitle => _currentTitle;
  String? get currentArtist => _currentArtist;
  String? get currentThumbnail => _currentThumbnail;
  Duration get duration => _duration;
  Duration get position => _position;

  // Expose player for advanced usage
  AudioPlayer get audioPlayer => _audioPlayer;

  PlayerController() {
    _init();
  }

  void _init() {
    // Listen to player state
    _audioPlayer.playerStateStream.listen((state) {
      final isPlaying = state.playing;
      final processingState = state.processingState;

      if (_isPlaying != isPlaying) {
        _isPlaying = isPlaying;
        notifyListeners();
      }

      if (processingState == ProcessingState.completed) {
        _isPlaying = false;
        _position = Duration.zero;
        notifyListeners();
      }
    });

    // Listen to position
    _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    // Listen to duration
    _audioPlayer.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
      notifyListeners();
    });
  }

  Future<void> playYoutubeVideo(String videoId) async {
    try {
      // 1. Get Video Info (Lightweight metadata fetch)
      var video = await _yt.videos.get(videoId);
      _currentTitle = video.title;
      _currentArtist = video.author;
      _currentThumbnail = video.thumbnails.mediumResUrl;
      notifyListeners();

      // 2. Get Audio Stream
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      var audioStream = manifest.audioOnly.withHighestBitrate();

      // 3. Load & Play
      await _audioPlayer.setUrl(audioStream.url.toString());
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("Error playing video: $e");
      // Handle error (notify UI)
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
