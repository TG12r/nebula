import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;
import 'package:nebula/core/services/notification_service.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  final Box _box;

  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  // Progress controllers: {trackId: StreamController}
  final Map<String, StreamController<double>> _progressControllers = {};

  DownloadRepositoryImpl(this._box);

  @override
  bool isDownloaded(String trackId) {
    final path = _box.get(trackId);
    if (path != null && File(path).existsSync()) {
      return true;
    }
    // Cleanup if file missing
    if (path != null) {
      _box.delete(trackId);
    }
    return false;
  }

  @override
  String? getLocalPath(String trackId) {
    if (isDownloaded(trackId)) {
      return _box.get(trackId);
    }
    return null;
  }

  @override
  Stream<double> getDownloadProgress(String trackId) {
    if (!_progressControllers.containsKey(trackId)) {
      _progressControllers[trackId] = StreamController<double>.broadcast();
    }
    return _progressControllers[trackId]!.stream;
  }

  @override
  Future<void> downloadTrack(Track track) async {
    if (isDownloaded(track.id)) return;

    final controller = _getProgressController(track.id);
    controller.add(0.01); // Started

    // Notification ID (hash code of ID for simplicity)
    final notifId = track.id.hashCode;
    await NotificationService().showProgress(
      notifId,
      "Downloading ${track.title}",
      "Starting...",
      0,
      100,
    );

    String? savePath;

    try {
      // 1. Get Audio URL with specific client
      final manifest = await _yt.videos.streamsClient.getManifest(
        track.id,
        ytClients: [yt_lib.YoutubeApiClient.androidVr],
      );

      yt_lib.AudioOnlyStreamInfo? audioStream;
      try {
        audioStream = manifest.audioOnly.firstWhere(
          (s) =>
              s.container.name.toLowerCase() == 'm4a' ||
              s.container.name.toLowerCase() == 'mp4',
        );
      } catch (_) {}
      audioStream ??= manifest.audioOnly.withHighestBitrate();

      // 2. Prepare File Path
      final dir = await getApplicationDocumentsDirectory();
      // Use sanitize simple approach
      final safeTitle = track.id; // using ID for filename is safer than title
      final extension = audioStream.container.name;
      savePath = '${dir.path}/$safeTitle.$extension';

      // 3. Download using YoutubeExplode Stream (Avoids Dio 403)
      final stream = _yt.videos.streamsClient.get(audioStream);
      final file = File(savePath);
      final fileSink = file.openWrite();

      final totalBytes = audioStream.size.totalBytes;
      var receivedBytes = 0;
      var lastNotifTime = DateTime.now();

      await for (final data in stream) {
        // Write chunk
        fileSink.add(data);

        // Update progress
        receivedBytes += data.length;
        if (totalBytes != 0) {
          final progress = receivedBytes / totalBytes;
          controller.add(progress);

          // Throttle notifications to every 500ms
          if (DateTime.now().difference(lastNotifTime).inMilliseconds > 500) {
            NotificationService().showProgress(
              notifId,
              "Downloading ${track.title}",
              "${(progress * 100).toInt()}%",
              (progress * 100).toInt(),
              100,
            );
            lastNotifTime = DateTime.now();
          }
        }
      }

      // Close file
      await fileSink.flush();
      await fileSink.close();

      // 4. Save to Hive
      await _box.put(track.id, savePath);
      controller.add(1.0); // Done

      // Completion Notification
      await NotificationService().showCompletion(
        notifId,
        "Download Complete",
        track.title,
      );

      // Close controller after delay
      Future.delayed(const Duration(seconds: 1), () {
        _progressControllers[track.id]?.close();
        _progressControllers.remove(track.id);
      });
    } catch (e) {
      debugPrint("Download failed: $e");
      controller.addError(e);
      _progressControllers[track.id]?.close();
      _progressControllers.remove(track.id);
      await NotificationService().cancel(notifId); // Or show error

      // Cleanup partial file
      if (savePath != null) {
        try {
          final file = File(savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    }
  }

  @override
  Future<void> deleteTrack(String trackId) async {
    final path = _box.get(trackId);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Error deleting file: $e");
      }
    }
    await _box.delete(trackId);
  }

  StreamController<double> _getProgressController(String trackId) {
    if (!_progressControllers.containsKey(trackId)) {
      _progressControllers[trackId] = StreamController<double>.broadcast();
    }
    return _progressControllers[trackId]!;
  }
}
