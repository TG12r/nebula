import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

class DownloadController extends ChangeNotifier {
  final DownloadRepository _repository;

  DownloadController(this._repository);

  // Track ID -> Progress (0.0 - 1.0)
  final Map<String, double> _downloadProgress = {};

  // Track IDs currently downloading
  final Set<String> _activeDownloads = {};

  bool isDownloaded(String trackId) => _repository.isDownloaded(trackId);

  bool isDownloading(String trackId) => _activeDownloads.contains(trackId);

  double getProgress(String trackId) => _downloadProgress[trackId] ?? 0.0;

  Future<void> downloadTrack(Track track) async {
    if (_repository.isDownloaded(track.id)) return;
    if (_activeDownloads.contains(track.id)) return;

    _activeDownloads.add(track.id);
    _downloadProgress[track.id] = 0.0;
    notifyListeners();

    // Listen to progress
    final subscription = _repository.getDownloadProgress(track.id).listen((
      progress,
    ) {
      _downloadProgress[track.id] = progress;
      notifyListeners();
    });

    try {
      await _repository.downloadTrack(track);
    } catch (e) {
      debugPrint("Download error for ${track.title}: $e");
    } finally {
      // Cleanup
      await subscription.cancel();
      _activeDownloads.remove(track.id);
      _downloadProgress.remove(track.id); // Or keep 1.0?
      notifyListeners();
    }
  }

  Future<void> deleteTrack(String trackId) async {
    await _repository.deleteTrack(trackId);
    notifyListeners();
  }

  /// Download multiple tracks sequentially
  Future<void> downloadPlaylist(List<Track> tracks) async {
    for (var track in tracks) {
      if (!isDownloaded(track.id) && !isDownloading(track.id)) {
        await downloadTrack(track);
      }
    }
  }
}
