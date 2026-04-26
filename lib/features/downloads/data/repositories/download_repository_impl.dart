import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;
import 'package:nebula/core/services/notification_service.dart';

import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  final Box _box;
  final SettingsRepository _settingsRepository;
  final SoundCloudRepository _scRepository;

  final yt_lib.YoutubeExplode _yt = yt_lib.YoutubeExplode();

  // Progress controllers: {trackId: StreamController}
  final Map<String, StreamController<double>> _progressControllers = {};

  DownloadRepositoryImpl(
    this._box, 
    this._settingsRepository,
    this._scRepository,
  );

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
  Map<String, String> getAllDownloads() {
    final Map<String, String> downloads = {};
    for (var key in _box.keys) {
      final path = _box.get(key);
      if (path is String) {
        downloads[key.toString()] = path;
      }
    }
    return downloads;
  }

  @override
  Future<void> updateDownloadPath(String trackId, String newPath) async {
    await _box.put(trackId, newPath);
  }

  @override
  Future<void> downloadTrack(Track track) async {
    if (isDownloaded(track.id)) return;

    final controller = _getProgressController(track.id);
    controller.add(0.01); // Started

    // Notification ID (hash code of ID for simplicity)
    final notifId = track.id.hashCode;
    try {
      await NotificationService().showProgress(
        notifId,
        "Downloading ${track.title}",
        "Starting...",
        0,
        100,
      );
    } catch (e) {
      debugPrint("Notification error: $e");
    }

    String? savePath;

    try {
      final customDir = _settingsRepository.downloadPath;
      final Directory dir;
      if (customDir != null && await Directory(customDir).exists()) {
        dir = Directory(customDir);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final safeTitle = TrackSource.stripPrefix(track.id);
      
      if (track.source == TrackSource.soundcloud) {
        // --- SoundCloud Download ---
        final streamUrl = await _scRepository.getStreamUrl(track.id);
        if (streamUrl == null) throw Exception("Could not get SoundCloud stream URL");

        savePath = '${dir.path}/sc_${safeTitle}.mp3';
        final file = File(savePath);
        final fileSink = file.openWrite();

        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(streamUrl));
        final response = await request.close();

        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        var lastNotifTime = DateTime.now();

        await for (final data in response) {
          fileSink.add(data);
          receivedBytes += data.length;
          if (totalBytes != -1) {
            final progress = receivedBytes / totalBytes;
            controller.add(progress);
            if (DateTime.now().difference(lastNotifTime).inMilliseconds > 500) {
              try {
                NotificationService().showProgress(
                  notifId,
                  "Downloading ${track.title}",
                  "${(progress * 100).toInt()}%",
                  (progress * 100).toInt(),
                  100,
                );
              } catch (_) {}
              lastNotifTime = DateTime.now();
            }
          }
        }
        await fileSink.flush();
        await fileSink.close();
      } else {
        // --- YouTube Download ---
        final manifest = await _yt.videos.streamsClient.getManifest(
          track.rawId,
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

        final extension = audioStream.container.name;
        savePath = '${dir.path}/yt_${safeTitle}.$extension';

        final stream = _yt.videos.streamsClient.get(audioStream);
        final file = File(savePath);
        final fileSink = file.openWrite();

        final totalBytes = audioStream.size.totalBytes;
        var receivedBytes = 0;
        var lastNotifTime = DateTime.now();

        await for (final data in stream) {
          fileSink.add(data);
          receivedBytes += data.length;
          if (totalBytes != 0) {
            final progress = receivedBytes / totalBytes;
            controller.add(progress);
            if (DateTime.now().difference(lastNotifTime).inMilliseconds > 500) {
              try {
                NotificationService().showProgress(
                  notifId,
                  "Downloading ${track.title}",
                  "${(progress * 100).toInt()}%",
                  (progress * 100).toInt(),
                  100,
                );
              } catch (_) {}
              lastNotifTime = DateTime.now();
            }
          }
        }
        await fileSink.flush();
        await fileSink.close();
      }

      // 4. Save to Hive using storageId
      await _box.put(track.storageId, savePath);
      controller.add(1.0); // Done

      // Completion Notification
      try {
        await NotificationService().showCompletion(
          notifId,
          "Download Complete",
          track.title,
        );
      } catch (e) {
        // Ignore notification errors
      }

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
      try {
        await NotificationService().cancel(notifId);
      } catch (_) {}

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
