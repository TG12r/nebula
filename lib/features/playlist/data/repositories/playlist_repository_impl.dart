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
          .order('created_at', ascending: false);

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

      return playlists;
    } catch (e) {
      // Return cached data if available
      if (_box.containsKey('user_playlists')) {
        final cached = _box.get('user_playlists') as List;
        return cached
            .map((e) => Playlist.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
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
        .single();

    final playlist = Playlist(
      id: response['id'] as String,
      name: response['name'] as String,
      userId: response['user_id'] as String,
    );

    // Ideally update cache here or invalidate, but getPlaylists will refresh it.
    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _supabase.from('playlists').delete().eq('id', playlistId);
    // Invalidate cache implicitly or handle manually
    // For now, re-fetch will handle it, or we could remove from box map.
  }

  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async {
    try {
      final response = await _supabase
          .from('playlist_tracks')
          .select()
          .eq('playlist_id', playlistId)
          .order('added_at', ascending: false);

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
    await _supabase.from('playlist_tracks').insert({
      'playlist_id': playlistId,
      'track_id': track.id,
      'title': track.title,
      'artist': track.artist,
      'thumbnail_url': track.thumbnailUrl,
      'duration_seconds': track.duration.inSeconds,
    });
  }

  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await _supabase
        .from('playlist_tracks')
        .delete()
        .eq('playlist_id', playlistId)
        .eq('track_id', trackId);
  }

  @override
  Future<List<String>> getPlaylistsContainingTrack(String trackId) async {
    // This is less critical for offline usually, but could also be cached.
    // For now keeping online-only or simple.
    try {
      final response = await _supabase
          .from('playlist_tracks')
          .select('playlist_id')
          .eq('track_id', trackId);

      final data = response as List;
      return data.map((e) => e['playlist_id'] as String).toList();
    } catch (e) {
      return [];
    }
  }
}
