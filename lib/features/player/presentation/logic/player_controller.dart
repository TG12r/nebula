import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';

class PlayerController extends ChangeNotifier {
  final PlayerRepository _repository;

  // State
  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<Track> _searchResults = [];
  bool _isSearching = false;

  // Getters
  bool get isPlaying => _isPlaying;
  String? get currentTitle => _currentTrack?.title;
  String? get currentArtist => _currentTrack?.artist;
  String? get currentThumbnail => _currentTrack?.thumbnailUrl;
  Duration get duration => _duration;
  Duration get position => _position;
  List<Track> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  PlayerController(this._repository) {
    _initStreams();
  }

  void _initStreams() {
    _subscriptions.add(
      _repository.positionStream.listen((p) {
        _position = p;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _repository.durationStream.listen((d) {
        _duration = d;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _repository.isPlayingStream.listen((p) {
        _isPlaying = p;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _repository.currentTrackStream.listen((t) {
        _currentTrack = t;
        notifyListeners();
      }),
    );
  }

  // Actions forwarded to Repository
  Future<String?> playYoutubeVideo(String videoId) async {
    return await _repository.play(videoId);
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await _repository.pause();
    } else {
      await _repository.resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _repository.seek(position);
  }

  Future<void> search(String query) async {
    _isSearching = true;
    _searchResults = [];
    notifyListeners();

    try {
      _searchResults = await _repository.search(query);
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _repository.dispose();
    super.dispose();
  }
}
