import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  final SupabaseClient _supabase;

  PlaylistRepositoryImpl(this._supabase);

  String get _userId => _supabase.auth.currentUser!.id;

  @override
  Future<List<Playlist>> getPlaylists() async {
    final response = await _supabase
        .from('playlists')
        .select('*, playlist_tracks(count)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);

    final data = response as List;
    return data.map((item) {
      // Extract count from join if possible, or defaulting to 0
      // Note: playlist_tracks(count) returns a list of objects like [{count: 1}]
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
        trackCount: count, // Simplified for now, mapped correctly?
        // Supabase select with count is tricky.
        // Alternative: Just select from playlists and ignore count for MVP speed or fix query.
        // Let's use basic select for now.
      );
    }).toList();
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final response = await _supabase
        .from('playlists')
        .insert({'user_id': _userId, 'name': name})
        .select()
        .single();

    return Playlist(
      id: response['id'] as String,
      name: response['name'] as String,
      userId: response['user_id'] as String,
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _supabase.from('playlists').delete().eq('id', playlistId);
  }

  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async {
    final response = await _supabase
        .from('playlist_tracks')
        .select()
        .eq('playlist_id', playlistId)
        .order('added_at', ascending: false);

    final data = response as List;
    return data
        .map(
          (item) => Track(
            id: item['track_id'] as String,
            title: item['title'] as String,
            artist: item['artist'] as String,
            thumbnailUrl: item['thumbnail_url'] as String,
            duration: Duration(seconds: item['duration_seconds'] as int? ?? 0),
          ),
        )
        .toList();
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
    final response = await _supabase
        .from('playlist_tracks')
        .select('playlist_id')
        .eq('track_id', trackId);

    final data = response as List;
    return data.map((e) => e['playlist_id'] as String).toList();
  }
}
