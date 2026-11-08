import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/jam/data/jam_service.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/jam/presentation/screens/jam_screen.dart';
import 'package:nebula/features/jam/presentation/widgets/jam_bottom_sheet.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

class _MockJamService implements JamService {
  String _myUserId = 'ui_user_1';
  int _seq = 0;
  @override
  bool isHost = false;
  String? _currentCode;
  final Set<String> activeRooms = {'ACTIVE'};

  final _actionController = StreamController<JamAction>.broadcast();
  final _participantsController =
      StreamController<List<JamParticipant>>.broadcast();
  final _connectionReadyController = StreamController<String>.broadcast();
  final _reconnectedController = StreamController<void>.broadcast();

  @override
  String get myUserId => _myUserId;
  @override
  set myUserId(String value) => _myUserId = value;

  @override
  String nextActionId([String prefix = 'act']) => '${prefix}_${++_seq}';

  @override
  Stream<JamAction> get onAction => _actionController.stream;
  @override
  Stream<List<JamParticipant>> get participantsStream =>
      _participantsController.stream;
  @override
  Stream<String> get onConnectionReady => _connectionReadyController.stream;
  @override
  Stream<void> get onReconnected => _reconnectedController.stream;

  @override
  String? get currentCode => _currentCode;
  @override
  bool get isInJam => _currentCode != null;
  @override
  bool get isSubscribed => isInJam;

  @override
  Future<String> createJam() async {
    isHost = true;
    _currentCode = 'NEB999';
    _participantsController.add([
      const JamParticipant(
        id: 'ui_user_1',
        username: 'HostUser',
        isHost: true,
        joinedAt: 1000,
      ),
    ]);
    return _currentCode!;
  }

  @override
  Future<void> joinJam(
    String code, {
    bool verifyRoomExists = true,
    Duration roomCheckTimeout = const Duration(milliseconds: 2500),
  }) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 6) {
      throw ArgumentError('Jam code must be 6 characters');
    }
    if (verifyRoomExists && !activeRooms.contains(normalized)) {
      throw JamSessionNotFoundException(normalized);
    }
    isHost = false;
    _currentCode = normalized;
    _participantsController.add([
      const JamParticipant(
        id: 'host_id',
        username: 'RoomHost',
        isHost: true,
        joinedAt: 1000,
      ),
      const JamParticipant(
        id: 'ui_user_1',
        username: 'GuestUser',
        isHost: false,
        joinedAt: 2000,
      ),
    ]);
  }

  @override
  Future<void> leaveJam() async {
    _currentCode = null;
    isHost = false;
    _participantsController.add(const []);
  }

  @override
  Future<bool> broadcastAction(JamAction action, {int maxRetries = 3}) async =>
      true;

  @override
  Future<bool> sendActionTo(
    String targetId,
    JamAction action, {
    int maxRetries = 3,
  }) async =>
      true;

  @override
  Future<void> requestSync() async {}

  @override
  Future<void> updateHostPresence(bool newIsHost) async {
    isHost = newIsHost;
  }

  @override
  void dispose() {
    _actionController.close();
    _participantsController.close();
    _connectionReadyController.close();
    _reconnectedController.close();
  }
}

class _MockPlayerController extends ChangeNotifier implements PlayerController {
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = const Duration(seconds: 30);
  final Duration _duration = const Duration(seconds: 180);
  List<Track> _queue = [];
  bool shuffleCalled = false;
  bool clearCalled = false;

  @override
  Track? get currentTrack => _currentTrack;
  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  List<Track> get queue => List.unmodifiable(_queue);
  @override
  bool get isBuffering => false;
  @override
  String? get currentTitle => _currentTrack?.title;
  @override
  String? get currentArtist => _currentTrack?.artist;
  @override
  String? get currentThumbnail => null;
  @override
  List<Track> get playbackHistory => const [];
  @override
  List<Track> get searchResults => const [];
  @override
  List<String> get searchHistory => const [];
  @override
  bool get isSearching => false;
  @override
  Stream<Duration> get positionStream => Stream.value(_position);

