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
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  static const int minValidFileBytes = 10240; // 10 KB minimum valid audio size

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

  String? _findStoredKey(String trackId) {
    // 1. Check exact key
    if (_box.containsKey(trackId)) return trackId;

    // 2. Check stripped key
    final safeId = TrackSource.stripPrefix(trackId);
    if (safeId != trackId && _box.containsKey(safeId)) {
      return safeId;
    }

    // 3. Check prefixed keys if input is raw
    if (!trackId.startsWith('yt:') && !trackId.startsWith('sc:')) {
      final ytKey = 'yt:$trackId';
      if (_box.containsKey(ytKey)) return ytKey;

      final scKey = 'sc:$trackId';
      if (_box.containsKey(scKey)) return scKey;
    }

    return null;
  }

  @override
  bool isDownloaded(String trackId) {
    final key = _findStoredKey(trackId);
    if (key == null) return false;

    final path = _box.get(key);
    if (path != null) {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() >= minValidFileBytes) {
        return true;
      }
    }

    // Cleanup if record exists but file is missing or corrupted
    if (path != null) {
      _box.delete(key);
      final safeId = TrackSource.stripPrefix(trackId);
      _box.delete(safeId);
      _box.delete('yt:$safeId');
      _box.delete('sc:$safeId');
    }
    return false;
  }

  @override
  String? getLocalPath(String trackId) {
    final key = _findStoredKey(trackId);
    if (key == null) return null;

    final path = _box.get(key);
    if (path != null) {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() >= minValidFileBytes) {
        return path;
      }
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
    String? tempPath;

    try {
      final customDir = _settingsRepository.downloadPath;
      final Directory dir;
      if (customDir != null && await Directory(customDir).exists()) {
        dir = Directory(customDir);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final safeTitle = TrackSource.stripPrefix(track.id);
      int totalBytes = -1;
      int receivedBytes = 0;

      if (track.source == TrackSource.soundcloud) {
        // --- SoundCloud Download ---
        final streamUrl = await _scRepository.getStreamUrl(track.id);
        if (streamUrl == null) {
          throw Exception("Could not get SoundCloud stream URL");
        }

        savePath = '${dir.path}/sc_$safeTitle.mp3';
        tempPath = '$savePath.part';
        final tempFile = File(tempPath);
        final fileSink = tempFile.openWrite();
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);

        try {
          final request = await client.getUrl(Uri.parse(streamUrl));
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception(
              "SoundCloud download HTTP error: ${response.statusCode}",
            );
          }

          totalBytes = response.contentLength;
          var lastNotifTime = DateTime.now();

          await for (final data in response) {
            fileSink.add(data);
            receivedBytes += data.length;
            if (totalBytes > 0) {
              final progress = (receivedBytes / totalBytes).clamp(0.0, 0.99);
              controller.add(progress);
              if (DateTime.now().difference(lastNotifTime).inMilliseconds >
                  500) {
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
        } finally {
          await fileSink.close();
          client.close();
        }

        // If SoundCloud returned an HLS (#EXTM3U) playlist (common on 20+ minute mixes/sets),
        // download and concatenate all audio segments into a contiguous .mp3 file.
        final probeBytes = await tempFile.openRead(0, 10).fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        final probeHeader = String.fromCharCodes(probeBytes).trim();
        if (probeHeader.startsWith('#EXTM3U')) {
          final manifestText = await tempFile.readAsString();
          final segmentUris = _parseHlsSegments(
            manifestText,
            Uri.parse(streamUrl),
          );
          if (segmentUris.isEmpty) {
            throw Exception(
              "HLS manifest for ${track.title} contains no downloadable audio segments",
            );
          }

          debugPrint(
            "SoundCloud: Downloading ${segmentUris.length} HLS audio segments for ${track.title}...",
          );
          final segSink = tempFile.openWrite();
          final segClient = HttpClient()
            ..connectionTimeout = const Duration(seconds: 15);
          totalBytes = -1;
          receivedBytes = 0;
          var lastNotifTime = DateTime.now();

          try {
            for (int i = 0; i < segmentUris.length; i++) {
              final segReq = await segClient.getUrl(segmentUris[i]);
              final segRes = await segReq.close();
              if (segRes.statusCode < 200 || segRes.statusCode >= 300) {
                throw Exception(
                  "SoundCloud HLS segment $i HTTP error: ${segRes.statusCode}",
                );
              }
              await for (final chunk in segRes) {
                segSink.add(chunk);
                receivedBytes += chunk.length;
              }
              final progress = ((i + 1) / segmentUris.length).clamp(0.0, 0.99);
              controller.add(progress);
              if (DateTime.now().difference(lastNotifTime).inMilliseconds >
                  500) {
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
            await segSink.flush();
          } finally {
            await segSink.close();
            segClient.close();
          }
        }
      } else {
        // --- YouTube Download ---
        final manifest = await _yt.videos.streamsClient.getManifest(track.rawId);

        // Prefer the highest-bitrate MP4/M4A (AAC-LC) stream so long 20+ minute
        // tracks have maximum compatibility with Android ExoPlayer's local MP4 extractor.
        final mp4Streams = manifest.audioOnly.where(
          (s) =>
              s.container.name.toLowerCase() == 'm4a' ||
              s.container.name.toLowerCase() == 'mp4',
        );
        final yt_lib.AudioOnlyStreamInfo audioStream = mp4Streams.isNotEmpty
            ? mp4Streams.withHighestBitrate()
            : manifest.audioOnly.withHighestBitrate();

        final extension = audioStream.container.name;
        savePath = '${dir.path}/yt_$safeTitle.$extension';
        tempPath = '$savePath.part';

        final stream = _yt.videos.streamsClient.get(audioStream);
        final tempFile = File(tempPath);
        final fileSink = tempFile.openWrite();

        try {
          totalBytes = audioStream.size.totalBytes;
          var lastNotifTime = DateTime.now();

          await for (final data in stream) {
            fileSink.add(data);
            receivedBytes += data.length;
            if (totalBytes > 0) {
              final progress = (receivedBytes / totalBytes).clamp(0.0, 0.99);
              controller.add(progress);
              if (DateTime.now().difference(lastNotifTime).inMilliseconds >
                  500) {
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
        } finally {
          await fileSink.close();
        }
      }

      // 3. Verify integrity before committing
      if (totalBytes > 0 && receivedBytes < totalBytes) {
        throw Exception(
          "Incomplete download for ${track.title}: received $receivedBytes of $totalBytes bytes",
        );
      }

      final tempFile = File(tempPath);
      final writtenSize = await tempFile.length();
      if (writtenSize < minValidFileBytes) {
        throw Exception(
          "Downloaded file for ${track.title} is too small ($writtenSize bytes)",
        );
      }

      final firstBytes = await tempFile.openRead(0, 10).fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );
      final header = String.fromCharCodes(firstBytes).trim();
      if (header.startsWith('#EXTM3U')) {
        throw Exception(
          "Downloaded content for ${track.title} is an HLS manifest (#EXTM3U), not a direct audio file",
        );
      }

      final finalFile = File(savePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(savePath);

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
      if (controller.hasListener) {
        controller.addError(e);
      }
      _progressControllers[track.id]?.close();
      _progressControllers.remove(track.id);
      try {
        await NotificationService().cancel(notifId);
      } catch (_) {}

      // Cleanup temporary and partial files
      for (final path in [tempPath, savePath]) {
        if (path != null) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {
            // Ignore cleanup errors
          }
        }
      }
    }
  }

  @override
  Future<void> deleteTrack(String trackId) async {
    final key = _findStoredKey(trackId);
    String? path;
    if (key != null) {
      path = _box.get(key);
      await _box.delete(key);
    }

    // Cleanup other potential aliases
    final safeId = TrackSource.stripPrefix(trackId);
    await _box.delete(safeId);
    await _box.delete('yt:$safeId');
    await _box.delete('sc:$safeId');

    if (path != null) {
      for (final targetPath in [path, '$path.part']) {
        try {
          final file = File(targetPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint("Error deleting file: $e");
        }
      }
    }
  }

  List<Uri> _parseHlsSegments(String manifestContent, Uri baseUri) {
    final segments = <Uri>[];
    final lines = manifestContent.split(RegExp(r'\r?\n'));
    final mapRegex = RegExp(r'#EXT-X-MAP:.*URI="([^"]+)"');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final match = mapRegex.firstMatch(line);
        if (match != null && match.group(1) != null) {
          segments.add(baseUri.resolve(match.group(1)!));
        }
        continue;
      }
      segments.add(baseUri.resolve(line));
    }
    return segments;
  }

  StreamController<double> _getProgressController(String trackId) {
    if (!_progressControllers.containsKey(trackId)) {
      _progressControllers[trackId] = StreamController<double>.broadcast();
    }
    return _progressControllers[trackId]!;
  }
}
