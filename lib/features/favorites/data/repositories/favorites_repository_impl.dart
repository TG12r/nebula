import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  final SupabaseClient _supabase;

  FavoritesRepositoryImpl(this._supabase);

  String get _userId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user.id;
  }

  @override
  Future<List<Track>> getFavorites() async {
    final response = await _supabase
        .from('favorites')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false);

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
  Future<bool> isFavorite(String trackId) async {
    final response = await _supabase
        .from('favorites')
        .select('id')
        .eq('user_id', _userId)
        .eq('track_id', trackId)
        .maybeSingle();

    return response != null;
  }

  @override
  Future<void> toggleFavorite(Track track) async {
    final exists = await isFavorite(track.id);

    if (exists) {
      await _supabase
          .from('favorites')
          .delete()
          .eq('user_id', _userId)
          .eq('track_id', track.id);
    } else {
      await _supabase.from('favorites').insert({
        'user_id': _userId,
        'track_id': track.id,
        'title': track.title,
        'artist': track.artist,
        'thumbnail_url': track.thumbnailUrl,
        'duration_seconds': track.duration.inSeconds,
      });
    }
  }
}
