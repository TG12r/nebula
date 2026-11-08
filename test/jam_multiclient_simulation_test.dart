import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/jam/data/jam_service.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

// =============================================================================
// SIMULATED IN-MEMORY JAM NETWORK WITH REAL JSON SERIALIZATION & LATENCY
// =============================================================================

class SimulatedNetwork {
  final List<SimulatedJamService> _clients = [];
  final List<String> globalLogs = [];
  final Map<String, int> clientLatencyMs = {};

  void log(String clientName, String message) {
    final entry = '[$clientName] $message';
    globalLogs.add(entry);
    debugPrint(entry);
  }

  void register(SimulatedJamService client) {
    _clients.add(client);
  }

  void setLatency(String userId, int ms) {
    clientLatencyMs[userId] = ms;
  }

  bool hasActiveRoom(String code, {String? excludingUserId}) {
    return _clients.any(
      (c) =>
          c.isInJam &&
          c.currentCode == code &&
          c.myUserId != excludingUserId,
    );
  }

  void _deliverSerialized(SimulatedJamService target, JamAction action) {
    // 1. Full JSON serialization round-trip: guarantees memory isolation!
    final rawPayload = action.toPayload();
    final jsonStr = jsonEncode(rawPayload);
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final actionCopy = JamAction.fromPayload(decoded);

    // 2. Check latency
    final latency = clientLatencyMs[target.myUserId] ?? 0;
    if (latency > 0) {
      Future.delayed(Duration(milliseconds: latency), () {
        if (target.isInJam) {
          target.deliverAction(actionCopy);
        }
      });
    } else {
      target.deliverAction(actionCopy);
    }
  }

  void broadcast(String senderId, JamAction action) {
    final senderName = _getClientName(senderId);
    log(senderName, '--> BROADCAST ${action.type.name} (track: ${action.track?.title ?? "none"}, pos: ${action.positionMs}ms)');
    for (final c in _clients) {
      if (c.myUserId != senderId && c.isInJam) {
        _deliverSerialized(c, action);
      }
    }
  }

  void sendTo(String senderId, String targetId, JamAction action) {
    final senderName = _getClientName(senderId);
    log(senderName, '--> SEND TO $targetId: ${action.type.name}');
    for (final c in _clients) {
      if ((c.myUserId == targetId || (targetId == 'host' && c.isHost)) && c.isInJam) {
        _deliverSerialized(c, action);
      }
    }
  }

  void syncPresence() {
    final active = _clients.where((c) => c.isInJam).map((c) => c.toParticipant()).toList();
    for (final c in _clients) {
      if (c.isInJam) {
        c.deliverParticipants(List.unmodifiable(active));
      }
    }
  }

  String _getClientName(String id) {
    for (final c in _clients) {
      if (c.myUserId == id) return c.name;
    }
    return id;
  }
}

// =============================================================================
// SIMULATED JAM SERVICE
// =============================================================================

class SimulatedJamService implements JamService {
  final String name;
  String _myUserId = '';
  int _actionSeq = 0;

  @override
  String get myUserId => _myUserId;
  @override
  set myUserId(String value) => _myUserId = value;
  final SimulatedNetwork network;

  @override
  bool isHost = false;
  String? _currentCode;
  int joinedAt = 0;

  final _actionController = StreamController<JamAction>.broadcast();
  final _participantsController = StreamController<List<JamParticipant>>.broadcast();
  final _connectionReadyController = StreamController<String>.broadcast();
  final _reconnectedController = StreamController<void>.broadcast();

  final List<JamAction> broadcastHistory = [];

  SimulatedJamService({
    required this.name,
    required String myUserId,
    required this.network,
  }) : _myUserId = myUserId {
    network.register(this);
  }

  @override
  String nextActionId([String prefix = 'act']) {
    return '${prefix}_${_myUserId}_${DateTime.now().microsecondsSinceEpoch}_${++_actionSeq}';
  }

  @override
  Stream<JamAction> get onAction => _actionController.stream;

  @override
  Stream<List<JamParticipant>> get participantsStream => _participantsController.stream;

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

  JamParticipant toParticipant() => JamParticipant(
        id: myUserId,
        username: name,
        isHost: isHost,
        joinedAt: joinedAt,
      );

  void deliverAction(JamAction action) {
    network.log(name, '<-- RECEIVED ${action.type.name} from ${network._getClientName(action.senderId)}');
    _actionController.add(action);
  }

  final Set<String> _knownParticipants = {};

  void deliverParticipants(List<JamParticipant> participants) {
    network.log(name, 'Presence updated (${participants.length} participants: ${participants.map((p) => "${p.username}${p.isHost ? " [HOST]" : ""}").join(", ")})');
    if (isHost) {
      for (final p in participants) {
        if (p.id != myUserId && !_knownParticipants.contains(p.id)) {
          _knownParticipants.add(p.id);
          network.log(name, 'Host detected new Guest (${p.id}). Emitting connection ready...');
          _connectionReadyController.add(p.id);
        }
      }
      final currentIds = participants.map((p) => p.id).toSet();
      _knownParticipants.removeWhere((id) => !currentIds.contains(id));
    }
    _participantsController.add(participants);
  }

  void triggerReconnect() {
    network.log(name, 'Channel reconnected signal emitted');
    _reconnectedController.add(null);
  }

  @override
  Future<String> createJam() async {
    isHost = true;
    _currentCode = 'JAM123';
    joinedAt = DateTime.now().millisecondsSinceEpoch;
    network.log(name, 'Created Jam $_currentCode (as Host)');
    network.syncPresence();
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
    if (verifyRoomExists &&
        !network.hasActiveRoom(normalized, excludingUserId: myUserId)) {
      throw JamSessionNotFoundException(normalized);
    }
    isHost = false;
    _currentCode = normalized;
    joinedAt = DateTime.now().millisecondsSinceEpoch;
    network.log(name, 'Joined Jam $normalized (as Guest)');
    network.syncPresence();
  }

  @override
  Future<void> leaveJam() async {
    network.log(name, 'Left Jam $_currentCode');
    _currentCode = null;
    isHost = false;
    joinedAt = 0;
    _knownParticipants.clear();
    network.syncPresence();
  }

  @override
  Future<bool> broadcastAction(JamAction action, {int maxRetries = 3}) async {
    broadcastHistory.add(action);
    network.broadcast(myUserId, action);
    return true;
  }