  void seedState({required Track currentTrack, required List<Track> queue, bool isPlaying = true}) {
    _currentTrack = currentTrack;
    _queue = List.from(queue);
    _isPlaying = isPlaying;
    notifyListeners();
  }

  @override
  Future<String?> playTrack(Track track, {bool autoPlay = true}) async {
    _currentTrack = track;
    _isPlaying = autoPlay;
    notifyListeners();
    return null;
  }

  @override
  Future<void> playPlaylist(
    List<Track> tracks, {
    int? initialIndex,
    bool shuffle = false,
    bool autoPlay = true,
  }) async {
    _queue = List.from(tracks);
    final idx = (initialIndex ?? 0).clamp(0, tracks.isNotEmpty ? tracks.length - 1 : 0);
    _currentTrack = tracks.isNotEmpty ? tracks[idx] : null;
    _isPlaying = autoPlay;
    notifyListeners();
  }

  @override
  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  }) async {
    _queue = List.from(tracks);
    notifyListeners();
  }

  @override
  Future<void> clearQueue() async {
    clearCalled = true;
    _queue = [];
    _currentTrack = null;
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentTrack = _queue[index];
      notifyListeners();
    }
  }

  @override
  Future<void> skipToNext() async {}
  @override
  Future<void> skipToPrevious() async {}
  @override
  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
  }

  @override
  Future<void> addToQueue(Track track) async {
    _queue.add(track);
    notifyListeners();
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      notifyListeners();
    }
  }

  @override
  Future<void> shuffleQueue() async {
    shuffleCalled = true;
    notifyListeners();
  }

  @override
  double volume = 1.0;
  @override
  bool get isMuted => volume == 0.0;
  @override
  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    notifyListeners();
  }
  @override
  Future<void> toggleMute() async {
    volume = volume > 0.0 ? 0.0 : 1.0;
    notifyListeners();
  }
  @override
  Future<void> increaseVolume([double step = 0.05]) async {
    await setVolume(volume + step);
  }
  @override
  Future<void> decreaseVolume([double step = 0.05]) async {
    await setVolume(volume - step);
  }

  @override
  Future<bool> playMix(String query) async => false;
  @override
  Future<void> search(String query) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> deleteHistoryItem(String query) async {}
}

