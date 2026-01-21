import 'package:flutter/foundation.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:file_picker/file_picker.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;
  // We need generic access, but we can't import the Repo impl here.
  // We should depend on the interface.
  // Ideally this would be clean architecture, but for speed:
  // We will assume the controller is passed the abstract repo.
  // But wait, circular dependency?
  // SettingsRepo -> ...
  // DownloadRepo -> SettingsRepo.
  // SettingsController -> SettingsRepo, DownloadRepo.
  // This is fine.
  final dynamic
  _downloadRepository; // Using dynamic to avoid import cycles if any, or just import it.

  SettingsController(this._repository, this._downloadRepository);

  // Theme
  bool get isDarkMode => _repository.isDarkMode;

  Future<void> toggleTheme() async {
    await _repository.setDarkMode(!isDarkMode);
    notifyListeners();
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

  // Downloads
  String? get downloadPath => _repository.downloadPath;

  bool _isMigrating = false;
  bool get isMigrating => _isMigrating;

  Future<void> pickDownloadPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        await _repository.setDownloadPath(selectedDirectory);

        // Trigger migration
        if (_downloadRepository is DownloadRepository) {
          _isMigrating = true;
          notifyListeners();

          try {
            await (_downloadRepository as DownloadRepository).moveDownloads(
              selectedDirectory,
            );
          } catch (e) {
            debugPrint("Migration error: $e");
          } finally {
            _isMigrating = false;
          }
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error picking directory: $e");
      // On Linux/Windows this might fail if native dialogs aren't available
      // We could relay this error to the UI if needed, but for now just preventing crash
    }
  }

  // Initial Load (mostly for syncing, though repo is sync-ish)
  Future<void> loadSettings() async {
    notifyListeners();
  }
}
