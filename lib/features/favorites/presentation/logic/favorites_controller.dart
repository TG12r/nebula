import 'package:flutter/foundation.dart';
import 'package:nebula/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

class FavoritesController extends ChangeNotifier {
  final FavoritesRepository _repository;

  final Set<String> _favoriteIds = {};
  List<Track> _favoritesList = [];

  bool _isLoading = false;

  FavoritesController(this._repository) {
    _loadFavorites();
  }

  List<Track> get favorites => _favoritesList;
  bool get isLoading => _isLoading;

  Future<void> _loadFavorites() async {
    _isLoading = true;
    notifyListeners();
    try {
      final favs = await _repository.getFavorites();
      _favoritesList = favs;
      _favoriteIds.clear();
      _favoriteIds.addAll(favs.map((t) => t.id));
    } catch (e) {
      debugPrint("Error loading favorites: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isFavorite(String trackId) {
    return _favoriteIds.contains(trackId);
  }

  Future<void> toggleFavorite(Track track) async {
    // Optimistic Update
    final isFav = _favoriteIds.contains(track.id);
    if (isFav) {
      _favoriteIds.remove(track.id);
      _favoritesList.removeWhere((t) => t.id == track.id);
    } else {
      _favoriteIds.add(track.id);
      _favoritesList.insert(0, track);
    }
    notifyListeners();

    try {
      await _repository.toggleFavorite(track);
    } catch (e) {
      // Revert if error
      if (isFav) {
        _favoriteIds.add(track.id);
        _favoritesList.insert(0, track);
      } else {
        _favoriteIds.remove(track.id);
        _favoritesList.removeWhere((t) => t.id == track.id);
      }
      notifyListeners();
      debugPrint("Error toggling favorite: $e");
    }
  }
}
