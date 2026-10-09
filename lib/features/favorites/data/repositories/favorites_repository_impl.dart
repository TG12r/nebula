import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/core/enums/track_source.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  final SupabaseClient _supabase;
  final Box? _box;

  FavoritesRepositoryImpl(this._supabase, [this._box]);

  String get _userId {
    final user = _supabase.auth.currentUser;
    return user?.id ?? '';
  }

  @override
  Future<List<Track>> getFavorites() async {
    try {
      if (_supabase.auth.currentUser == null) {
        throw Exception('User not logged in');
      }

      final response = await _supabase
          .from('favorites')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 3));

      final data = response as List;
      final tracks = data
          .map(
            (item) => Track(
              id: item['track_id'] as String,
              title: item['title'] as String,
              artist: item['artist'] as String,
              thumbnailUrl: item['thumbnail_url'] as String,
              duration: Duration(seconds: item['duration_seconds'] as int? ?? 0),
              source: TrackSource.fromId(item['track_id'] as String),
            ),
          )
          .toList();

      // Cache locally for instant offline fallback
      if (_box != null) {
        await _box.put('user_favorites', tracks.map((t) => t.toMap()).toList());
      }

      return tracks;
    } catch (e) {
      debugPrint("FavoritesRepository: Network fetch failed or timed out ($e), checking Hive cache...");
      if (_box != null && _box.containsKey('user_favorites')) {
        final cached = _box.get('user_favorites') as List;
        return cached
            .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    }
  }

  @override
  Future<bool> isFavorite(String trackId) async {
    // Fast path: check local Hive cache first
    if (_box != null && _box.containsKey('user_favorites')) {
      final cached = _box.get('user_favorites') as List;
      final exists = cached.any((e) => (e as Map)['id'] == trackId);
      if (exists) return true;
    }

    try {
      final response = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', _userId)
          .eq('track_id', trackId)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));

      return response != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> toggleFavorite(Track track) async {
    bool isCurrentlyFav = false;

    // Check memory/cache
    if (_box != null && _box.containsKey('user_favorites')) {
      final cached = (_box.get('user_favorites') as List)
          .map((e) => Track.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final index = cached.indexWhere((t) => t.id == track.id);
      if (index != -1) {
        isCurrentlyFav = true;
        cached.removeAt(index);
      } else {
        isCurrentlyFav = false;
        cached.insert(0, track);
      }
      await _box.put('user_favorites', cached.map((t) => t.toMap()).toList());
    }

    try {
      if (isCurrentlyFav) {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', _userId)
            .eq('track_id', track.id)
            .timeout(const Duration(seconds: 3));
      } else {
        await _supabase.from('favorites').insert({
          'user_id': _userId,
          'track_id': track.id,
          'title': track.title,
          'artist': track.artist,
          'thumbnail_url': track.thumbnailUrl,
          'duration_seconds': track.duration.inSeconds,
        }).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      debugPrint("FavoritesRepository: Background Supabase sync failed: $e");
    }
  }
}
