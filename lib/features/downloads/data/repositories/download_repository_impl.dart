import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

class DownloadRepositoryImpl implements DownloadRepository {
  final Box _box;
  final Dio _dio = Dio();
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
      final savePath = '${dir.path}/$safeTitle.$extension';

      // 3. Download with Headers
      await _dio.download(
        audioStream.url.toString(),
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            controller.add(progress);
          }
        },
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3',
          },
        ),
      );

      // 4. Save to Hive
      await _box.put(track.id, savePath);
      controller.add(1.0); // Done

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
