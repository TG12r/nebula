import 'package:flutter/foundation.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;

  SettingsController(this._repository);

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

  // Initial Load (mostly for syncing, though repo is sync-ish)
  Future<void> loadSettings() async {
    notifyListeners();
  }
}
