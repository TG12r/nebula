import 'package:flutter/material.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart';

class PlaylistController extends ChangeNotifier {
  final PlaylistRepository _repository;

  List<Playlist> _playlists = [];
  bool _isLoading = false;

  // Cache for open playlist details
  String? _currentPlaylistId;
  List<Track> _currentPlaylistTracks = [];
  bool _isLoadingDetails = false;

  PlaylistSortType _sortType = PlaylistSortType.custom;

  PlaylistController(this._repository) {
    _loadPlaylists();
  }

  List<Playlist> get playlists => _playlists;
  bool get isLoading => _isLoading;
  PlaylistSortType get sortType => _sortType;

  List<Track> get currentPlaylistTracks => _currentPlaylistTracks;
  bool get isLoadingDetails => _isLoadingDetails;

  Future<void> _loadPlaylists() async {
    _isLoading = true;
    notifyListeners();

    try {
      _playlists = await _repository.getPlaylists();
      final savedSort = await _repository.getPlaylistSortType();
      if (savedSort != null) {
        _sortType = PlaylistSortType.values.firstWhere(
          (e) => e.name == savedSort,
          orElse: () => PlaylistSortType.custom,
        );
      }
      _applySort();
    } catch (e) {
      debugPrint("Error loading playlists: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applySort() {
    switch (_sortType) {
      case PlaylistSortType.nameAsc:
        _playlists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case PlaylistSortType.nameDesc:
        _playlists.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case PlaylistSortType.tracksCount:
        _playlists.sort((a, b) => b.trackCount.compareTo(a.trackCount));
        break;
      case PlaylistSortType.recent:
      case PlaylistSortType.custom:
        break;
    }
  }

  Future<void> setSortType(PlaylistSortType type) async {
    _sortType = type;
    if (type == PlaylistSortType.recent) {
      _playlists = await _repository.getPlaylists();
    } else {
      _applySort();
    }
    notifyListeners();
    await _repository.savePlaylistSortType(type.name);
  }

  Future<void> reorderPlaylists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _playlists.length) return;
    if (newIndex < 0 || newIndex > _playlists.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _playlists.removeAt(oldIndex);
    _playlists.insert(newIndex, item);
    _sortType = PlaylistSortType.custom;
    notifyListeners();

    final orderIds = _playlists.map((p) => p.id).toList();
    await _repository.savePlaylistsOrder(orderIds);
    await _repository.savePlaylistSortType(PlaylistSortType.custom.name);
  }

  Future<void> createPlaylist(String name) async {
    try {
      final newPlaylist = await _repository.createPlaylist(name);
      _playlists.insert(0, newPlaylist);
      notifyListeners();
    } catch (e) {
      debugPrint("Error creating playlist: $e");
      rethrow;
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      await _repository.deletePlaylist(id);
      _playlists.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting playlist: $e");
      rethrow;
    }
  }

  Future<void> loadPlaylistDetails(String playlistId) async {
    _currentPlaylistId = playlistId;
    _isLoadingDetails = true;
    _currentPlaylistTracks = []; // Clear previous
    notifyListeners();

    try {
      _currentPlaylistTracks = await _repository.getPlaylistTracks(playlistId);
    } catch (e) {
      debugPrint("Error loading playlist tracks: $e");
    } finally {
      _isLoadingDetails = false;
      notifyListeners();
    }
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    // Optimistic update if currently viewing this playlist
    if (_currentPlaylistId == playlistId) {
      _currentPlaylistTracks.insert(0, track);
      notifyListeners();
    }

    // Optimistic update for playlist list count
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final p = _playlists[index];
      _playlists[index] = Playlist(
        id: p.id,
        name: p.name,
        userId: p.userId,
        trackCount: p.trackCount + 1,
      );
      notifyListeners();
    }

    try {
      await _repository.addTrackToPlaylist(playlistId, track);
    } catch (e) {
      // Revert details
      if (_currentPlaylistId == playlistId) {
        _currentPlaylistTracks.remove(track);
        notifyListeners();
      }

      // Revert list count
      if (index != -1) {
        final p = _playlists[index];
        _playlists[index] = Playlist(
          id: p.id,
          name: p.name,
          userId: p.userId,
          trackCount: p.trackCount - 1,
        );
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> addTracksToPlaylist(String playlistId, List<Track> tracks) async {
    if (tracks.isEmpty) return;

    // Optimistic update if currently viewing this playlist
    if (_currentPlaylistId == playlistId) {
      _currentPlaylistTracks.insertAll(0, tracks);
      notifyListeners();
    }

    // Optimistic update for playlist list count
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final p = _playlists[index];
      _playlists[index] = Playlist(
        id: p.id,
        name: p.name,
        userId: p.userId,
        trackCount: p.trackCount + tracks.length,
      );
      notifyListeners();
    }

    try {
      await _repository.addTracksToPlaylist(playlistId, tracks);
    } catch (e) {
      // Revert details
      if (_currentPlaylistId == playlistId) {
        for (final t in tracks) {
          _currentPlaylistTracks.remove(t);
        }
        notifyListeners();
      }

      // Revert list count
      if (index != -1) {
        final p = _playlists[index];
        _playlists[index] = Playlist(
          id: p.id,
          name: p.name,
          userId: p.userId,
          trackCount: p.trackCount - tracks.length,
        );
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<List<String>> getPlaylistsContainingTrack(String trackId) async {
    return await _repository.getPlaylistsContainingTrack(trackId);
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    try {
      await _repository.removeTrackFromPlaylist(playlistId, trackId);
      // Optimistic update if viewing
      if (_currentPlaylistId == playlistId) {
        _currentPlaylistTracks.removeWhere((t) => t.id == trackId);
        notifyListeners();
      }

      // Update list count
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        final p = _playlists[index];
        _playlists[index] = Playlist(
          id: p.id,
          name: p.name,
          userId: p.userId,
          trackCount: p.trackCount - 1,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error removing track: $e");
      rethrow;
    }
  }
}
