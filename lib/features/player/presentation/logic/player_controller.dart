import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:nebula/features/home/data/repositories/search_history_repository.dart';
import 'package:nebula/features/home/data/repositories/playback_history_repository.dart';

class PlayerController extends ChangeNotifier {
  final PlayerRepository _repository;
  final SearchHistoryRepository _historyRepository;
  final PlaybackHistoryRepository _playbackHistoryRepository;

  // State
  bool _isPlaying = false;
  Track? _currentTrack;
  String? _lastHistoryTrackId;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  double _lastNonZeroVolume = 0.5;

  List<Track> _searchResults = [];
  bool _isSearching = false;
  bool _isBuffering = false;

  List<Track> _queue = [];
  List<String> _searchHistory = [];
  List<Track> _playbackHistory = [];

  // Getters
  bool get isPlaying => _isPlaying;
  String? get currentTitle => _currentTrack?.title;
  String? get currentArtist => _currentTrack?.artist;
  String? get currentThumbnail => _currentTrack?.thumbnailUrl;
  Duration get duration => _duration;
  Duration get position => _position;
  double get volume => _volume;
  bool get isMuted => _volume == 0.0;
  Stream<Duration> get positionStream => _repository.positionStream;
  List<Track> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  bool get isBuffering => _isBuffering;
  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  List<String> get searchHistory => _searchHistory;
  List<Track> get playbackHistory => _playbackHistory;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  PlayerController(
    this._repository,
    this._historyRepository,
    this._playbackHistoryRepository,
  ) {
    _initStreams();
    _loadHistory();
    _loadPlaybackHistory();
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
    _volume = _repository.volume;
    if (_volume > 0) _lastNonZeroVolume = _volume;

    _subscriptions.add(
      _repository.volumeStream.listen((v) {
        _volume = v;
        if (v > 0) _lastNonZeroVolume = v;
        notifyListeners();
      }),
    );

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
        if (t != null) {
          final rawId = TrackSource.stripPrefix(t.id);
          if (rawId != _lastHistoryTrackId) {
            _lastHistoryTrackId = rawId;
            _playbackHistoryRepository.addToHistory(t);
            _loadPlaybackHistory();
          }
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
  Future<String?> playTrack(Track track, {bool autoPlay = true}) async {
    _currentTrack = track;
    _isPlaying = autoPlay;
    notifyListeners();
    return await _repository.play(track, autoPlay: autoPlay);
  }

  Future<void> playPlaylist(
    List<Track> tracks, {
    int? initialIndex,
    bool shuffle = false,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;

    List<Track> effectiveTracks;
    int startIdx;

    if (shuffle) {
      if (initialIndex != null && initialIndex >= 0 && initialIndex < tracks.length) {
        final selectedTrack = tracks[initialIndex];
        final remainingTracks = List<Track>.from(tracks)..removeAt(initialIndex);
        remainingTracks.shuffle();
        effectiveTracks = [selectedTrack, ...remainingTracks];
        startIdx = 0;
      } else {
        effectiveTracks = List<Track>.from(tracks)..shuffle();
        startIdx = 0;
      }
    } else {
      effectiveTracks = tracks;
      startIdx = (initialIndex ?? 0).clamp(0, tracks.length - 1);
    }

    _queue = List.unmodifiable(effectiveTracks);
    _currentTrack = effectiveTracks[startIdx];
    _isPlaying = autoPlay;
    notifyListeners();

    await _repository.setQueue(
      effectiveTracks,
      initialIndex: startIdx,
      autoPlay: autoPlay,
    );
  }

  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  }) async {
    await _repository.updateQueuePreservingCurrent(
      tracks,
      currentIndex: currentIndex,
    );
  }

  Future<void> shuffleQueue() async {
    await _repository.shuffleQueue();
  }

  Future<void> addToQueue(Track track) async {
    await _repository.addToQueue(track);
  }

  Future<void> removeFromQueue(int index) async {
    await _repository.removeFromQueue(index);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;

    final newQueue = List<Track>.from(_queue);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);

    _queue = newQueue;
    notifyListeners();

    int currentIdx = 0;
    if (_currentTrack != null) {
      final found = newQueue.indexWhere(
        (t) => TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(_currentTrack!.id),
      );
      if (found != -1) currentIdx = found;
    }

    await _repository.updateQueuePreservingCurrent(
      newQueue,
      currentIndex: currentIdx,
    );
  }

  Future<void> clearQueue() async {
    _queue = [];
    _currentTrack = null;
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
    await _repository.clearQueue();
  }

  Future<void> skipToNext() async {
    await _repository.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _repository.skipToPrevious();
  }

  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentTrack = _queue[index];
      _isPlaying = true;
      notifyListeners();
    }
    await _repository.skipToQueueItem(index);
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    await _repository.pause();
  }

  Future<void> resume() async {
    _isPlaying = true;
    notifyListeners();
    await _repository.resume();
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

  /// Sets the volume between 0.0 (muted) and 1.0 (100%).
  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _volume = clamped;
    if (clamped > 0) {
      _lastNonZeroVolume = clamped;
    }
    notifyListeners();
    await _repository.setVolume(clamped);
  }

  /// Toggles between muted and the last non-zero volume.
  Future<void> toggleMute() async {
    if (_volume > 0.0) {
      _lastNonZeroVolume = _volume;
      await setVolume(0.0);
    } else {
      await setVolume(_lastNonZeroVolume > 0.0 ? _lastNonZeroVolume : 0.5);
    }
  }

  /// Increases volume by [step] (defaults to 0.05 or 5%).
  Future<void> increaseVolume([double step = 0.05]) async {
    await setVolume((_volume + step).clamp(0.0, 1.0));
  }

  /// Decreases volume by [step] (defaults to 0.05 or 5%).
  Future<void> decreaseVolume([double step = 0.05]) async {
    await setVolume((_volume - step).clamp(0.0, 1.0));
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
