import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart';

class FakeSettingsRepository implements SettingsRepository {
  @override
  bool dataSaver = false;
  @override
  int lookaheadTracks = 2;
  @override
  int audioCacheLimitMb = 512;
  @override
  bool isDarkMode = true;
  @override
  bool highAudioQuality = false;
  @override
  bool gaplessPlayback = false;
  @override
  bool anonymousMetrics = false;
  @override
  ImageQuality imageQuality = ImageQuality.medium;
  @override
  TrackSource searchSource = TrackSource.youtube;
  @override
  String? downloadPath;
  @override
  double volume = 1.0;

  @override
  Future<void> init() async {}
  @override
  Future<void> setDataSaver(bool value) async => dataSaver = value;
  @override
  Future<void> setLookaheadTracks(int value) async => lookaheadTracks = value;
  @override
  Future<void> setAudioCacheLimitMb(int value) async => audioCacheLimitMb = value;
  @override
  Future<void> setDarkMode(bool value) async => isDarkMode = value;
  @override
  Future<void> setHighAudioQuality(bool value) async => highAudioQuality = value;
  @override
  Future<void> setGaplessPlayback(bool value) async => gaplessPlayback = value;
  @override
  Future<void> setAnonymousMetrics(bool value) async => anonymousMetrics = value;
  @override
  Future<void> setImageQuality(ImageQuality value) async => imageQuality = value;
  @override
  Future<void> setSearchSource(TrackSource source) async => searchSource = source;
  @override
  Future<void> setDownloadPath(String? value) async => downloadPath = value;
  @override
  Future<void> setVolume(double value) async => volume = value;
}

class FakeDownloadRepository implements DownloadRepository {
  @override
  Map<String, String> getAllDownloads() => {};
  @override
  Future<void> updateDownloadPath(String trackId, String newPath) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SettingsController Data Saver & Resource Controls', () {
    late FakeSettingsRepository fakeSettingsRepo;
    late FakeDownloadRepository fakeDownloadRepo;
    late SettingsController controller;

    setUp(() {
      fakeSettingsRepo = FakeSettingsRepository();
      fakeDownloadRepo = FakeDownloadRepository();
      controller = SettingsController(fakeSettingsRepo, fakeDownloadRepo);
    });

    test('Initial defaults match standard settings', () {
      expect(controller.dataSaver, isFalse);
      expect(controller.lookaheadTracks, 2);
      expect(controller.audioCacheLimitMb, 512);
    });

    test('toggleDataSaver switches state and notifies listeners', () async {
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.toggleDataSaver();
      expect(controller.dataSaver, isTrue);
      expect(fakeSettingsRepo.dataSaver, isTrue);
      expect(notified, isTrue);

      notified = false;
      await controller.toggleDataSaver();
      expect(controller.dataSaver, isFalse);
      expect(fakeSettingsRepo.dataSaver, isFalse);
      expect(notified, isTrue);
    });

    test('setLookaheadTracks updates track preload limit', () async {
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.setLookaheadTracks(0);
      expect(controller.lookaheadTracks, 0);
      expect(fakeSettingsRepo.lookaheadTracks, 0);
      expect(notified, isTrue);

      await controller.setLookaheadTracks(1);
      expect(controller.lookaheadTracks, 1);
      expect(fakeSettingsRepo.lookaheadTracks, 1);
    });

    test('setAudioCacheLimitMb sets disk cache size ceiling', () async {
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.setAudioCacheLimitMb(256);
      expect(controller.audioCacheLimitMb, 256);
      expect(fakeSettingsRepo.audioCacheLimitMb, 256);
      expect(notified, isTrue);

      await controller.setAudioCacheLimitMb(1024);
      expect(controller.audioCacheLimitMb, 1024);
      expect(fakeSettingsRepo.audioCacheLimitMb, 1024);
    });
  });
}
