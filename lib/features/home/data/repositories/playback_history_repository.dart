import 'package:hive_flutter/hive_flutter.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'dart:convert';

class PlaybackHistoryRepository {
  final Box _box;

  PlaybackHistoryRepository(this._box);

  // Store history as list of JSON strings (to reuse Track.fromMap)
  static const String _kHistoryKey = 'playback_history_list';
  static const int _kMaxHistorySize = 20;

  List<Track> getHistory() {
    final List<dynamic> rawList = _box.get(_kHistoryKey, defaultValue: []);
    // Convert JSON strings/Maps back to Track objects
    return rawList.map((e) {
      if (e is String) {
        return Track.fromMap(jsonDecode(e));
      }
      return Track.fromMap(Map<String, dynamic>.from(e));
    }).toList();
  }

  Future<void> addToHistory(Track track) async {
    final List<Track> currentHistory = getHistory();

    // Remove if already exists (move to top)
    currentHistory.removeWhere((t) => t.id == track.id);

    // Add to start
    currentHistory.insert(0, track);

    // Trim size
    if (currentHistory.length > _kMaxHistorySize) {
      currentHistory.removeLast();
    }

    // Convert back to JSON for storage
    final List<Map<String, dynamic>> jsonList = currentHistory
        .map((t) => t.toMap())
        .toList();

    await _box.put(_kHistoryKey, jsonList);
  }

  Future<void> clearHistory() async {
    await _box.delete(_kHistoryKey);
  }
}
