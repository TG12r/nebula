import 'package:nebula/features/settings/domain/entities/image_quality.dart';

abstract class SettingsRepository {
  Future<void> init();

  // Image Quality
  ImageQuality get imageQuality;
  Future<void> setImageQuality(ImageQuality value);

  // Playback
  bool get highAudioQuality;
  Future<void> setHighAudioQuality(bool value);

  bool get gaplessPlayback;
  Future<void> setGaplessPlayback(bool value);

  // Privacy
  bool get anonymousMetrics;
  Future<void> setAnonymousMetrics(bool value);

  // Theme
  bool get isDarkMode;
  Future<void> setDarkMode(bool value);

  // Downloads
  String? get downloadPath;
  Future<void> setDownloadPath(String path);
}
