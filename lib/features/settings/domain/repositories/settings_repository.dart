abstract class SettingsRepository {
  Future<void> init();

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
}
