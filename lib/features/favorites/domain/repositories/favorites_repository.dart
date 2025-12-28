import 'package:nebula/features/player/domain/entities/track.dart';

abstract class FavoritesRepository {
  Future<void> toggleFavorite(Track track);
  Future<bool> isFavorite(String trackId);
  Future<List<Track>> getFavorites();
}
