import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/home/data/repositories/playback_history_repository.dart';
import 'package:nebula/features/home/data/repositories/search_history_repository.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/data/repositories/player_repository_impl.dart';
import 'package:nebula/features/player/data/repositories/soundcloud_repository.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/downloads/domain/repositories/download_repository.dart';
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart';
import 'package:rxdart/rxdart.dart';

class FakePlayerRepository implements PlayerRepository {
  double _vol = 1.0;
  final BehaviorSubject<double> _volumeController =
      BehaviorSubject<double>.seeded(1.0);
  final BehaviorSubject<Duration> _posController =
      BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<Duration> _durController =
      BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<bool> _playingController =
      BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<Track?> _trackController =
      BehaviorSubject<Track?>.seeded(null);
  final BehaviorSubject<List<Track>> _queueController =
      BehaviorSubject<List<Track>>.seeded([]);

  FakePlayerRepository({double initialVolume = 1.0}) {
    _vol = initialVolume;
    _volumeController.add(initialVolume);
  }

  @override
  double get volume => _vol;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Future<void> setVolume(double value) async {
    _vol = value.clamp(0.0, 1.0);
    _volumeController.add(_vol);
  }

  @override
  Stream<Duration> get positionStream => _posController.stream;
  @override
  Stream<Duration> get durationStream => _durController.stream;
  @override
  Stream<bool> get isPlayingStream => _playingController.stream;
  @override
  Stream<Track?> get currentTrackStream => _trackController.stream;
  @override
  Stream<List<Track>> get queueStream => _queueController.stream;
  @override
  Stream<AudioProcessingState> get processingStateStream => const Stream.empty();

  @override
  Future<void> addToQueue(Track track) async {}
  @override
  Future<void> clearQueue() async {}
  @override
  void dispose() {
    _volumeController.close();
    _posController.close();
    _durController.close();
    _playingController.close();
    _trackController.close();
    _queueController.close();
  }
  @override
  Future<void> pause() async {}
  @override
  Future<String?> play(Track track, {bool autoPlay = true}) async => null;
  @override
  Future<void> removeFromQueue(int index) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<List<Track>> search(String query) async => [];
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setQueue(List<Track> tracks, {int initialIndex = 0, bool autoPlay = true}) async {}
  @override
  Future<void> shuffleQueue() async {}
  @override
  Future<void> skipToNext() async {}
  @override
  Future<void> skipToPrevious() async {}
  @override
  Future<void> skipToQueueItem(int index) async {}
  @override
  Future<void> updateQueuePreservingCurrent(List<Track> tracks, {required int currentIndex}) async {}
}

class FakeSearchHistoryRepo implements SearchHistoryRepository {
  @override
  Future<void> addQuery(String query) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> deleteQuery(String query) async {}
  @override
  List<String> getHistory() => [];
}

class FakePlaybackHistoryRepo implements PlaybackHistoryRepository {
  @override
  Future<void> addToHistory(Track track) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  List<Track> getHistory() => [];
}

