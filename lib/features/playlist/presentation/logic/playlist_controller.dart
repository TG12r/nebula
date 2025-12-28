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

  PlaylistController(this._repository) {
    _loadPlaylists();
  }

  List<Playlist> get playlists => _playlists;
  bool get isLoading => _isLoading;

  List<Track> get currentPlaylistTracks => _currentPlaylistTracks;
  bool get isLoadingDetails => _isLoadingDetails;

  Future<void> _loadPlaylists() async {
    _isLoading = true;
    notifyListeners();

    try {
      _playlists = await _repository.getPlaylists();
    } catch (e) {
      debugPrint("Error loading playlists: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

    try {
      await _repository.addTrackToPlaylist(playlistId, track);
    } catch (e) {
      // Revert
      if (_currentPlaylistId == playlistId) {
        _currentPlaylistTracks.remove(track);
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
    } catch (e) {
      debugPrint("Error removing track: $e");
      rethrow;
    }
  }
}
