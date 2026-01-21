import 'dart:async';
import 'package:nebula/features/player/domain/entities/track.dart';

abstract class DownloadRepository {
  /// Queue a track for download
  Future<void> downloadTrack(Track track);

  /// Delete a downloaded track
  Future<void> deleteTrack(String trackId);

  /// Check if a track is downloaded
  bool isDownloaded(String trackId);

  /// Get absolute path to local file
  String? getLocalPath(String trackId);

  /// Stream of download progress (0.0 to 1.0) for a specific track
  Stream<double> getDownloadProgress(String trackId);

  /// Move all downloaded files to a new directory
  Future<void> moveDownloads(String newPath);
}