class FakeSettingsRepo implements SettingsRepository {
  double _volume = 0.8;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double value) async {
    _volume = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAudioHandler extends Fake implements NebulaAudioHandler {
  double currentVolume = 1.0;
  final BehaviorSubject<double> _volStream = BehaviorSubject<double>.seeded(1.0);
  final BehaviorSubject<int?> _indexStream = BehaviorSubject<int?>.seeded(0);

  @override
  double get volume => currentVolume;

  @override
  Stream<double> get volumeStream => _volStream.stream;

  @override
  Stream<int?> get currentIndexStream => _indexStream.stream;

  @override
  Future<void> setVolume(double vol) async {
    currentVolume = vol;
    _volStream.add(vol);
  }
}

class FakeDownloadRepo extends Fake implements DownloadRepository {}
class FakeSoundCloudRepo extends Fake implements SoundCloudRepository {}

void main() {
  group('PlayerController Volume Controls', () {
    late FakePlayerRepository repo;
    late PlayerController controller;

    setUp(() {
      repo = FakePlayerRepository(initialVolume: 0.75);
      controller = PlayerController(
        repo,
        FakeSearchHistoryRepo(),
        FakePlaybackHistoryRepo(),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('initializes volume with repository volume', () {
      expect(controller.volume, equals(0.75));
      expect(controller.isMuted, isFalse);
    });

    test('setVolume updates volume within [0.0, 1.0] and notifies listeners', () async {
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setVolume(0.4);
      expect(controller.volume, equals(0.4));
      expect(repo.volume, equals(0.4));
      expect(notifyCount, greaterThan(0));

      // Test clamping below 0
      await controller.setVolume(-0.5);
      expect(controller.volume, equals(0.0));
      expect(controller.isMuted, isTrue);

      // Test clamping above 1
      await controller.setVolume(1.8);
      expect(controller.volume, equals(1.0));
      expect(controller.isMuted, isFalse);
    });

    test('increaseVolume and decreaseVolume increment and decrement with clamping', () async {
      await controller.setVolume(0.5);

      await controller.increaseVolume(0.05);
      expect(controller.volume, closeTo(0.55, 0.001));

      await controller.decreaseVolume(0.10);
      expect(controller.volume, closeTo(0.45, 0.001));

      // Increase beyond 1.0
      await controller.increaseVolume(0.8);
      expect(controller.volume, equals(1.0));

      // Decrease beyond 0.0
      await controller.decreaseVolume(1.5);
      expect(controller.volume, equals(0.0));
      expect(controller.isMuted, isTrue);
    });

    test('toggleMute toggles to 0.0 and restores previous volume', () async {
      await controller.setVolume(0.65);

      // First toggle: mute
      await controller.toggleMute();
      expect(controller.volume, equals(0.0));
      expect(controller.isMuted, isTrue);

      // Second toggle: restore 0.65
      await controller.toggleMute();
      expect(controller.volume, closeTo(0.65, 0.001));
      expect(controller.isMuted, isFalse);
    });

    test('toggleMute restores default 0.5 if initially muted at 0.0', () async {
      final mutedRepo = FakePlayerRepository(initialVolume: 0.0);
      final mutedController = PlayerController(
        mutedRepo,
        FakeSearchHistoryRepo(),
        FakePlaybackHistoryRepo(),
      );

      expect(mutedController.isMuted, isTrue);
      await mutedController.toggleMute();
      expect(mutedController.volume, equals(0.5));
      expect(mutedController.isMuted, isFalse);

      mutedController.dispose();
    });

    test('reacts to external updates from repository volumeStream', () async {
      expect(controller.volume, equals(0.75));

      await repo.setVolume(0.32);
      await pumpEventQueue();

      expect(controller.volume, closeTo(0.32, 0.001));
    });
  });

  group('PlayerRepositoryImpl Volume Integration', () {
    test('initializes audio handler with settings repository volume', () async {
      final fakeHandler = FakeAudioHandler();
      final fakeSettings = FakeSettingsRepo();
      await fakeSettings.setVolume(0.42);

      final repo = PlayerRepositoryImpl(
        fakeHandler,
        FakeDownloadRepo(),
        fakeSettings,
        FakeSoundCloudRepo(),
      );

      expect(fakeHandler.currentVolume, equals(0.42));
      expect(repo.volume, equals(0.42));
    });

    test('setVolume updates both audio handler and settings repository', () async {
      final fakeHandler = FakeAudioHandler();
      final fakeSettings = FakeSettingsRepo();

      final repo = PlayerRepositoryImpl(
        fakeHandler,
        FakeDownloadRepo(),
        fakeSettings,
        FakeSoundCloudRepo(),
      );

      await repo.setVolume(0.65);
      expect(fakeHandler.currentVolume, equals(0.65));
      expect(fakeSettings.volume, equals(0.65));
      expect(repo.volume, equals(0.65));

      // Test clamping
      await repo.setVolume(1.2);
      expect(fakeHandler.currentVolume, equals(1.0));
      expect(fakeSettings.volume, equals(1.0));
    });
  });
}
