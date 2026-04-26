import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:nebula/core/enums/track_source.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  final DownloadRepository _downloadRepository;

  SettingsController(this._repository, this._downloadRepository);

  // Migration state
  bool _isMigrating = false;
  bool get isMigrating => _isMigrating;

  double _migrationProgress = 0.0;
  double get migrationProgress => _migrationProgress;

  String _migrationStatus = '';
  String get migrationStatus => _migrationStatus;

  // Theme
  bool get isDarkMode => _repository.isDarkMode;

  Future<void> toggleTheme() async {
    await _repository.setDarkMode(!isDarkMode);
    notifyListeners();
  }

  // Search
  TrackSource get searchSource => _repository.searchSource;

  Future<void> setSearchSource(TrackSource source) async {
    await _repository.setSearchSource(source);
    notifyListeners();
  }

  // Storage
  String? get downloadPath => _repository.downloadPath;

  Future<void> pickAndMigrateFolder() async {
    if (_isMigrating) return;

    // Android Permission handling
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isDenied) {
        // This will open the system settings page for "All Files Access" on Android 11+
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) return;
      }
    }

    String? selectedDirectory = await FilePicker.getDirectoryPath();

    if (selectedDirectory != null) {
      // Start migration
      _isMigrating = true;
      _migrationProgress = 0.0;
      _migrationStatus = 'Preparing to move files...';
      notifyListeners();

      try {
        final downloads = _downloadRepository.getAllDownloads();
        final total = downloads.length;

        if (total == 0) {
          // No files to move, just update path
          await _repository.setDownloadPath(selectedDirectory);
        } else {
          int count = 0;
          for (var entry in downloads.entries) {
            final trackId = entry.key;
            final oldPath = entry.value;

            _migrationStatus = 'Moving track ${count + 1} of $total...';
            notifyListeners();

            final file = File(oldPath);
            if (await file.exists()) {
              final fileName = p.basename(oldPath);
              final newPath = p.join(selectedDirectory, fileName);

              // Skip if same path
              if (oldPath != newPath) {
                // Copy and Delete (safer than rename across partitions)
                final newFile = await file.copy(newPath);
                if (await newFile.exists()) {
                  await file.delete();
                }
                // Update Hive
                await _downloadRepository.updateDownloadPath(trackId, newPath);
              }
            }

            count++;
            _migrationProgress = count / total;
            notifyListeners();
          }

          await _repository.setDownloadPath(selectedDirectory);
        }
        _migrationStatus = 'Migration complete!';
      } catch (e) {
        debugPrint("Migration error: $e");
        _migrationStatus = 'Error during migration: $e';
      } finally {
        // Wait a bit to show 100%
        await Future.delayed(const Duration(seconds: 1));
        _isMigrating = false;
        notifyListeners();
      }
    }
  }

  // Image Quality
  ImageQuality get imageQuality => _repository.imageQuality;

  Future<void> setImageQuality(ImageQuality quality) async {
    await _repository.setImageQuality(quality);
    notifyListeners();
  }

  // Audio Quality
  bool get highQuality => _repository.highAudioQuality;

  Future<void> toggleHighQuality() async {
    await _repository.setHighAudioQuality(!highQuality);
    notifyListeners();
  }

  // Gapless
  bool get gapless => _repository.gaplessPlayback;

  Future<void> toggleGapless() async {
    await _repository.setGaplessPlayback(!gapless);
    notifyListeners();
  }

  // Metrics
  bool get anonymousMetrics => _repository.anonymousMetrics;

  Future<void> toggleAnonymousMetrics() async {
    await _repository.setAnonymousMetrics(!anonymousMetrics);
    notifyListeners();
  }

  // Initial Load (mostly for syncing, though repo is sync-ish)
  Future<void> loadSettings() async {
    notifyListeners();
  }
}