  @override
  Future<bool> sendActionTo(String targetId, JamAction action, {int maxRetries = 3}) async {
    network.sendTo(myUserId, targetId, action);
    return true;
  }

  @override
  Future<void> requestSync() async {
    network.log(name, 'Requested sync from host');
    await sendActionTo(
      'host',
      JamAction(
        id: nextActionId('sync_req'),
        type: JamActionType.requestSync,
        senderId: myUserId,
      ),
    );
  }

  @override
  Future<void> updateHostPresence(bool newIsHost) async {
    isHost = newIsHost;
    network.log(name, 'Updated host presence: isHost = $newIsHost');
    network.syncPresence();
  }

  @override
  void dispose() {
    _actionController.close();
    _participantsController.close();
    _connectionReadyController.close();
    _reconnectedController.close();
  }
}

// =============================================================================
// SIMULATED PLAYER CONTROLLER
// =============================================================================

class SimulatedPlayerController extends ChangeNotifier implements PlayerController {
  final String clientName;
  final SimulatedNetwork network;

  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(seconds: 240);
  List<Track> _queue = [];
  bool _isBuffering = false;
  int simulatedBufferingDelayMs = 0;
  bool emitPositionTicksWhileLoading = false;

  final List<String> playerLogs = [];

  SimulatedPlayerController({
    required this.clientName,
    required this.network,
  });

  void _record(String action) {
    final entry = '[$clientName Player] $action';
    playerLogs.add(entry);
    network.log(clientName, 'Player: $action');
  }

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
  bool get isBuffering => _isBuffering;

  void setBuffering(bool buffering) {
    _isBuffering = buffering;
    _record('isBuffering = $buffering');
    notifyListeners();
  }

  void advancePlaybackSeconds(int seconds) {
    _position += Duration(seconds: seconds);
    _record('Advanced position to ${_position.inSeconds}s');
    notifyListeners();
  }

  void simulateNaturalTrackCompletion() {
    _record('simulateNaturalTrackCompletion() for "${_currentTrack?.title}"');
    final currentIdx = _queue.indexWhere((t) => TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(_currentTrack?.id ?? ''));
    if (currentIdx != -1 && currentIdx + 1 < _queue.length) {
      _currentTrack = _queue[currentIdx + 1];
      _position = Duration.zero;
      _isPlaying = true;
      _record('Natural advance -> "${_currentTrack?.title}"');
      notifyListeners();
    } else {
      _isPlaying = false;
      _record('Natural completion: queue finished');
      notifyListeners();
    }
  }

  @override
  Future<String?> playTrack(Track track, {bool autoPlay = true}) async {
    _record('playTrack("${track.title}") autoPlay=$autoPlay');
    if (simulatedBufferingDelayMs > 0) {
      if (emitPositionTicksWhileLoading && _currentTrack != null) {
        // Simulate just_audio emitting position ticks on the OLD track while
        // the YouTube manifest for the new track is being resolved!
        await Future.delayed(Duration(milliseconds: simulatedBufferingDelayMs ~/ 2));
        _position += const Duration(milliseconds: 200);
        notifyListeners();
        await Future.delayed(Duration(milliseconds: simulatedBufferingDelayMs ~/ 2));
      } else {
        _isBuffering = true;
        _isPlaying = false;
        notifyListeners();
        await Future.delayed(Duration(milliseconds: simulatedBufferingDelayMs));
        _isBuffering = false;
      }
    }
    _currentTrack = track;
    _position = Duration.zero;
    _isPlaying = autoPlay;
    if (_queue.isEmpty || !_queue.any((t) => TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(track.id))) {
      _queue = [track];
    }
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
    final idx = (initialIndex ?? 0).clamp(0, tracks.isNotEmpty ? tracks.length - 1 : 0);
    if (simulatedBufferingDelayMs > 0) {
      _isBuffering = true;
      _isPlaying = false;
      notifyListeners();
      await Future.delayed(Duration(milliseconds: simulatedBufferingDelayMs));
      _isBuffering = false;
    }
    _queue = List.from(tracks);
    _currentTrack = tracks.isNotEmpty ? tracks[idx] : null;
    _position = Duration.zero;
    _isPlaying = autoPlay;
    _record('playPlaylist(${tracks.length} tracks, index=$idx -> "${_currentTrack?.title}")');
    notifyListeners();
  }

  @override
  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  }) async {
    _queue = List.from(tracks);
    if (currentIndex >= 0 && currentIndex < _queue.length) {
      _currentTrack ??= _queue[currentIndex];
    }
    _record('updateQueuePreservingCurrent(${tracks.length} tracks, currentIndex=$currentIndex, pos=${_position.inSeconds}s)');
    notifyListeners();
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _record('reorderQueue(oldIndex=$oldIndex, newIndex=$newIndex)');
    notifyListeners();
  }

  @override
  Future<void> clearQueue() async {
    _queue = [];
    _currentTrack = null;
    _isPlaying = false;
    _position = Duration.zero;
    _record('clearQueue()');
    notifyListeners();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentTrack = _queue[index];
      _position = Duration.zero;
      _isPlaying = true;
      _record('skipToQueueItem($index -> "${_currentTrack?.title}")');
      notifyListeners();
    }
  }

  @override
  Future<void> skipToNext() async {
    final idx = _queue.indexWhere((t) => TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(_currentTrack?.id ?? ''));
    if (idx != -1 && idx + 1 < _queue.length) {
      _currentTrack = _queue[idx + 1];
      _position = Duration.zero;
      _record('skipToNext() -> "${_currentTrack?.title}"');
      notifyListeners();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final idx = _queue.indexWhere((t) => TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(_currentTrack?.id ?? ''));
    if (idx > 0) {
      _currentTrack = _queue[idx - 1];
      _position = Duration.zero;
      _record('skipToPrevious() -> "${_currentTrack?.title}"');
      notifyListeners();
    }
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _record('pause() at ${_position.inMilliseconds}ms');
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    _isPlaying = true;
    _record('resume() at ${_position.inMilliseconds}ms');
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  @override
  Future<void> seek(Duration targetPosition) async {
    _record('seek(${targetPosition.inMilliseconds}ms)');
    _position = targetPosition;
    notifyListeners();
  }

  @override
  Future<void> addToQueue(Track track) async {
    _queue.add(track);
    _record('addToQueue("${track.title}") -> queue length: ${_queue.length}');
    notifyListeners();
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _queue.length) {
      final removed = _queue.removeAt(index);
      _record('removeFromQueue($index: "${removed.title}") -> queue length: ${_queue.length}');
      notifyListeners();
    }
  }

  @override
  Future<void> shuffleQueue() async {
    if (_queue.length <= 1) return;
    final currentIdx = _currentTrack == null
        ? -1
        : _queue.indexWhere(
            (t) =>
                TrackSource.stripPrefix(t.id) ==
                TrackSource.stripPrefix(_currentTrack!.id),
          );
    if (currentIdx != -1 && currentIdx + 1 < _queue.length) {
      final upcoming = _queue.sublist(currentIdx + 1)..shuffle();
      _queue.replaceRange(currentIdx + 1, _queue.length, upcoming);
    } else if (currentIdx == -1) {
      _queue.shuffle();
    }
    _record('shuffleQueue() preserving current index $currentIdx');
    notifyListeners();
  }

  @override
  Future<bool> playMix(String query) async => false;

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

  // Unused getters in JamController
  @override
  String? get currentTitle => _currentTrack?.title;
  @override
  String? get currentArtist => _currentTrack?.artist;
  @override
  String? get currentThumbnail => _currentTrack?.thumbnailUrl;
  @override
  List<Track> get playbackHistory => [];
  @override
  List<Track> get searchResults => [];
  @override
  List<String> get searchHistory => [];
  @override
  bool get isSearching => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> search(String query) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> deleteHistoryItem(String query) async {}
}

