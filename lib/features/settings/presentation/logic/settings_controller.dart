import 'package:flutter/material.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  final SettingsRepository _repository;

  SettingsController(this._repository);

  // Local State Cache
  late bool _highQuality;
  late bool _gapless;
  late bool _metrics;
  late bool _isDarkMode;

  bool get highQuality => _highQuality;
  bool get gapless => _gapless;
  bool get metrics => _metrics;
  bool get isDarkMode => _isDarkMode;

  // Init called typically after repository is ready or in constructor if repo is sync-ready
  // But repo.init() is async.
  // Ideally, we load initial values when controller is created assuming repo is ready.
  // We'll expose a load method.

  void loadSettings() {
    _highQuality = _repository.highAudioQuality;
    _gapless = _repository.gaplessPlayback;
    _metrics = _repository.anonymousMetrics;
    _isDarkMode = _repository.isDarkMode;
    notifyListeners();
  }

  Future<void> toggleHighQuality(bool value) async {
    _highQuality = value;
    notifyListeners();
    await _repository.setHighAudioQuality(value);
  }

  Future<void> toggleGapless(bool value) async {
    _gapless = value;
    notifyListeners();
    await _repository.setGaplessPlayback(value);
  }

  Future<void> toggleMetrics(bool value) async {
    _metrics = value;
    notifyListeners();
    await _repository.setAnonymousMetrics(value);
  }

  Future<void> toggleTheme(bool isDark) async {
    _isDarkMode = isDark;
    notifyListeners();
    await _repository.setDarkMode(isDark);
  }
}
