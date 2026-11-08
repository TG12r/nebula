import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:nebula/core/enums/track_source.dart';

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

  // Storage
  String? get downloadPath;
  Future<void> setDownloadPath(String? value);
  // Search Engine
  TrackSource get searchSource;
  Future<void> setSearchSource(TrackSource source);

  // Data Saver & Resource Consumption
  bool get dataSaver;
  Future<void> setDataSaver(bool value);

  int get lookaheadTracks;
  Future<void> setLookaheadTracks(int value);

  int get audioCacheLimitMb;
  Future<void> setAudioCacheLimitMb(int value);

  // Volume (0.0 to 1.0)
  double get volume;
  Future<void> setVolume(double value);
}
