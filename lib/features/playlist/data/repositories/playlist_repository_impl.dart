import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  final SupabaseClient _supabase;
  final Box _box;

  PlaylistRepositoryImpl(this._supabase, this._box);

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  @override
  Future<List<Playlist>> getPlaylists() async {
    try {
      if (_supabase.auth.currentUser == null) {
        throw Exception('User not logged in');
      }

      final response = await _supabase
          .from('playlists')
          .select('*, playlist_tracks(count)')
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 3));

      final data = response as List;
      final playlists = data.map((item) {
        // Extract count from join if possible, or defaulting to 0
        int count = 0;
        if (item['playlist_tracks'] != null) {
          final tracksApi = item['playlist_tracks'] as List;
          if (tracksApi.isNotEmpty) {
            count = tracksApi[0]['count'] as int;
          }
        }

        return Playlist(
          id: item['id'] as String,
          name: item['name'] as String,
          userId: item['user_id'] as String,
          trackCount: count,
        );
      }).toList();

      // Cache the playlists
      await _box.put(
        'user_playlists',
        playlists.map((e) => e.toMap()).toList(),
      );

      final customOrder = await getPlaylistsOrder();
      if (customOrder.isNotEmpty) {
        playlists.sort((a, b) {
          final idxA = customOrder.indexOf(a.id);
          final idxB = customOrder.indexOf(b.id);
          if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
          if (idxA != -1) return -1;
          if (idxB != -1) return 1;
          return 0;
        });
      }

      return playlists;
    } catch (e) {
      debugPrint("PlaylistRepository: Network fetch failed ($e), falling back to Hive cache...");
      // Return cached data if available
      if (_box.containsKey('user_playlists')) {
        final cached = _box.get('user_playlists') as List;
        final playlists = cached
            .map((e) => Playlist.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();

        final customOrder = await getPlaylistsOrder();
        if (customOrder.isNotEmpty) {
          playlists.sort((a, b) {
            final idxA = customOrder.indexOf(a.id);
            final idxB = customOrder.indexOf(b.id);
            if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
            if (idxA != -1) return -1;
            if (idxB != -1) return 1;
            return 0;
          });
        }
        return playlists;
      }
      rethrow;
    }
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final response = await _supabase
        .from('playlists')
        .insert({'user_id': _userId, 'name': name})
        .select()
        .single()
        .timeout(const Duration(seconds: 4));

    final playlist = Playlist(
      id: response['id'] as String,
      name: response['name'] as String,
      userId: response['user_id'] as String,
    );

    // Update local cache
    if (_box.containsKey('user_playlists')) {
      final cached = (_box.get('user_playlists') as List)
          .map((e) => Playlist.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      cached.insert(0, playlist);
      await _box.put('user_playlists', cached.map((e) => e.toMap()).toList());
    }

    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    try {
      await _supabase
          .from('playlists')
          .delete()
          .eq('id', playlistId)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint("Error deleting playlist online: $e");
    }

    // Invalidate/delete from local cache
    if (_box.containsKey('user_playlists')) {
      final cached = (_box.get('user_playlists') as List)
          .map((e) => Playlist.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      cached.removeWhere((p) => p.id == playlistId);
      await _box.put('user_playlists', cached.map((e) => e.toMap()).toList());
    }
    await _box.delete('playlist_tracks_$playlistId');
  }

  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async {
    try {
      final response = await _supabase
          .from('playlist_tracks')
          .select()
          .eq('playlist_id', playlistId)
          .order('added_at', ascending: false)
          .timeout(const Duration(seconds: 3));

      final data = response as List;
      final tracks = data
          .map(
            (item) => Track(
              id: item['track_id'] as String,
              title: item['title'] as String,
              artist: item['artist'] as String,
              thumbnailUrl: item['thumbnail_url'] as String,
              duration: Duration(
                seconds: item['duration_seconds'] as int? ?? 0,
              ),
              source: TrackSource.fromId(item['track_id'] as String),
            ),
          )
          .toList();

      // Cache tracks for this playlist
      await _box.put(
        'playlist_tracks_$playlistId',
        tracks.map((e) => e.toMap()).toList(),
      );

      return tracks;
    } catch (e) {
      if (_box.containsKey('playlist_tracks_$playlistId')) {
        final cached = _box.get('playlist_tracks_$playlistId') as List;
        return cached
            .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      rethrow;
    }
  }

  @override
  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    // 1. Update local cache immediately
    if (_box.containsKey('playlist_tracks_$playlistId')) {
      final cached = (_box.get('playlist_tracks_$playlistId') as List)
          .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      cached.insert(0, track);
      await _box.put(
        'playlist_tracks_$playlistId',
        cached.map((e) => e.toMap()).toList(),
      );
    }

    // 2. Sync online in background
    try {
      await _supabase.from('playlist_tracks').insert({
        'playlist_id': playlistId,
        'track_id': track.id,
        'title': track.title,
        'artist': track.artist,
        'thumbnail_url': track.thumbnailUrl,
        'duration_seconds': track.duration.inSeconds,
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint("Error syncing added track to Supabase: $e");
    }
  }

  @override
  Future<void> addTracksToPlaylist(String playlistId, List<Track> tracks) async {
    if (tracks.isEmpty) return;

    // 1. Update local cache immediately
    if (_box.containsKey('playlist_tracks_$playlistId')) {
      final cached = (_box.get('playlist_tracks_$playlistId') as List)
          .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      cached.insertAll(0, tracks);
      await _box.put(
        'playlist_tracks_$playlistId',
        cached.map((e) => e.toMap()).toList(),
      );
    }

    // 2. Sync online in background in a single batch insert
    try {
      final rows = tracks
          .map(
            (track) => {
              'playlist_id': playlistId,
              'track_id': track.id,
              'title': track.title,
              'artist': track.artist,
              'thumbnail_url': track.thumbnailUrl,
              'duration_seconds': track.duration.inSeconds,
            },
          )
          .toList();

      await _supabase
          .from('playlist_tracks')
          .insert(rows)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint("Error syncing batch added tracks to Supabase: $e");
    }
  }

  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    // 1. Update local cache immediately
    if (_box.containsKey('playlist_tracks_$playlistId')) {
      final cached = (_box.get('playlist_tracks_$playlistId') as List)
          .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      cached.removeWhere((t) => t.id == trackId);
      await _box.put(
        'playlist_tracks_$playlistId',
        cached.map((e) => e.toMap()).toList(),
      );
    }

    // 2. Sync online in background
    try {
      await _supabase
          .from('playlist_tracks')
          .delete()
          .eq('playlist_id', playlistId)
          .eq('track_id', trackId)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint("Error syncing removed track to Supabase: $e");
    }
  }

  @override
  Future<List<String>> getPlaylistsContainingTrack(String trackId) async {
    try {
      final response = await _supabase
          .from('playlist_tracks')
          .select('playlist_id')
          .eq('track_id', trackId)
          .timeout(const Duration(seconds: 3));

      final data = response as List;
      return data.map((e) => e['playlist_id'] as String).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> savePlaylistsOrder(List<String> playlistIds) async {
    await _box.put('playlist_custom_order', playlistIds);
  }

  @override
  Future<List<String>> getPlaylistsOrder() async {
    if (_box.containsKey('playlist_custom_order')) {
      final list = _box.get('playlist_custom_order');
      if (list is List) {
        return list.cast<String>();
      }
    }
    return [];
  }

  @override
  Future<void> savePlaylistSortType(String sortType) async {
    await _box.put('playlist_sort_type', sortType);
  }

  @override
  Future<String?> getPlaylistSortType() async {
    return _box.get('playlist_sort_type') as String?;
  }
}