void main() {
  late _MockJamService jamService;
  late _MockPlayerController playerController;
  late JamController jamController;

  setUp(() {
    jamService = _MockJamService();
    playerController = _MockPlayerController();
    jamController = JamController(jamService, playerController, 'ui_user_1');
  });

  tearDown(() {
    jamController.dispose();
  });

  Widget wrapWithProviders(Widget home) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: playerController),
        ChangeNotifierProvider<JamController>.value(value: jamController),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: home,
      ),
    );
  }

  group('JamBottomSheet UI & Error Handling Tests', () {
    testWidgets('Shows validation error when joining with < 6 character code', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const Scaffold(body: JamBottomSheet()),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.tap(find.text('JOIN JAM'));
      await tester.pump();

      expect(find.text('ERR: CODE MUST BE 6 CHARACTERS'), findsOneWidget);
    });

    testWidgets('Shows clean error when joining a non-existent 6-char Jam room', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const Scaffold(body: JamBottomSheet()),
        ),
      );

      await tester.enterText(find.byType(TextField), 'GHOST9');
      await tester.tap(find.text('JOIN JAM'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('JAM SESSION "GHOST9" NOT FOUND'),
        findsOneWidget,
      );
      expect(jamController.isInJam, false);
    });

    testWidgets('Creating a Jam displays generated 6-char code and navigates to JamScreen on ENTER JAM', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => JamBottomSheet.show(context),
                child: const Text('OPEN JAM SHEET'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN JAM SHEET'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CREATE JAM'));
      await tester.pumpAndSettle();

      expect(find.text('JAM CREATED'), findsOneWidget);
      expect(find.text('NEB999'), findsOneWidget);

      await tester.tap(find.text('ENTER JAM'));
      await tester.pumpAndSettle();

      expect(find.byType(JamScreen), findsOneWidget);
      expect(find.text('CHANNEL CODE'), findsOneWidget);

      await jamController.leaveJam();
      await tester.pump();
    });
  });

  group('JamScreen UI, Queue Controls & Navigation Guard Tests', () {
    testWidgets('Renders participants, HOST badge, and highlights active track even with yt: prefix mismatch', (tester) async {
      await jamController.createJam();
      playerController.seedState(
        currentTrack: Track(
          id: 'yt:song_1',
          title: 'Cybernetic Pulse',
          artist: 'Nebula Synth',
          thumbnailUrl: '',
          source: TrackSource.youtube,
        ),
        queue: [
          Track(
            id: 'song_1', // raw ID in queue vs 'yt:song_1' in currentTrack
            title: 'Cybernetic Pulse',
            artist: 'Nebula Synth',
            thumbnailUrl: '',
            source: TrackSource.youtube,
          ),
          Track(
            id: 'song_2',
            title: 'Starlight Drift',
            artist: 'Void Runner',
            thumbnailUrl: '',
            source: TrackSource.youtube,
          ),
        ],
      );

      await tester.pumpWidget(wrapWithProviders(const JamScreen()));
      await tester.pump();

      expect(find.text('NEB999'), findsOneWidget);
      expect(find.text('HOSTUSER'), findsOneWidget);
      expect(find.text('HOST'), findsOneWidget);
      expect(find.text('CYBERNETIC PULSE'), findsWidgets);
      expect(find.text('STARLIGHT DRIFT'), findsOneWidget);
      expect(find.text('SHUFFLE'), findsOneWidget);
      expect(find.text('CLEAR'), findsOneWidget);

      await jamController.leaveJam();
      await tester.pump();
    });

    testWidgets('Tapping SHUFFLE and CLEAR triggers queue actions on JamController', (tester) async {
      await jamController.createJam();
      playerController.seedState(
        currentTrack: Track(
          id: 'yt:song_1',
          title: 'Track One',
          artist: 'Artist One',
          thumbnailUrl: '',
        ),
        queue: [
          Track(id: 'song_1', title: 'Track One', artist: 'Artist One', thumbnailUrl: ''),
          Track(id: 'song_2', title: 'Track Two', artist: 'Artist Two', thumbnailUrl: ''),
        ],
      );

      await tester.pumpWidget(wrapWithProviders(const JamScreen()));
      await tester.pump();

      await tester.tap(find.text('SHUFFLE'));
      await tester.pump();
      expect(playerController.shuffleCalled, true);

      await tester.tap(find.text('CLEAR'));
      await tester.pump();
      expect(playerController.clearCalled, true);
      expect(playerController.queue.isEmpty, true);

      await jamController.leaveJam();
      await tester.pump();
    });

    testWidgets('Tapping LEAVE JAM pops JamScreen exactly once without popping parent screen', (tester) async {
      await jamController.createJam();

      await tester.pumpWidget(
        wrapWithProviders(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JamScreen()),
                    );
                  },
                  child: const Text('GO TO JAM SCREEN'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('GO TO JAM SCREEN'));
      await tester.pumpAndSettle();
      expect(find.byType(JamScreen), findsOneWidget);

      // Scroll down to LEAVE JAM button and tap it
      await tester.ensureVisible(find.text('LEAVE JAM'));
      await tester.tap(find.text('LEAVE JAM'));
      await tester.pumpAndSettle();

      // Verify JamScreen was popped AND parent screen ('GO TO JAM SCREEN') is still intact!
      expect(find.byType(JamScreen), findsNothing);
      expect(find.text('GO TO JAM SCREEN'), findsOneWidget);
      expect(jamController.isInJam, false);
    });
  });
}