// =============================================================================
// MULTI-CLIENT CLIENT HARNESS
// =============================================================================

class JamClientTestHarness {
  final String name;
  final SimulatedNetwork network;
  late final SimulatedJamService service;
  late final SimulatedPlayerController player;
  late final JamController jam;

  JamClientTestHarness({
    required this.name,
    required String userId,
    required this.network,
  }) {
    service = SimulatedJamService(name: name, myUserId: userId, network: network);
    player = SimulatedPlayerController(clientName: name, network: network);
    jam = JamController(service, player);
  }

  void dispose() {
    jam.dispose();
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  final trackA = Track(id: 'yt:song_a', title: 'Song Alpha', artist: 'Artist 1', thumbnailUrl: '', source: TrackSource.youtube);
  final trackB = Track(id: 'yt:song_b', title: 'Song Beta', artist: 'Artist 2', thumbnailUrl: '', source: TrackSource.youtube);
  final trackC = Track(id: 'yt:song_c', title: 'Song Gamma', artist: 'Artist 3', thumbnailUrl: '', source: TrackSource.youtube);
  final trackD = Track(id: 'yt:song_d', title: 'Song Delta', artist: 'Artist 4', thumbnailUrl: '', source: TrackSource.youtube);

  group('Jam 3-Client Local Simulation Tests', () {
    late SimulatedNetwork network;
    late JamClientTestHarness host;
    late JamClientTestHarness guest1;
    late JamClientTestHarness guest2;

    setUp(() {
      network = SimulatedNetwork();
      host = JamClientTestHarness(name: 'Host', userId: 'user_host_01', network: network);
      guest1 = JamClientTestHarness(name: 'Guest 1', userId: 'user_guest_01', network: network);
      guest2 = JamClientTestHarness(name: 'Guest 2', userId: 'user_guest_02', network: network);
    });

    tearDown(() async {
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();
      host.dispose();
      guest1.dispose();
      guest2.dispose();
    });

    test('1. 3 clients join session: exactly 1 Host, 2 Guests, NO dual-host split-brain', () async {
      network.log('TEST', '--- Starting Test 1: Session creation and multi-client join ---');

      // Host creates Jam
      final code = await host.jam.createJam();
      expect(code, 'JAM123');
      expect(host.jam.isHost, true);
      expect(host.jam.isInJam, true);

      // Guests join Jam
      await guest1.jam.joinJam(code);
      await guest2.jam.joinJam(code);

      expect(guest1.jam.isInJam, true);
      expect(guest1.jam.isHost, false);

      expect(guest2.jam.isInJam, true);
      expect(guest2.jam.isHost, false);

      // Verify participant count across all 3 nodes
      expect(host.jam.participants.length, 3);
      expect(guest1.jam.participants.length, 3);
      expect(guest2.jam.participants.length, 3);

      // Verify strictly 1 host exists
      final hostsInSession = host.jam.participants.where((p) => p.isHost).toList();
      expect(hostsInSession.length, 1);
      expect(hostsInSession.first.id, 'user_host_01');
      network.log('TEST', '--- Test 1 PASSED: Single Host verified across all 3 nodes ---');
    });

    test('2. Guest 1 changes track -> Host executes -> NO echo loop (0 duplicate broadcasts)', () async {
      network.log('TEST', '--- Starting Test 2: Guest 1 track change and echo prevention ---');

      // Setup session with initial song on Host
      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(host.player.currentTrack?.id, 'yt:song_a');
      expect(guest1.player.currentTrack?.id, 'yt:song_a');
      expect(guest2.player.currentTrack?.id, 'yt:song_a');

      // Snapshot Host's broadcast history before Guest 1 changes track
      final hostBroadcastsBefore = host.service.broadcastHistory.length;

      network.log('TEST', 'Guest 1 changes track to Song Beta...');
      await guest1.jam.playTrack(trackB);
      await pumpEventQueue();

      // Give 250ms for asynchronous execution and remote action completion
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // 1. All 3 clients must now be playing Song Beta
      expect(guest1.player.currentTrack?.id, 'yt:song_b', reason: 'Guest 1 initiated Song B');
      expect(host.player.currentTrack?.id, 'yt:song_b', reason: 'Host must receive and switch to Song B');
      expect(guest2.player.currentTrack?.id, 'yt:song_b', reason: 'Guest 2 must receive and switch to Song B');

      // 2. CRITICAL VERIFICATION: Host must NOT have broadcasted an echo playTrack
      final hostEchoes = host.service.broadcastHistory.skip(hostBroadcastsBefore).where(
            (a) => a.type == JamActionType.playTrack && (a.track?.id == 'yt:song_b' || a.track?.id == 'song_b'),
          );
      expect(hostEchoes.isEmpty, true, reason: 'Host MUST NOT echo playTrack back when receiving remote action!');

      network.log('TEST', '--- Test 2 PASSED: 0 echo messages emitted by Host. Loop broken! ---');
    });

    test('3. Heartbeat quiet grace period suppresses stale pulses during track change', () async {
      network.log('TEST', '--- Starting Test 3: Heartbeat quiet grace period ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Guest 1 changes track
      await guest1.jam.playTrack(trackB);
      await pumpEventQueue();

      // Manually simulate a delayed/in-flight stale pulse from the old song arriving at Guest 1
      network.log('TEST', 'Delivering stale pulse of Song Alpha to Guest 1...');
      guest1.service.deliverAction(JamAction(
        id: 'stale_pulse_123',
        type: JamActionType.syncPulse,
        track: trackA,
        positionMs: 35000,
        isPlaying: true,
        senderId: host.service.myUserId,
      ));
      await pumpEventQueue();

      // Guest 1 must still be playing Song Beta (stale pulse ignored during grace period!)
      expect(guest1.player.currentTrack?.id, 'yt:song_b',
          reason: 'Guest 1 must NOT revert to Song Alpha upon receiving stale pulse!');

      network.log('TEST', '--- Test 3 PASSED: Stale pulse rejected by quiet grace period ---');
    });

    test('4. Smooth track start: No seek executed on early playback seconds', () async {
      network.log('TEST', '--- Starting Test 4: Smooth track start & drift seek suppression ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Guest 1 starts a new track from 0
      final seeksBefore = guest1.player.playerLogs.where((l) => l.contains('seek(')).length;

      await guest1.jam.playTrack(trackC);
      await pumpEventQueue();

      // Receive a syncPulse with 1500ms position within the first 6 seconds
      guest1.service.deliverAction(JamAction(
        id: 'early_pulse',
        type: JamActionType.syncPulse,
        track: trackC,
        positionMs: 1500,
        isPlaying: true,
        senderId: host.service.myUserId,
      ));
      await pumpEventQueue();

      // Verify NO seek was performed on early playback (prevents the first-seconds buffer loop)
      final seeksAfter = guest1.player.playerLogs.where((l) => l.contains('seek(')).length;
      expect(seeksAfter, seeksBefore, reason: 'No seek should be executed during early playback!');

      network.log('TEST', '--- Test 4 PASSED: Early playback seeks suppressed for smooth buffering ---');
    });

    test('5. Queue navigation (skipToQueueItem) preserves the full queue across all 3 clients', () async {
      network.log('TEST', '--- Starting Test 5: Shared queue navigation and preservation ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      // Host plays a 4-track playlist
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(host.player.queue.length, 4);
      expect(guest1.player.queue.length, 4);
      expect(guest2.player.queue.length, 4);
      expect(host.player.currentTrack?.id, 'yt:song_a');

      // Guest 2 skips directly to Track 3 (Song Delta, index 3) in queue
      network.log('TEST', 'Guest 2 calls skipToQueueItem(3) -> Song Delta');
      await guest2.jam.skipToQueueItem(3);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // 1. All 3 clients must now be playing Song Delta
      expect(guest2.player.currentTrack?.id, 'yt:song_d');
      expect(host.player.currentTrack?.id, 'yt:song_d');
      expect(guest1.player.currentTrack?.id, 'yt:song_d');

      // 2. Full queue must NOT have been wiped to [Song Delta]
      expect(host.player.queue.length, 4, reason: 'Host queue must preserve all 4 tracks');
      expect(guest1.player.queue.length, 4, reason: 'Guest 1 queue must preserve all 4 tracks');
      expect(guest2.player.queue.length, 4, reason: 'Guest 2 queue must preserve all 4 tracks');

      network.log('TEST', '--- Test 5 PASSED: Full queue intact and synchronized on all 3 clients ---');
    });

    test('6. Host conflict resolution: Younger host automatically demotes if dual-host emerges', () async {
      network.log('TEST', '--- Starting Test 6: Dual-host conflict resolution ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Force simulated dual-host situation (e.g. temporary presence packet race)
      final hostParticipant = JamParticipant(
        id: host.service.myUserId,
        username: 'Host',
        isHost: true,
        joinedAt: 1000, // Older
      );
      final guestAccidentalHost = JamParticipant(
        id: guest1.service.myUserId,
        username: 'Guest 1',
        isHost: true,
        joinedAt: 2000, // Newer
      );

      // Deliver both hosts to Guest 1
      guest1.jam.participants; // trigger stream
      guest1.service.deliverParticipants([hostParticipant, guestAccidentalHost]);
      await pumpEventQueue();

      // Guest 1 must recognize the older host and demote itself!
      expect(guest1.jam.isHost, false, reason: 'Younger host must yield and demote itself to guest');
      expect(host.jam.isHost, true, reason: 'Original host remains host');

      network.log('TEST', '--- Test 6 PASSED: Conflict resolved, single host maintained ---');
    });

    test('7. Out-of-order packet arrival: Monotonic timestamps drop delayed stale actions', () async {
      network.log('TEST', '--- Starting Test 7: Out-of-order packet drop ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Start by playing Song Alpha
      await host.jam.playTrack(trackA);
      await pumpEventQueue();

      expect(guest1.player.isPlaying, true);

      final baseTs = DateTime.now().millisecondsSinceEpoch;

      // Simulate network lag: Host resumes at baseTs + 5000, but an earlier pause from baseTs + 1000 was delayed
      network.log('TEST', 'Delivering newer Resume (ts: baseTs + 5000) to Guest 1...');
      guest1.service.deliverAction(JamAction(
        id: 'action_resume_5000',
        type: JamActionType.resume,
        track: trackA,
        positionMs: 15000,
        timestampMs: baseTs + 5000,
        isPlaying: true,
        senderId: host.service.myUserId,
      ));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.isPlaying, true);

      // Now the delayed, stale Pause (baseTs + 1000) arrives after Resume
      network.log('TEST', 'Delivering delayed, stale Pause (ts: baseTs + 1000) to Guest 1...');
      guest1.service.deliverAction(JamAction(
        id: 'action_pause_1000_stale',
        type: JamActionType.pause,
        track: trackA,
        positionMs: 14000,
        timestampMs: baseTs + 1000, // Older than baseTs + 5000!
        isPlaying: false,
        senderId: host.service.myUserId,
      ));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Guest 1 MUST still be playing because the stale Pause was dropped!
      expect(guest1.player.isPlaying, true,
          reason: 'Stale Pause arriving out-of-order must be dropped, playback must stay playing!');

      network.log('TEST', '--- Test 7 PASSED: Monotonic timestamp successfully dropped out-of-order packet ---');
    });

    test('8. Near-simultaneous actions: Skip race condition window debounces duplicate skips', () async {
      network.log('TEST', '--- Starting Test 8: Near-simultaneous skip debouncing ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      // Playlist with [Song A, Song B, Song C, Song D]
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(host.player.currentTrack?.id, 'yt:song_a');
      expect(guest1.player.currentTrack?.id, 'yt:song_a');
      expect(guest2.player.currentTrack?.id, 'yt:song_a');

      // Guest 1 skips to next at t=0
      network.log('TEST', 'Guest 1 triggers skipToNext() -> advances to Song B');
      await guest1.jam.skipToNext();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(guest2.player.currentTrack?.id, 'yt:song_b');

      // Guest 2 also clicked "Next" almost at the same time (arriving within the 700ms window)
      network.log('TEST', 'Guest 2 near-simultaneous skip arrives at Host and Guest 1 (within race window)...');
      final duplicateSkip = JamAction(
        id: 'guest2_simultaneous_skip',
        type: JamActionType.skipNext,
        track: trackB,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: guest2.service.myUserId,
      );
      host.service.deliverAction(duplicateSkip);
      guest1.service.deliverAction(duplicateSkip);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Both Host and Guest 1 must REMAIN on Song B, NOT skipped again to Song C!
      expect(host.player.currentTrack?.id, 'yt:song_b',
          reason: 'Near-simultaneous skip must NOT skip a second track ahead!');
      expect(guest1.player.currentTrack?.id, 'yt:song_b',
          reason: 'Guest 1 must also remain on Song B!');

      network.log('TEST', '--- Test 8 PASSED: Near-simultaneous duplicate skip successfully debounced ---');
    });

    test('9. Queue coalescing: Rapid seek scrubbing keeps only the latest seek', () async {
      network.log('TEST', '--- Starting Test 9: Rapid seek queue coalescing ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      final now = DateTime.now().millisecondsSinceEpoch;

      // Simulate a user rapidly scrubbing the slider: 4 seek actions in rapid succession
      network.log('TEST', 'Delivering 4 rapid seek actions (10s, 20s, 35s, 50s)...');
      guest1.service.deliverAction(JamAction(
        id: 'seek_1',
        type: JamActionType.seek,
        track: trackA,
        positionMs: 10000,
        timestampMs: now + 10,
        senderId: host.service.myUserId,
      ));
      guest1.service.deliverAction(JamAction(
        id: 'seek_2',
        type: JamActionType.seek,
        track: trackA,
        positionMs: 20000,
        timestampMs: now + 20,
        senderId: host.service.myUserId,
      ));
      guest1.service.deliverAction(JamAction(
        id: 'seek_3',
        type: JamActionType.seek,
        track: trackA,
        positionMs: 35000,
        timestampMs: now + 30,
        senderId: host.service.myUserId,
      ));
      guest1.service.deliverAction(JamAction(
        id: 'seek_4',
        type: JamActionType.seek,
        track: trackA,
        positionMs: 50000,
        timestampMs: now + 40,
        senderId: host.service.myUserId,
      ));

      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // Verify that Guest 1 player reached 50s
      expect(guest1.player.position.inSeconds, 50,
          reason: 'Final position must be 50s matching the latest scrubbed target');

      // Verify that intermediate seeks were coalesced and didn't result in 4 sequential seeks
      final seekLogs = guest1.player.playerLogs.where((l) => l.contains('seek(')).toList();
      network.log('TEST', 'Executed seek operations: ${seekLogs.join(", ")}');
      expect(seekLogs.length <= 2, true,
          reason: 'Intermediate seeks should be coalesced away, executing at most 2 seeks total');

      network.log('TEST', '--- Test 9 PASSED: Rapid seek actions coalesced efficiently ---');
    });

    test('10. Action ID deduplication: Network duplicate packets are ignored', () async {
      network.log('TEST', '--- Starting Test 10: Packet deduplication ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      final queueLengthBefore = guest1.player.queue.length;

      // Deliver duplicate addToQueue packets (same ID)
      final duplicateAction = JamAction(
        id: 'unique_packet_id_456',
        type: JamActionType.addToQueue,
        track: trackB,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: host.service.myUserId,
      );

      network.log('TEST', 'Delivering addToQueue packet first time...');
      guest1.service.deliverAction(duplicateAction);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.queue.length, queueLengthBefore + 1);

      network.log('TEST', 'Delivering exact same addToQueue packet second time (simulating retransmit)...');
      guest1.service.deliverAction(duplicateAction);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Queue length must still be queueLengthBefore + 1, NOT + 2!
      expect(guest1.player.queue.length, queueLengthBefore + 1,
          reason: 'Duplicate packet with identical ID must be rejected');

      network.log('TEST', '--- Test 10 PASSED: Duplicate network packet dropped cleanly ---');
    });

    test('11. Concurrent queue removal: Content-based removal prevents index drift errors', () async {
      network.log('TEST', '--- Starting Test 11: Concurrent queue removal with index drift ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Playlist: [Song A (0), Song B (1), Song C (2), Song D (3)]
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.queue.length, 4);

      // Locally, Guest 1 removes Song Alpha (index 0)
      // Now Guest 1 queue is: [Song Beta (0), Song Gamma (1), Song Delta (2)]
      await guest1.player.removeFromQueue(0);
      expect(guest1.player.queue.length, 3);
      expect(guest1.player.queue[1].id, 'yt:song_c', reason: 'Song Gamma shifted from index 2 to index 1');

      // Now a remote action arrives from Host who concurrently removed Song Gamma when it was at index 2
      // Host action has queueIndex: 2, but track: Song Gamma
      network.log('TEST', 'Delivering remote removeFromQueue with index=2, but track=Song Gamma (shifted to 1)...');
      guest1.service.deliverAction(JamAction(
        id: 'remove_concurrent_gamma',
        type: JamActionType.removeFromQueue,
        track: trackC,
        queueIndex: 2, // In original queue it was 2, but currently at 1!
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: host.service.myUserId,
      ));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Guest 1 must have removed Song Gamma (by track ID), NOT Song Delta!
      expect(guest1.player.queue.length, 2);
      expect(guest1.player.queue.any((t) => t.id == 'yt:song_c'), false,
          reason: 'Song Gamma should have been removed correctly by ID');
      expect(guest1.player.queue.any((t) => t.id == 'yt:song_d'), true,
          reason: 'Song Delta should still remain in queue!');

      network.log('TEST', '--- Test 11 PASSED: Content-based queue removal protected against index drift ---');
    });

    test('12. Network reconnect: Guest resets state and resyncs automatically', () async {
      network.log('TEST', '--- Starting Test 12: Network reconnect and resync recovery ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.currentTrack?.id, 'yt:song_a');

      // Simulate Host changing track while Guest 1 has a disconnected channel
      network.log('TEST', 'Host changes track to Song Delta...');
      await host.jam.playTrack(trackD);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Now simulate Guest 1 channel reconnecting
      network.log('TEST', 'Simulating Guest 1 channel reconnection event...');
      guest1.service.triggerReconnect();
      await pumpEventQueue();

      // Wait for handshake / sync polling to query Host and apply syncState
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // Guest 1 should now be synchronized with Host on Song Delta
      expect(guest1.player.currentTrack?.id, 'yt:song_d',
          reason: 'Guest 1 should resync to Song Delta after reconnection');

      network.log('TEST', '--- Test 12 PASSED: Reconnected guest successfully resynced room state ---');
    });

    test('13. Late Joiner: Guest joins halfway through active session without resetting Host or existing guests', () async {
      network.log('TEST', '--- Starting Test 13: Late Joiner ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Host plays a 4-track playlist
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 1); // Starting at Song Beta
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Host & Guest 1 advance to 45 seconds of Song Beta
      host.player.advancePlaybackSeconds(45);
      guest1.player.advancePlaybackSeconds(45);
      await pumpEventQueue();

      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(host.player.position.inSeconds, 45);
      expect(guest1.player.position.inSeconds, 45);

      // Now Guest 2 joins late
      network.log('TEST', 'Guest 2 joins late while session is at 45s of Song Beta...');
      await guest2.jam.joinJam('JAM123');
      await pumpEventQueue();

      // Wait for handshake / sync polling to complete
      await Future.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();

      // 1. Host and Guest 1 MUST STILL be at Song Beta, and NOT reset to 0:00!
      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(host.player.position.inSeconds, 45, reason: 'Host playback MUST NOT reset to 0 when late guest joins!');
      expect(guest1.player.position.inSeconds, 45, reason: 'Guest 1 playback MUST NOT reset to 0!');

      // 2. Guest 2 must receive full queue (4 tracks)
      expect(guest2.player.queue.length, 4, reason: 'Late guest must receive full 4-track queue');

      // 3. Guest 2 must be on Song Beta
      expect(guest2.player.currentTrack?.id, 'yt:song_b', reason: 'Late guest must match the active track');

      // 4. Guest 2 position must be synced (>= 40s)
      expect(guest2.player.position.inSeconds >= 40, true, reason: 'Late guest must seek to current playback position');

      network.log('TEST', '--- Test 13 PASSED: Late joiner seamlessly synchronized without disrupting existing playback ---');
    });

    test('14. Natural song completion: Host advances to next track and notifies guests with 0 broadcast loops', () async {
      network.log('TEST', '--- Starting Test 14: Natural song completion ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      final playlist = [trackA, trackB, trackC];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      expect(host.player.currentTrack?.id, 'yt:song_a');
      expect(guest1.player.currentTrack?.id, 'yt:song_a');
      expect(guest2.player.currentTrack?.id, 'yt:song_a');

      // Snapshot broadcasts before natural finish
      final guest1BroadcastsBefore = guest1.service.broadcastHistory.length;
      final guest2BroadcastsBefore = guest2.service.broadcastHistory.length;

      // Host player naturally finishes Song Alpha and advances to Song Beta
      network.log('TEST', 'Host player reaches end of Song Alpha -> auto-advances to Song Beta...');
      host.player.simulateNaturalTrackCompletion();
      await pumpEventQueue();

      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // All 3 nodes must now be on Song Beta
      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(guest1.player.currentTrack?.id, 'yt:song_b', reason: 'Guest 1 must follow Host natural advance');
      expect(guest2.player.currentTrack?.id, 'yt:song_b', reason: 'Guest 2 must follow Host natural advance');

      // Guests must NOT broadcast any actions upon receiving the natural change
      final guest1BroadcastsAfter = guest1.service.broadcastHistory.length;
      final guest2BroadcastsAfter = guest2.service.broadcastHistory.length;
      expect(guest1BroadcastsAfter, guest1BroadcastsBefore, reason: 'Guests must not re-broadcast natural track advance');
      expect(guest2BroadcastsAfter, guest2BroadcastsBefore, reason: 'Guests must not re-broadcast natural track advance');

      network.log('TEST', '--- Test 14 PASSED: Natural song completion advanced smoothly across all peers ---');
    });

    test('15. Host departure during active playback: Oldest guest promoted, preserves remaining queue and playback', () async {
      network.log('TEST', '--- Starting Test 15: Host failover during active queue ---');

      await host.jam.createJam();
      guest1.service.joinedAt = 1000;
      await guest1.jam.joinJam('JAM123');
      guest1.service.joinedAt = 1000;
      await guest2.jam.joinJam('JAM123');
      guest2.service.joinedAt = 2000;
      network.syncPresence();
      await pumpEventQueue();

      // Play 4 tracks starting at Track B (index 1)
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 1);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Host leaves the session abruptly
      network.log('TEST', 'Host abruptly leaves session...');
      await host.jam.leaveJam();
      await pumpEventQueue();

      expect(guest1.jam.isHost, true, reason: 'Oldest guest (Guest 1) must be promoted to Host immediately');
      expect(guest2.jam.isHost, false, reason: 'Younger guest (Guest 2) must remain Guest');
      expect(guest1.player.queue.length, 4, reason: 'Promoted guest queue must NOT be wiped');
      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(guest2.player.queue.length, 4);

      network.log('TEST', '--- Test 15 PASSED: Oldest guest promoted to Host and queue preserved ---');
    });

    test('16. Impatient button spam: Rapid Play/Pause toggles stabilize cleanly without desync', () async {
      network.log('TEST', '--- Starting Test 16: Rapid Play/Pause spam ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(guest1.player.isPlaying, true);

      // User spams pause -> resume -> pause in rapid succession (within 20ms)
      network.log('TEST', 'User rapidly taps Pause -> Resume -> Pause...');
      await guest1.jam.pause();
      await guest1.jam.resume();
      await guest1.jam.pause();
      await pumpEventQueue();

      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // Both Host and Guest 1 must be in paused state cleanly
      expect(guest1.player.isPlaying, false, reason: 'Final state of spam should be paused');
      expect(host.player.isPlaying, false, reason: 'Host should follow final paused state');

      network.log('TEST', '--- Test 16 PASSED: Rapid toggle spam settled stably ---');
    });

    test('17. Real JSON isolation: In-memory mutation of queue on one client does not affect others', () async {
      network.log('TEST', '--- Starting Test 17: Real JSON payload isolation ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      final playlist = [trackA, trackB, trackC];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await pumpEventQueue();

      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Verify all 3 have 3 items
      expect(host.player.queue.length, 3);
      expect(guest1.player.queue.length, 3);
      expect(guest2.player.queue.length, 3);

      // Locally mutate Guest 1 queue (simulate direct local manipulation)
      await guest1.player.removeFromQueue(0);
      expect(guest1.player.queue.length, 2);

      // Host and Guest 2 queues MUST STILL be 3 because they do NOT share memory references
      expect(host.player.queue.length, 3, reason: 'Host queue memory must be completely isolated');
      expect(guest2.player.queue.length, 3, reason: 'Guest 2 queue memory must be completely isolated');

      network.log('TEST', '--- Test 17 PASSED: Memory references strictly isolated across clients ---');
    });

    test('18. Slow async track loading with position ticks during manifest resolution emits 0 old-track broadcasts', () async {
      network.log('TEST', '--- Starting Test 18: Slow async track load with position ticks ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      await host.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(host.player.currentTrack?.id, 'yt:song_a');
      expect(guest1.player.currentTrack?.id, 'yt:song_a');

      // Enable slow manifest extraction with position ticks firing on the old track
      host.player.simulatedBufferingDelayMs = 200;
      host.player.emitPositionTicksWhileLoading = true;

      final broadcastsBefore = host.service.broadcastHistory.length;

      // Host selects Track B while Track A is still emitting position ticks during the 200ms load
      await host.jam.playTrack(trackB);
      await Future.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      final newBroadcasts = host.service.broadcastHistory.skip(broadcastsBefore).toList();
      final spuriousOldTrackBroadcasts = newBroadcasts.where(
        (a) =>
            a.type == JamActionType.playTrack &&
            TrackSource.stripPrefix(a.track?.id ?? '') == 'song_a',
      );

      expect(
        spuriousOldTrackBroadcasts.isEmpty,
        true,
        reason: 'Host MUST NOT broadcast old track Song A while Song B is resolving!',
      );
      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(guest2.player.currentTrack?.id, 'yt:song_b');

      network.log('TEST', '--- Test 18 PASSED: _localActionDepth guard prevented old-track echo race ---');
    });

    test('19. Raw vs prefixed Track IDs ("song_a" vs "yt:song_a") resolve accurately in skipToNext and skipToPrevious', () async {
      network.log('TEST', '--- Starting Test 19: Raw vs prefixed Track IDs in queue navigation ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');

      // Queue has raw IDs (as returned by YouTube search), while currentTrack has prefixed ID
      final rawQueue = [
        Track(id: 'song_a', title: 'Song Alpha', artist: 'Artist 1', thumbnailUrl: '', source: TrackSource.youtube),
        Track(id: 'song_b', title: 'Song Beta', artist: 'Artist 2', thumbnailUrl: '', source: TrackSource.youtube),
        Track(id: 'song_c', title: 'Song Gamma', artist: 'Artist 3', thumbnailUrl: '', source: TrackSource.youtube),
      ];

      await host.jam.playPlaylist(rawQueue, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Simulate MediaItem setting currentTrack with 'yt:' prefix
      await host.player.playTrack(trackA);
      // Restore the raw-ID queue
      await host.player.updateQueuePreservingCurrent(rawQueue, currentIndex: 0);

      await host.jam.skipToNext();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(TrackSource.stripPrefix(host.player.currentTrack?.id ?? ''), 'song_b');
      expect(TrackSource.stripPrefix(guest1.player.currentTrack?.id ?? ''), 'song_b');

      await host.jam.skipToPrevious();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(TrackSource.stripPrefix(host.player.currentTrack?.id ?? ''), 'song_a');
      expect(TrackSource.stripPrefix(guest1.player.currentTrack?.id ?? ''), 'song_a');

      network.log('TEST', '--- Test 19 PASSED: Normalized Track IDs work across skipToNext & skipToPrevious ---');
    });

    test('20. Mid-playlist shuffleQueue preserves current track and playback position across all peers', () async {
      network.log('TEST', '--- Starting Test 20: Mid-playlist shuffleQueue without restarting track ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 1); // Playing Song Beta (index 1)
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Advance all clients to 45s into Song Beta
      host.player.advancePlaybackSeconds(45);
      guest1.player.advancePlaybackSeconds(45);
      guest2.player.advancePlaybackSeconds(45);

      // Guest 1 triggers shuffleQueue mid-song
      await guest1.jam.shuffleQueue();
      await Future.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      // All 3 clients must STILL be playing Song Beta and MUST NOT have reset position to 0s!
      expect(host.player.currentTrack?.id, 'yt:song_b');
      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(guest2.player.currentTrack?.id, 'yt:song_b');

      expect(host.player.position.inSeconds, 45, reason: 'Host position must not reset to 0 on shuffleQueue');
      expect(guest1.player.position.inSeconds, 45, reason: 'Guest 1 position must not reset to 0 on shuffleQueue');
      expect(guest2.player.position.inSeconds, 45, reason: 'Guest 2 position must not reset to 0 on shuffleQueue');

      // All 3 clients must share the exact same queue order
      final hostQueueIds = host.player.queue.map((t) => TrackSource.stripPrefix(t.id)).toList();
      final guest1QueueIds = guest1.player.queue.map((t) => TrackSource.stripPrefix(t.id)).toList();
      final guest2QueueIds = guest2.player.queue.map((t) => TrackSource.stripPrefix(t.id)).toList();
      expect(hostQueueIds, equals(guest1QueueIds));
      expect(guest2QueueIds, equals(guest1QueueIds));

      network.log('TEST', '--- Test 20 PASSED: Mid-playlist shuffle preserved active track & position ---');
    });

    test('21. Host failover followed by natural track completion on promoted Host advances remaining guests', () async {
      network.log('TEST', '--- Starting Test 21: Host failover + natural track completion ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      guest1.service.joinedAt = 1000;
      await guest2.jam.joinJam('JAM123');
      guest2.service.joinedAt = 2000;
      network.syncPresence();
      await pumpEventQueue();

      final playlist = [trackA, trackB, trackC];
      await host.jam.playPlaylist(playlist, initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      // Original Host leaves
      await host.jam.leaveJam();
      await pumpEventQueue();

      expect(guest1.jam.isHost, true);
      expect(guest2.jam.isHost, false);

      // Promoted Host (Guest 1) naturally finishes Song A -> advances to Song B
      guest1.player.simulateNaturalTrackCompletion();
      await Future.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(
        guest2.player.currentTrack?.id,
        'yt:song_b',
        reason: 'Guest 2 must receive natural track advance from newly promoted Host (Guest 1)',
      );

      network.log('TEST', '--- Test 21 PASSED: Promoted Host drives natural track advances for room ---');
    });

    test('22. Queue recovery on syncPulse when guest local queue is empty', () async {
      network.log('TEST', '--- Starting Test 22: Queue recovery via syncPulse ---');

      await host.jam.createJam();
      final playlist = [trackA, trackB, trackC, trackD];
      await host.jam.playPlaylist(playlist, initialIndex: 1);
      host.player.advancePlaybackSeconds(30);

      await guest1.jam.joinJam('JAM123');
      await Future.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();
      // Simulate Guest 1 having only the single track or empty queue (missed initial syncState)
      await guest1.player.clearQueue();
      expect(guest1.player.queue.isEmpty, true);

      // Deliver a syncPulse from Host
      guest1.service.deliverAction(JamAction(
        id: 'pulse_with_track_b',
        type: JamActionType.syncPulse,
        track: trackB,
        positionMs: 30000,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: host.service.myUserId,
      ));
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      // Guest 1 should have requested full sync from Host and recovered all 4 tracks
      expect(guest1.player.queue.length, 4, reason: 'Guest 1 should recover full 4-track queue from Host');
      expect(guest1.player.currentTrack?.id, 'yt:song_b');

      network.log('TEST', '--- Test 22 PASSED: Queue recovered automatically from syncPulse ---');
    });

    test('23. Clear queue synchronizes across all clients and stops playback cleanly', () async {
      network.log('TEST', '--- Starting Test 23: clearQueue synchronization ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      await host.jam.playPlaylist([trackA, trackB, trackC], initialIndex: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(host.player.queue.length, 3);
      expect(guest1.player.queue.length, 3);
      expect(guest2.player.queue.length, 3);

      // Guest 2 clears the queue
      await guest2.jam.clearQueue();
      await Future.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      expect(host.player.queue.isEmpty, true);
      expect(guest1.player.queue.isEmpty, true);
      expect(guest2.player.queue.isEmpty, true);

      network.log('TEST', '--- Test 23 PASSED: clearQueue synchronized across all 3 clients ---');
    });

    test('24. syncPulse does not overwrite lastActionBy or flicker syncStatus when locked', () async {
      network.log('TEST', '--- Starting Test 24: syncPulse metadata & status stability ---');

      await host.jam.createJam();
      await guest1.jam.joinJam('JAM123');
      await guest2.jam.joinJam('JAM123');

      await guest1.jam.playTrack(trackA);
      await Future.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      expect(guest2.jam.lastActionBy, 'Guest 1');
      expect(guest2.jam.syncStatus, JamSyncStatus.synced);

      // Wait past track change grace window so syncPulse is processed
      // We can test that delivering a syncPulse does not overwrite lastActionBy
      guest2.service.deliverAction(JamAction(
        id: 'heartbeat_pulse_99',
        type: JamActionType.syncPulse,
        track: trackA,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: host.service.myUserId,
      ));
      await Future.delayed(const Duration(milliseconds: 100));
      await pumpEventQueue();

      expect(
        guest2.jam.lastActionBy,
        'Guest 1',
        reason: 'Background syncPulse from Host must NOT overwrite lastActionBy!',
      );
      expect(guest2.jam.syncStatus, JamSyncStatus.synced);

      network.log('TEST', '--- Test 24 PASSED: lastActionBy and syncStatus remain stable across heartbeats ---');
    });

    test('25. Joining a non-existent Jam room throws JamSessionNotFoundException and cleans up state', () async {
      network.log('TEST', '--- Starting Test 25: Non-existent Jam room error handling ---');

      await expectLater(
        () => guest1.jam.joinJam('GHOST9'),
        throwsA(isA<JamSessionNotFoundException>()),
      );

      expect(guest1.jam.isInJam, false);
      expect(guest1.jam.jamCode, isNull);

      network.log('TEST', '--- Test 25 PASSED: Non-existent room rejected cleanly ---');
    });

    test('26. Joining a paused Jam session loads queue and position in paused state without playing audio', () async {
      network.log('TEST', '--- Starting Test 26: Joining paused Jam session ---');

      await host.jam.createJam();
      final playlist = [trackA, trackB, trackC];
      await host.jam.playPlaylist(playlist, initialIndex: 1);
      host.player.advancePlaybackSeconds(60);
      await host.jam.pause();
      await pumpEventQueue();

      expect(host.player.isPlaying, false);
      expect(host.player.currentTrack?.id, 'yt:song_b');

      // Guest 1 joins while Host is paused at 60s of Song Beta
      await guest1.jam.joinJam('JAM123');
      await Future.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue();

      expect(guest1.player.currentTrack?.id, 'yt:song_b');
      expect(guest1.player.queue.length, 3);
      expect(guest1.player.isPlaying, false, reason: 'Guest 1 must remain paused when joining a paused Jam');
      expect(guest1.player.position.inSeconds, 60);

      network.log('TEST', '--- Test 26 PASSED: Paused Jam state synced accurately without audio blip ---');
    });
  });
}
