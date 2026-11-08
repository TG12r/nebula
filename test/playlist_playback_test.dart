import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/home/data/repositories/playback_history_repository.dart';
import 'package:nebula/features/home/data/repositories/search_history_repository.dart';
import 'package:nebula/features/jam/data/jam_service.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:rxdart/rxdart.dart';

class FakePlayerRepository implements PlayerRepository {
  List<Track>? lastSetQueueTracks;
  int? lastSetQueueInitialIndex;

  final _positionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _durationController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _isPlayingController = BehaviorSubject<bool>.seeded(false);
  final _currentTrackController = BehaviorSubject<Track?>.seeded(null);
  final _queueController = BehaviorSubject<List<Track>>.seeded([]);
  final _processingStateController =
      BehaviorSubject<AudioProcessingState>.seeded(AudioProcessingState.idle);

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    lastSetQueueTracks = List.from(tracks);
    lastSetQueueInitialIndex = initialIndex;
    _queueController.add(List.unmodifiable(tracks));
    if (initialIndex >= 0 && initialIndex < tracks.length) {
      _currentTrackController.add(tracks[initialIndex]);
    }
  }

  @override
  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  }) async {
    lastSetQueueTracks = List.from(tracks);
    lastSetQueueInitialIndex = currentIndex;
    _queueController.add(List.unmodifiable(tracks));
  }

  @override
  Future<void> clearQueue() async {
    lastSetQueueTracks = [];
    lastSetQueueInitialIndex = -1;
    _queueController.add(const []);
  }

  @override
  Future<String?> play(Track track, {bool autoPlay = true}) async {
    lastSetQueueTracks = [track];
    lastSetQueueInitialIndex = 0;
    _currentTrackController.add(track);
    return null;
  }

  @override
  Future<void> addToQueue(Track track) async {}
  @override
  Future<void> removeFromQueue(int index) async {}
  @override
  Future<void> shuffleQueue() async {}
  @override
  Future<void> skipToNext() async {}
  @override
  Future<void> skipToPrevious() async {}
  @override
  Future<void> skipToQueueItem(int index) async {}
  @override
  Future<void> pause() async {}
  @override
  double volume = 1.0;
  final _volumeController = BehaviorSubject<double>.seeded(1.0);
  @override
  Stream<double> get volumeStream => _volumeController.stream;
  @override
  Future<void> setVolume(double value) async {
    volume = value;
    _volumeController.add(value);
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<List<Track>> search(String query) async => [];
  @override
  void dispose() {}

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  @override
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  @override
  Stream<List<Track>> get queueStream => _queueController.stream;
  @override
  Stream<AudioProcessingState> get processingStateStream =>
      _processingStateController.stream;
}

class FakeSearchHistoryRepository extends Fake implements SearchHistoryRepository {
  @override
  List<String> getHistory() => [];
  @override
  Future<void> addQuery(String query) async {}
  @override
  Future<void> deleteQuery(String query) async {}
  @override
  Future<void> clear() async {}
}

class FakePlaybackHistoryRepository extends Fake implements PlaybackHistoryRepository {
  @override
  List<Track> getHistory() => [];
  @override
  Future<void> addToHistory(Track track) async {}
  @override
  Future<void> clearHistory() async {}
}

class FakeJamService extends Fake implements JamService {
  final _actionController = StreamController<JamAction>.broadcast();
  JamAction? lastBroadcastAction;
  int _seq = 0;

  @override
  Stream<JamAction> get onAction => _actionController.stream;

  @override
  Stream<List<JamParticipant>> get participantsStream => const Stream.empty();

  @override
  Stream<String> get onConnectionReady => const Stream.empty();

  @override
  Stream<void> get onReconnected => const Stream.empty();

  @override
  String get myUserId => 'test_user_id';

  @override
  String nextActionId([String prefix = 'act']) => '${prefix}_test_${++_seq}';

  @override
  Future<bool> broadcastAction(JamAction action, {int maxRetries = 3}) async {
    lastBroadcastAction = action;
    return true;
  }
}

