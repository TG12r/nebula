import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:nebula/features/home/data/repositories/search_history_repository.dart'; // Added

import 'package:nebula/features/home/data/repositories/playback_history_repository.dart'; // Added

class PlayerController extends ChangeNotifier {
  final PlayerRepository _repository;
  final SearchHistoryRepository _historyRepository;
  final PlaybackHistoryRepository _playbackHistoryRepository; // Added

  // State
  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<Track> _searchResults = [];
  bool _isSearching = false;
  bool _isBuffering = false;

  List<Track> _queue = [];
  List<String> _searchHistory = [];
  List<Track> _playbackHistory = []; // Added

  // Getters
  bool get isPlaying => _isPlaying;
  String? get currentTitle => _currentTrack?.title;
  String? get currentArtist => _currentTrack?.artist;
  String? get currentThumbnail => _currentTrack?.thumbnailUrl;
  Duration get duration => _duration;
  Duration get position => _position;
  List<Track> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get isBuffering => _isBuffering;
  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  List<String> get searchHistory => _searchHistory;
  List<Track> get playbackHistory => _playbackHistory; // Added

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  PlayerController(
    this._repository,
    this._historyRepository,
    this._playbackHistoryRepository,
  ) {
    _initStreams();
    _loadHistory();
    _loadPlaybackHistory(); // Added
  }

  Future<void> _loadPlaybackHistory() async {
    _playbackHistory = _playbackHistoryRepository.getHistory();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    _searchHistory = _historyRepository.getHistory();
    notifyListeners();
  }

  Future<void> deleteHistoryItem(String query) async {
    await _historyRepository.deleteQuery(query);
    await _loadHistory();
  }

  Future<void> clearHistory() async {
    await _historyRepository.clear();
    await _loadHistory();
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
        // Auto-save to history when track changes
        if (t != null && t.id != _currentTrack?.id) {
          _playbackHistoryRepository.addToHistory(t);
          _loadPlaybackHistory();
        }

        _currentTrack = t;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _repository.processingStateStream.listen((state) {
        _isBuffering =
            state == AudioProcessingState.buffering ||
            state == AudioProcessingState.loading;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _repository.queueStream.listen((q) {
        _queue = q;
        notifyListeners();
      }),
    );
  }

  // Actions forwarded to Repository
  Future<String?> playYoutubeVideo(Track track) async {
    return await _repository.play(track);
  }

  Future<void> playPlaylist(List<Track> tracks, {int initialIndex = 0}) async {
    await _repository.setQueue(tracks, initialIndex: initialIndex);
  }

  Future<void> addToQueue(Track track) async {
    await _repository.addToQueue(track);
  }

  Future<void> removeFromQueue(int index) async {
    await _repository.removeFromQueue(index);
  }

  Future<void> skipToNext() async {
    await _repository.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _repository.skipToPrevious();
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
      if (query.isNotEmpty) {
        await _historyRepository.addQuery(query);
        _loadHistory();
      }
      _searchResults = await _repository.search(query);
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<bool> playMix(String query) async {
    _isSearching = true; // Show loading state if UI observes it
    notifyListeners();

    try {
      final results = await _repository.search(query);
      if (results.isNotEmpty) {
        await playPlaylist(results);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error playing mix: $e");
      return false;
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
