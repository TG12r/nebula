import 'package:hive_flutter/hive_flutter.dart';

class SearchHistoryRepository {
  final Box _box;

  SearchHistoryRepository(this._box);

  List<String> getHistory() {
    return _box.values.toList().cast<String>().reversed.toList();
  }

  Future<void> addQuery(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    // Remove if exists to move to top (deduplicate)
    final Map<dynamic, dynamic> entries = _box.toMap();
    for (var key in entries.keys) {
      if (entries[key] == cleanQuery) {
        await _box.delete(key);
        break;
      }
    }

    await _box.add(cleanQuery);

    // Limit to last 20 queries
    if (_box.length > 20) {
      await _box.deleteAt(0); // Delete oldest
    }
  }

  Future<void> deleteQuery(String query) async {
    final Map<dynamic, dynamic> entries = _box.toMap();
    for (var key in entries.keys) {
      if (entries[key] == query) {
        await _box.delete(key);
        break;
      }
    }
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
