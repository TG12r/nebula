import 'package:shared_preferences/shared_preferences.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Keys
  static const String _kHighQuality = 'settings_high_quality';
  static const String _kGapless = 'settings_gapless';
  static const String _kMetrics = 'settings_metrics';

  @override
  bool get highAudioQuality => _prefs?.getBool(_kHighQuality) ?? true;

  @override
  Future<void> setHighAudioQuality(bool value) async {
    await _prefs?.setBool(_kHighQuality, value);
  }

  @override
  bool get gaplessPlayback => _prefs?.getBool(_kGapless) ?? true;

  @override
  Future<void> setGaplessPlayback(bool value) async {
    await _prefs?.setBool(_kGapless, value);
  }

  @override
  bool get anonymousMetrics => _prefs?.getBool(_kMetrics) ?? false; // Default off

  @override
  Future<void> setAnonymousMetrics(bool value) async {
    await _prefs?.setBool(_kMetrics, value);
  }

  // Theme
  static const String _kIsDarkMode = 'settings_is_dark_mode';

  @override
  bool get isDarkMode => _prefs?.getBool(_kIsDarkMode) ?? true; // Default Dark

  @override
  Future<void> setDarkMode(bool value) async {
    await _prefs?.setBool(_kIsDarkMode, value);
  }
}