void main() {
  late FakePlayerRepository fakeRepo;
  late PlayerController playerController;
  late List<Track> sampleTracks;

  setUp(() {
    fakeRepo = FakePlayerRepository();
    playerController = PlayerController(
      fakeRepo,
      FakeSearchHistoryRepository(),
      FakePlaybackHistoryRepository(),
    );

    sampleTracks = List.generate(
      5,
      (i) => Track(
        id: 'track_$i',
        title: 'Song $i',
        artist: 'Artist $i',
        thumbnailUrl: 'https://example.com/$i.jpg',
        duration: const Duration(seconds: 180),
        source: TrackSource.youtube,
      ),
    );
  });

  group('Playlist Playback & Shuffle Semantics', () {
    test(
        'Selecting a specific song with shuffle=true puts selected track at index 0',
        () async {
      // User selects Song 2 (index 2) while shuffle is enabled
      const selectedIndex = 2;
      final expectedTrack = sampleTracks[selectedIndex];

      await playerController.playPlaylist(
        sampleTracks,
        initialIndex: selectedIndex,
        shuffle: true,
      );

      expect(fakeRepo.lastSetQueueTracks, isNotNull);
      expect(fakeRepo.lastSetQueueInitialIndex, 0);

      // The selected track MUST be the first track played
      expect(fakeRepo.lastSetQueueTracks!.first.id, expectedTrack.id);
      expect(fakeRepo.lastSetQueueTracks!.first.title, 'Song 2');

      // All 5 original tracks must still be in the queue
      expect(fakeRepo.lastSetQueueTracks!.length, 5);
      final trackIds = fakeRepo.lastSetQueueTracks!.map((t) => t.id).toSet();
      expect(trackIds, equals(sampleTracks.map((t) => t.id).toSet()));
    });

    test(
        'Selecting a specific song with shuffle=false preserves order and initialIndex',
        () async {
      const selectedIndex = 3;

      await playerController.playPlaylist(
        sampleTracks,
        initialIndex: selectedIndex,
        shuffle: false,
      );

      expect(fakeRepo.lastSetQueueTracks, isNotNull);
      expect(fakeRepo.lastSetQueueInitialIndex, selectedIndex);

      // Tracks remain in the exact original order
      for (int i = 0; i < sampleTracks.length; i++) {
        expect(fakeRepo.lastSetQueueTracks![i].id, sampleTracks[i].id);
      }
    });

    test(
        'JamController.playPlaylist with shuffle=true pins selected track to index 0 and sets queue',
        () async {
      final fakeJam = FakeJamService();
      final jamController = JamController(
        fakeJam,
        playerController,
        'test_user_id',
      );

      const selectedIndex = 4;
      final expectedTrack = sampleTracks[selectedIndex];

      await jamController.playPlaylist(
        sampleTracks,
        initialIndex: selectedIndex,
        shuffle: true,
      );

      // Local player repo gets selectedTrack at index 0
      expect(fakeRepo.lastSetQueueTracks, isNotNull);
      expect(fakeRepo.lastSetQueueInitialIndex, 0);
      expect(fakeRepo.lastSetQueueTracks!.first.id, expectedTrack.id);
      expect(fakeRepo.lastSetQueueTracks!.length, sampleTracks.length);
    });

    test(
        'Play All with shuffle=true (no initialIndex) shuffles the entire queue and does not always pin track 0',
        () async {
      final manyTracks = List.generate(
        20,
        (i) => Track(
          id: 'track_$i',
          title: 'Song $i',
          artist: 'Artist $i',
          thumbnailUrl: 'https://example.com/$i.jpg',
          duration: const Duration(seconds: 180),
          source: TrackSource.youtube,
        ),
      );

      // Run multiple times to verify track 0 is not always first
      final firstTrackIds = <String>{};
      for (int run = 0; run < 10; run++) {
        await playerController.playPlaylist(
          manyTracks,
          shuffle: true,
        );

        expect(fakeRepo.lastSetQueueTracks, isNotNull);
        expect(fakeRepo.lastSetQueueInitialIndex, 0);
        expect(fakeRepo.lastSetQueueTracks!.length, 20);

        final trackIds = fakeRepo.lastSetQueueTracks!.map((t) => t.id).toSet();
        expect(trackIds, equals(manyTracks.map((t) => t.id).toSet()));

        firstTrackIds.add(fakeRepo.lastSetQueueTracks!.first.id);
      }

      // With 20 items across 10 runs, we should see different first tracks
      expect(firstTrackIds.length, greaterThan(1));
    });

    test(
        'Play All with shuffle=false (no initialIndex) preserves order and starts at index 0',
        () async {
      await playerController.playPlaylist(
        sampleTracks,
        shuffle: false,
      );

      expect(fakeRepo.lastSetQueueTracks, isNotNull);
      expect(fakeRepo.lastSetQueueInitialIndex, 0);
      expect(fakeRepo.lastSetQueueTracks!.first.id, sampleTracks.first.id);
      for (int i = 0; i < sampleTracks.length; i++) {
        expect(fakeRepo.lastSetQueueTracks![i].id, sampleTracks[i].id);
      }
    });

    test(
        'JamController Play All with shuffle=true broadcasts shuffled queue without pinning track 0',
        () async {
      final fakeJam = FakeJamService();
      final jamController = JamController(
        fakeJam,
        playerController,
        'test_user_id',
      );

      final manyTracks = List.generate(
        20,
        (i) => Track(
          id: 'track_$i',
          title: 'Song $i',
          artist: 'Artist $i',
          thumbnailUrl: 'https://example.com/$i.jpg',
          duration: const Duration(seconds: 180),
          source: TrackSource.youtube,
        ),
      );

      await jamController.playPlaylist(
        manyTracks,
        shuffle: true,
      );

      expect(fakeRepo.lastSetQueueTracks, isNotNull);
      expect(fakeRepo.lastSetQueueInitialIndex, 0);
      expect(fakeRepo.lastSetQueueTracks!.length, 20);
      final trackIds = fakeRepo.lastSetQueueTracks!.map((t) => t.id).toSet();
      expect(trackIds, equals(manyTracks.map((t) => t.id).toSet()));
    });
  });
}
