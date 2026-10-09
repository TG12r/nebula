import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/data/services/playlist_track_matcher.dart';
import 'package:nebula/features/playlist/data/services/spotify_import_provider.dart';
import 'package:nebula/features/playlist/domain/entities/importable_playlist.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/domain/services/playlist_import_service.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';

enum ImportStatus {
  idle,
  fetchingPreview,
  previewReady,
  importing,
  completed,
  error,
}

class PlaylistImportController extends ChangeNotifier {
  final List<PlaylistImportProvider> _providers;
  final PlaylistTrackMatcher _matcher;

  PlaylistImportController({
    List<PlaylistImportProvider>? providers,
    PlaylistTrackMatcher? matcher,
  })  : _providers = providers ?? [SpotifyImportProvider()],
        _matcher = matcher ?? PlaylistTrackMatcher();

  ImportStatus _status = ImportStatus.idle;
  String? _errorMessage;
  ImportablePlaylist? _previewPlaylist;
  Playlist? _createdPlaylist;

  int _currentIndex = 0;
  int _totalTracks = 0;
  String _currentTrackTitle = '';
  int _successfulCount = 0;
  int _failedCount = 0;
  bool _isCancelled = false;

  ImportStatus get status => _status;
  String? get errorMessage => _errorMessage;
  ImportablePlaylist? get previewPlaylist => _previewPlaylist;
  Playlist? get createdPlaylist => _createdPlaylist;

  int get currentIndex => _currentIndex;
  int get totalTracks => _totalTracks;
  String get currentTrackTitle => _currentTrackTitle;
  int get successfulCount => _successfulCount;
  int get failedCount => _failedCount;
  double get progress => _totalTracks > 0 ? (_currentIndex / _totalTracks).clamp(0.0, 1.0) : 0.0;

  void reset() {
    _status = ImportStatus.idle;
    _errorMessage = null;
    _previewPlaylist = null;
    _createdPlaylist = null;
    _currentIndex = 0;
    _totalTracks = 0;
    _currentTrackTitle = '';
    _successfulCount = 0;
    _failedCount = 0;
    _isCancelled = false;
    notifyListeners();
  }

  void cancel() {
    _isCancelled = true;
    notifyListeners();
  }

  Future<void> fetchPreview(String urlOrId) async {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Please enter a Spotify playlist link.';
      _status = ImportStatus.error;
      notifyListeners();
      return;
    }

    PlaylistImportProvider? matchedProvider;
    for (final provider in _providers) {
      if (provider.canHandle(trimmed)) {
        matchedProvider = provider;
        break;
      }
    }

    if (matchedProvider == null) {
      _errorMessage = 'Unsupported link. Please paste a valid public Spotify playlist URL.';
      _status = ImportStatus.error;
      notifyListeners();
      return;
    }

    _status = ImportStatus.fetchingPreview;
    _errorMessage = null;
    _previewPlaylist = null;
    notifyListeners();

    try {
      final playlist = await matchedProvider.fetchPlaylist(trimmed);
      _previewPlaylist = playlist;
      _status = ImportStatus.previewReady;
      notifyListeners();
    } catch (e) {
      _status = ImportStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> startImport(
    PlaylistController playlistController, {
    String? customName,
  }) async {
    if (_previewPlaylist == null || _previewPlaylist!.tracks.isEmpty) {
      _errorMessage = 'No tracks found to import.';
      _status = ImportStatus.error;
      notifyListeners();
      return;
    }

    _status = ImportStatus.importing;
    _errorMessage = null;
    _isCancelled = false;
    _currentIndex = 0;
    _totalTracks = _previewPlaylist!.tracks.length;
    _successfulCount = 0;
    _failedCount = 0;
    _currentTrackTitle = '';
    notifyListeners();

    final playlistName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : _previewPlaylist!.title;

    try {
      // 1. Create playlist in Nebula
      await playlistController.createPlaylist(playlistName);
      // Retrieve the newly created playlist (it gets inserted at index 0)
      if (playlistController.playlists.isNotEmpty) {
        _createdPlaylist = playlistController.playlists.first;
      }

      final playlistId = _createdPlaylist?.id;
      if (playlistId == null) {
        throw Exception('Failed to initialize playlist in database.');
      }

      // 2. Iterate through tracks and match with controlled concurrency
      final total = _previewPlaylist!.tracks.length;
      final matchedTracks = List<Track?>.filled(total, null);
      int completedCount = 0;
      int nextIndex = 0;
      const workerCount = 3;

      Future<void> worker() async {
        while (!_isCancelled) {
          if (nextIndex >= total) break;
          final index = nextIndex++;
          final importableTrack = _previewPlaylist!.tracks[index];

          _currentTrackTitle =
              '${importableTrack.artist} - ${importableTrack.title}';
          notifyListeners();

          final matched = await _matcher.matchTrack(importableTrack);
          if (_isCancelled) break;

          completedCount++;
          _currentIndex = completedCount;
          if (matched != null) {
            matchedTracks[index] = matched;
            _successfulCount++;
          } else {
            _failedCount++;
          }
          notifyListeners();

          // Small delay per worker to be polite to the network
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }

      await Future.wait(List.generate(workerCount, (_) => worker()));

      if (_isCancelled) {
        debugPrint('Import cancelled by user');
      }

      // 3. Batch commit all matched tracks in order to local cache and database
      final orderedTracks = matchedTracks.whereType<Track>().toList();
      if (orderedTracks.isNotEmpty) {
        try {
          await playlistController.addTracksToPlaylist(playlistId, orderedTracks);
        } catch (e) {
          debugPrint('Failed to batch save tracks: $e');
        }
      }

      _status = ImportStatus.completed;
      notifyListeners();
    } catch (e) {
      _status = ImportStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _matcher.dispose();
    super.dispose();
  }
}
