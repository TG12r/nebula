import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nebula/features/jam/data/jam_service.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

/// Sync status for visual indicators in the UI.
enum JamSyncStatus {
  synced,
  syncing,
  buffering,
}

/// Manages Jam session state and coordinates between
/// [JamService] (network) and [PlayerController] (local playback).
///
/// Features:
/// - Anti-echo guard for both remote and local actions to prevent broadcast loops.
/// - Network latency and local media loading time compensation.
/// - Continuous periodic heartbeat (syncPulse) by the Host with drift correction.
/// - Complete queue and playlist synchronization across all devices without audio dropouts.
/// - Deterministic automatic host migration if the current host disconnects.
class JamController extends ChangeNotifier {
  final JamService _jamService;
  final PlayerController _playerController;

  // State
  bool _isInJam = false;
  bool _isHost = false;
  String? _jamCode;
  List<JamParticipant> _participants = [];
  String? _lastActionBy;
  JamSyncStatus _syncStatus = JamSyncStatus.synced;

  // Guards to prevent echo loops when applying remote or local actions
  bool _isApplyingRemoteAction = false;
  int _localActionDepth = 0;
  bool get _isPerformingLocalAction => _localActionDepth > 0;

  bool _isProcessingAction = false;
  final List<JamAction> _actionQueue = [];
  bool _hasReceivedInitialSync = false;
  bool _hasObservedHost = false;
  DateTime? _sessionJoinTime;
  DateTime? _lastTrackChangeTime;
  DateTime? _lastSkipTime;
  JamActionType? _lastSkipType;
  bool _isDisposed = false;
  int _localActionSeq = 0;

  // Network robustness: Per-sender monotonic timestamps to drop out-of-order stale packets
  final Map<String, int> _lastActionTimestamps = {};

  // Network robustness: Action ID deduplication against duplicate/retransmitted packets
  final Set<String> _processedActionIds = {};
  final List<String> _recentActionIdOrder = [];
  static const int _maxProcessedActionHistory = 300;

  bool _hasProcessedAction(String id) => _processedActionIds.contains(id);

  void _recordProcessedAction(String id) {
    _processedActionIds.add(id);
    _recentActionIdOrder.add(id);
    if (_recentActionIdOrder.length > _maxProcessedActionHistory) {
      final oldest = _recentActionIdOrder.removeAt(0);
      _processedActionIds.remove(oldest);
    }
  }

  String _nextActionId() {
    return '${_currentUserId}_${DateTime.now().microsecondsSinceEpoch}_${++_localActionSeq}';
  }

  // Active sync timer for guests to guarantee initial state arrival
  Timer? _initialSyncTimer;
  int _syncRequestAttempts = 0;

  // Timer for delayed host failover check if no host was initially observed
  Timer? _hostFailoverTimer;

  // Heartbeat timer for host drift correction
  Timer? _heartbeatTimer;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Getters
  bool get isInJam => _isInJam;
  bool get isHost => _isHost;
  String? get jamCode => _jamCode;
  List<JamParticipant> get participants => _participants;
  String? get lastActionBy => _lastActionBy;
  JamSyncStatus get syncStatus => _syncStatus;

  String? _lastTrackId;
  bool _lastIsPlaying = false;

  bool _isSameTrackId(String? id1, String? id2) {
    if (id1 == null || id2 == null) return id1 == id2;
    return TrackSource.stripPrefix(id1) == TrackSource.stripPrefix(id2);
  }

  bool _isSameQueue(List<Track> q1, List<Track> q2) {
    if (q1.length != q2.length) return false;
    for (int i = 0; i < q1.length; i++) {
      if (!_isSameTrackId(q1[i].id, q2[i].id)) return false;
    }
    return true;
  }

  bool _isUserInitiatedAction(JamActionType type) {
    switch (type) {
      case JamActionType.requestSync:
      case JamActionType.syncState:
      case JamActionType.syncPulse:
        return false;
      case JamActionType.playTrack:
      case JamActionType.pause:
      case JamActionType.resume:
      case JamActionType.skipNext:
      case JamActionType.skipPrev:
      case JamActionType.addToQueue:
      case JamActionType.removeFromQueue:
      case JamActionType.clearQueue:
      case JamActionType.setQueue:
      case JamActionType.seek:
        return true;
    }
  }

  JamController(this._jamService, this._playerController, [String? userId]) {
    _lastTrackId = _playerController.currentTrack?.id;
    _lastIsPlaying = _playerController.isPlaying;
    _initStreams();
  }

  void _initStreams() {
    // Listen for remote Jam actions
    _subscriptions.add(
      _jamService.onAction.listen(_handleRemoteAction),
    );

    // Listen for participant changes & handle host failover / conflict resolution
    _subscriptions.add(
      _jamService.participantsStream.listen((participants) {
        _participants = participants;
        _evaluateHostRoles(participants);
        notifyListeners();
      }),
    );

    // Listen for new connections: Host proactively sends state
    _subscriptions.add(
      _jamService.onConnectionReady.listen((remoteId) {
        if (_isHost) {
          _sendFullSyncState(remoteId);
        }
      }),
    );

    // Listen for channel reconnections (e.g. mobile wake from sleep or Wi-Fi drop)
    _subscriptions.add(
      _jamService.onReconnected.listen((_) {
        debugPrint('JAM: Channel reconnected. Ensuring active session synchronization...');
        if (_isInJam) {
          _lastActionTimestamps.clear();
          if (_isHost) {
            _sendFullSyncState('all');
          } else {
            _hasReceivedInitialSync = false;
            _startSyncPolling();
          }
        }
      }),
    );

    // Listen to PlayerController state changes
    _playerController.addListener(_onPlayerStateChanged);
  }

  void _evaluateHostRoles(List<JamParticipant> participants) {
    if (!_isInJam || participants.isEmpty) return;

    final hosts = participants.where((p) => p.isHost).toList()
      ..sort((a, b) {
        final cmp = a.joinedAt.compareTo(b.joinedAt);
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });

    // 1. Conflict resolution: If multiple hosts exist, only the oldest host stays host!
    if (_isHost && hosts.length > 1) {
      final oldestHost = hosts.first;
      if (oldestHost.id != _currentUserId) {
        debugPrint(
            'JAM: Multiple hosts detected. Demoting self to guest (oldest host is ${oldestHost.id}).');
        _isHost = false;
        _jamService.updateHostPresence(false);
        _stopHeartbeat();
        return;
      }
    }

    // 2. Remember if we've seen an active host in this session
    if (hosts.isNotEmpty) {
      _hasObservedHost = true;
      _hostFailoverTimer?.cancel();
      _hostFailoverTimer = null;
      return;
    }

    // 3. Auto host failover when hosts.isEmpty:
    if (!_isHost && hosts.isEmpty) {
      if (_hasObservedHost) {
        // We previously observed an active host who has now disconnected: promote oldest immediately!
        _promoteOldestToHost(participants);
      } else if (_sessionJoinTime != null) {
        final elapsed = DateTime.now().difference(_sessionJoinTime!);
        if (elapsed >= const Duration(seconds: 6)) {
          _promoteOldestToHost(participants);
        } else {
          // Schedule deferred check when the initial 6s join window completes
          _hostFailoverTimer?.cancel();
          final remaining = const Duration(seconds: 6) - elapsed;
          _hostFailoverTimer = Timer(remaining, () {
            if (_isInJam && !_isHost) {
              _evaluateHostRoles(_participants);
              notifyListeners();
            }
          });
        }
      }
    }
  }

  void _promoteOldestToHost(List<JamParticipant> participants) {
    if (participants.isEmpty) return;
    final sorted = List<JamParticipant>.from(participants)
      ..sort((a, b) {
        final cmp = a.joinedAt.compareTo(b.joinedAt);
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });
    final oldest = sorted.first;

    if (oldest.id == _currentUserId) {
      debugPrint('JAM: Host left. Promoting self ($_currentUserId) to Host.');
      _isHost = true;
      _hasObservedHost = true;
      _lastTrackId = _playerController.currentTrack?.id;
      _lastIsPlaying = _playerController.isPlaying;
      _initialSyncTimer?.cancel();
      _initialSyncTimer = null;
      _hostFailoverTimer?.cancel();
      _hostFailoverTimer = null;
      _jamService.updateHostPresence(true);
      _startHeartbeat();
      _sendFullSyncState('all');
    }
  }

  void _onPlayerStateChanged() {
    if (!_isInJam) return;

    if (_playerController.isBuffering) {
      _setSyncStatus(JamSyncStatus.buffering);
    } else if (_syncStatus == JamSyncStatus.buffering) {
      _setSyncStatus(JamSyncStatus.synced);
    }

    // Suppress broadcast if a remote or local JamController action is actively mutating the player
    if (_isApplyingRemoteAction || _isPerformingLocalAction) return;

    // ONLY the Host broadcasts natural, unprompted player state changes
    // (such as when a track naturally finishes and advances to the next track)
    if (!_isHost) return;

    final currentTrack = _playerController.currentTrack;
    final isPlaying = _playerController.isPlaying;

    bool trackChanged = false;
    bool playStateChanged = false;

    if (currentTrack != null && !_isSameTrackId(currentTrack.id, _lastTrackId)) {
      trackChanged = true;
      _lastTrackId = currentTrack.id;
      _lastIsPlaying = isPlaying;
      _lastTrackChangeTime = DateTime.now();
    } else if (!_playerController.isBuffering && isPlaying != _lastIsPlaying) {
      playStateChanged = true;
      _lastIsPlaying = isPlaying;
    }

    if (trackChanged && currentTrack != null) {
      debugPrint('JAM: Host track changed naturally. Broadcasting new track: ${currentTrack.title}');
      int queueIdx = -1;
      if (_playerController.queue.isNotEmpty) {
        queueIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, currentTrack.id));
      }
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.playTrack,
        track: currentTrack,
        queueIndex: queueIdx >= 0 ? queueIdx : null,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: isPlaying,
        senderId: _currentUserId,
      ));
    } else if (playStateChanged) {
      debugPrint('JAM: Host play state changed naturally ($isPlaying). Broadcasting.');
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: isPlaying ? JamActionType.resume : JamActionType.pause,
        track: currentTrack,
        positionMs: _playerController.position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: isPlaying,
        senderId: _currentUserId,
      ));
    }
  }

  // --- Public Actions (called by UI) ---

  /// Creates a new Jam session.
  Future<String> createJam() async {
    final code = await _jamService.createJam();
    _isInJam = true;
    _isHost = true;
    _hasObservedHost = true;
    _sessionJoinTime = DateTime.now();
    _lastTrackId = _playerController.currentTrack?.id;
    _lastIsPlaying = _playerController.isPlaying;
    _jamCode = code;
    _startHeartbeat();
    notifyListeners();
    return code;
  }

  /// Joins an existing Jam session by code.
  Future<void> joinJam(String code) async {
    _hasReceivedInitialSync = false;
    _hasObservedHost = false;
    _sessionJoinTime = DateTime.now();
    _lastTrackId = _playerController.currentTrack?.id;
    _lastIsPlaying = _playerController.isPlaying;
    await _jamService.joinJam(code);
    _isInJam = true;
    _isHost = false;
    _jamCode = code.trim().toUpperCase();
    _stopHeartbeat();
    if (_participants.any((p) => p.isHost)) {
      _hasObservedHost = true;
    }
    notifyListeners();

    // Active handshake: Proactively request sync every 1200ms until initial state arrives (up to 5 attempts)
    _startSyncPolling();
  }

  void _startSyncPolling() {
    _initialSyncTimer?.cancel();
    _syncRequestAttempts = 0;
    if (_hasReceivedInitialSync) return;
    // Immediately fire the first sync request!
    _jamService.requestSync();
    _initialSyncTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!_isInJam || _isHost || _hasReceivedInitialSync) {
        timer.cancel();
        _initialSyncTimer = null;
        return;
      }
      _syncRequestAttempts++;
      if (_syncRequestAttempts > 5) {
        debugPrint('JAM: Max initial sync requests reached without response.');
        timer.cancel();
        _initialSyncTimer = null;
        return;
      }
      debugPrint('JAM: Requesting sync from host (attempt $_syncRequestAttempts/5)...');
      _jamService.requestSync();
    });
  }

  /// Leaves the current Jam session.
  Future<void> leaveJam() async {
    _stopHeartbeat();
    _initialSyncTimer?.cancel();
    _initialSyncTimer = null;
    _hostFailoverTimer?.cancel();
    _hostFailoverTimer = null;
    _syncRequestAttempts = 0;
    await _jamService.leaveJam();
    _isInJam = false;
    _isHost = false;
    _jamCode = null;
    _participants = [];
    _lastActionBy = null;
    _hasReceivedInitialSync = false;
    _hasObservedHost = false;
    _sessionJoinTime = null;
    _actionQueue.clear();
    _lastActionTimestamps.clear();
    _processedActionIds.clear();
    _recentActionIdOrder.clear();
    _lastSkipTime = null;
    _lastSkipType = null;
    _isProcessingAction = false;
    _isApplyingRemoteAction = false;
    _localActionDepth = 0;
    _syncStatus = JamSyncStatus.synced;
    notifyListeners();
  }

  // --- Jam-Aware Player Actions ---

  void _recordLocalUserAction() {
    if (_isInJam) {
      _lastActionBy = _findParticipantName(_currentUserId) ?? 'YOU';
      notifyListeners();
    }
  }

  /// Play a specific track, broadcasting to all peers if active.
  Future<void> playTrack(Track track) async {
    _lastTrackId = track.id;
    _lastIsPlaying = true;
    _lastTrackChangeTime = DateTime.now();

    _localActionDepth++;
    try {
      await _playerController.playTrack(track);
      _lastTrackId = track.id;
      _lastIsPlaying = true;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.playTrack,
        track: track,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: _currentUserId,
      ));
    }
  }

  /// Play a playlist, broadcasting the entire queue to all peers.
  Future<void> playPlaylist(
    List<Track> tracks, {
    int? initialIndex,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;

    List<Track> listToPlay;
    int targetIndex;

    if (shuffle) {
      if (initialIndex != null && initialIndex >= 0 && initialIndex < tracks.length) {
        final selectedTrack = tracks[initialIndex];
        final remainingTracks = List<Track>.from(tracks)..removeAt(initialIndex);
        remainingTracks.shuffle();
        listToPlay = [selectedTrack, ...remainingTracks];
        targetIndex = 0;
      } else {
        listToPlay = List<Track>.from(tracks)..shuffle();
        targetIndex = 0;
      }
    } else {
      listToPlay = List<Track>.from(tracks);
      targetIndex = (initialIndex ?? 0).clamp(0, tracks.length - 1);
    }

    _lastTrackId = listToPlay[targetIndex].id;
    _lastIsPlaying = true;
    _lastTrackChangeTime = DateTime.now();

    _localActionDepth++;
    try {
      await _playerController.playPlaylist(
        listToPlay,
        initialIndex: targetIndex,
        shuffle: false,
      );
      _lastTrackId = listToPlay[targetIndex].id;
      _lastIsPlaying = true;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam && listToPlay.isNotEmpty) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.setQueue,
        track: listToPlay[targetIndex],
        queue: listToPlay,
        queueIndex: targetIndex,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: _currentUserId,
      ));
    }
  }

  /// Play a mix query, broadcasting the resulting playlist.
  Future<bool> playMix(String query) async {
    _lastTrackChangeTime = DateTime.now();
    bool success = false;
    _localActionDepth++;
    try {
      success = await _playerController.playMix(query);
      if (success) {
        _lastTrackId = _playerController.currentTrack?.id;
        _lastIsPlaying = _playerController.isPlaying;
      }
    } finally {
      _localActionDepth--;
    }

    if (success && _isInJam && _playerController.queue.isNotEmpty) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.setQueue,
        track: _playerController.currentTrack,
        queue: _playerController.queue,
        queueIndex: 0,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: _currentUserId,
      ));
    }
    return success;
  }

  /// Skip to a specific item in the current queue, broadcasting to all peers.
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playerController.queue.length) return;
    final track = _playerController.queue[index];
    _lastTrackId = track.id;
    _lastIsPlaying = true;
    _lastTrackChangeTime = DateTime.now();

    _localActionDepth++;
    try {
      await _playerController.skipToQueueItem(index);
      _lastTrackId = track.id;
      _lastIsPlaying = true;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.setQueue,
        track: track,
        queue: _playerController.queue,
        queueIndex: index,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: _currentUserId,
      ));
    }
  }

  /// Pause playback, broadcasting exact position and timestamp.
  Future<void> pause() async {
    final pos = _playerController.position.inMilliseconds;
    _lastIsPlaying = false;
    _localActionDepth++;
    try {
      await _playerController.pause();
      _lastIsPlaying = false;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.pause,
        track: _playerController.currentTrack,
        positionMs: pos,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: false,
        senderId: _currentUserId,
      ));
    }
  }

  /// Resume playback, broadcasting exact position and timestamp.
  Future<void> resume() async {
    final pos = _playerController.position.inMilliseconds;
    _lastIsPlaying = true;
    _localActionDepth++;
    try {
      await _playerController.resume();
      _lastIsPlaying = true;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.resume,
        track: _playerController.currentTrack,
        positionMs: pos,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: true,
        senderId: _currentUserId,
      ));
    }
  }

  /// Toggle play/pause.
  Future<void> togglePlay() async {
    if (_playerController.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Skip to next track.
  Future<void> skipToNext() async {
    _lastSkipTime = DateTime.now();
    _lastSkipType = JamActionType.skipNext;
    _lastTrackChangeTime = DateTime.now();
    final queue = _playerController.queue;
    final current = _playerController.currentTrack;
    Track? nextTrack;
    int? nextIdx;

    if (queue.isNotEmpty && current != null) {
      final currentIdx = queue.indexWhere((t) => _isSameTrackId(t.id, current.id));
      if (currentIdx != -1 && currentIdx + 1 < queue.length) {
        nextIdx = currentIdx + 1;
        nextTrack = queue[nextIdx];
        _lastTrackId = nextTrack.id;
      } else if (currentIdx != -1 && currentIdx + 1 >= queue.length) {
        // Already at the end of the queue; nothing to skip to.
        return;
      }
    }

    _localActionDepth++;
    try {
      await _playerController.skipToNext();
      if (nextTrack != null) {
        _lastTrackId = nextTrack.id;
      } else if (!_isSameTrackId(_playerController.currentTrack?.id, current?.id)) {
        nextTrack = _playerController.currentTrack;
        _lastTrackId = nextTrack?.id;
      }
      _lastIsPlaying = _playerController.isPlaying;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam && (nextTrack != null || queue.isEmpty)) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.skipNext,
        track: nextTrack,
        queueIndex: nextIdx,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Skip to previous track.
  Future<void> skipToPrevious() async {
    _lastSkipTime = DateTime.now();
    _lastSkipType = JamActionType.skipPrev;
    _lastTrackChangeTime = DateTime.now();
    final queue = _playerController.queue;
    final current = _playerController.currentTrack;
    Track? prevTrack;
    int? prevIdx;

    if (queue.isNotEmpty && current != null) {
      final currentIdx = queue.indexWhere((t) => _isSameTrackId(t.id, current.id));
      if (currentIdx > 0) {
        prevIdx = currentIdx - 1;
        prevTrack = queue[prevIdx];
        _lastTrackId = prevTrack.id;
      } else if (currentIdx == 0) {
        // At track 0: restart track at 0:00
        await seek(Duration.zero);
        return;
      }
    }

    _localActionDepth++;
    try {
      await _playerController.skipToPrevious();
      if (prevTrack != null) {
        _lastTrackId = prevTrack.id;
      } else if (!_isSameTrackId(_playerController.currentTrack?.id, current?.id)) {
        prevTrack = _playerController.currentTrack;
        _lastTrackId = prevTrack?.id;
      }
      _lastIsPlaying = _playerController.isPlaying;
    } finally {
      _localActionDepth--;
    }

    if (_isInJam && (prevTrack != null || queue.isEmpty)) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.skipPrev,
        track: prevTrack,
        queueIndex: prevIdx,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Add a track to the queue, broadcasting to all peers.
  Future<void> addToQueue(Track track) async {
    _localActionDepth++;
    try {
      await _playerController.addToQueue(track);
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.addToQueue,
        track: track,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Remove a track from the queue by index.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _playerController.queue.length) return;
    final track = _playerController.queue[index];
    _localActionDepth++;
    try {
      await _playerController.removeFromQueue(index);
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.removeFromQueue,
        track: track,
        queueIndex: index,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Clears the entire shared queue and stops playback.
  Future<void> clearQueue() async {
    _lastTrackId = null;
    _lastIsPlaying = false;
    _localActionDepth++;
    try {
      await _playerController.clearQueue();
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.clearQueue,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Shuffle the queue, broadcasting the new queue order while preserving the active track.
  Future<void> shuffleQueue() async {
    _localActionDepth++;
    try {
      await _playerController.shuffleQueue();
    } finally {
      _localActionDepth--;
    }

    if (_isInJam && _playerController.queue.isNotEmpty) {
      _recordLocalUserAction();
      final current = _playerController.currentTrack;
      int currentIdx = 0;
      if (current != null) {
        final foundIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, current.id));
        if (foundIdx != -1) {
          currentIdx = foundIdx;
        }
      }
      _lastTrackId = current?.id;
      _lastIsPlaying = _playerController.isPlaying;
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.setQueue,
        track: current ?? _playerController.queue[currentIdx],
        queue: _playerController.queue,
        queueIndex: currentIdx,
        positionMs: _playerController.position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: _playerController.isPlaying,
        senderId: _currentUserId,
      ));
    }
  }

  /// Reorder the queue from [oldIndex] to [newIndex], broadcasting the new queue.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _localActionDepth++;
    try {
      await _playerController.reorderQueue(oldIndex, newIndex);
    } finally {
      _localActionDepth--;
    }

    if (_isInJam && _playerController.queue.isNotEmpty) {
      _recordLocalUserAction();
      final current = _playerController.currentTrack;
      int currentIdx = 0;
      if (current != null) {
        final foundIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, current.id));
        if (foundIdx != -1) {
          currentIdx = foundIdx;
        }
      }
      _lastTrackId = current?.id;
      _lastIsPlaying = _playerController.isPlaying;
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.setQueue,
        track: current ?? _playerController.queue[currentIdx],
        queue: _playerController.queue,
        queueIndex: currentIdx,
        positionMs: _playerController.position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: _playerController.isPlaying,
        senderId: _currentUserId,
      ));
    }
  }

  /// Seek to position, broadcasting to all peers with timestamp.
  Future<void> seek(Duration position) async {
    _localActionDepth++;
    try {
      await _playerController.seek(position);
    } finally {
      _localActionDepth--;
    }

    if (_isInJam) {
      _recordLocalUserAction();
      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.seek,
        track: _playerController.currentTrack,
        positionMs: position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: _playerController.isPlaying,
        senderId: _currentUserId,
      ));
    }
  }

  // --- Private Implementation ---

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isHost || !_isInJam) return;
      if (_playerController.currentTrack == null && _playerController.queue.isEmpty) return;

      // Do NOT send pulse if Host is actively applying an action or buffering
      if (_isApplyingRemoteAction || _isPerformingLocalAction || _playerController.isBuffering) {
        return;
      }

      // Do NOT send pulse if Host recently changed track (give 5s quiet grace period to stabilize)
      if (_lastTrackChangeTime != null &&
          DateTime.now().difference(_lastTrackChangeTime!) < const Duration(seconds: 5)) {
        return;
      }

      _broadcastAction(JamAction(
        id: _nextActionId(),
        type: JamActionType.syncPulse,
        track: _playerController.currentTrack,
        positionMs: _playerController.position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: _playerController.isPlaying,
        senderId: _currentUserId,
      ));
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _setSyncStatus(JamSyncStatus status) {
    if (_syncStatus != status) {
      _syncStatus = status;
      notifyListeners();
    }
  }

  Future<void> _handleRemoteAction(JamAction action) async {
    if (action.senderId == _currentUserId) return; // Prevent self-echo

    // 1. Packet deduplication: Drop identical network packets re-delivered by the channel
    if (_hasProcessedAction(action.id)) {
      debugPrint('JAM: Dropping duplicate action ${action.id} (${action.type.name})');
      return;
    }
    _recordProcessedAction(action.id);

    // 2. Out-of-order packet drop: Ensure monotonic timestamps per sender for playback mutations
    final isPlaybackMutation = action.type == JamActionType.playTrack ||
        action.type == JamActionType.pause ||
        action.type == JamActionType.resume ||
        action.type == JamActionType.seek ||
        action.type == JamActionType.skipNext ||
        action.type == JamActionType.skipPrev ||
        action.type == JamActionType.setQueue ||
        action.type == JamActionType.syncPulse ||
        action.type == JamActionType.syncState;

    if (isPlaybackMutation && action.timestampMs != null) {
      final lastSenderTs = _lastActionTimestamps[action.senderId];
      if (lastSenderTs != null && action.timestampMs! < lastSenderTs) {
        debugPrint(
            'JAM: Dropping out-of-order action ${action.type.name} from ${action.senderId} (ts ${action.timestampMs} < lastTs $lastSenderTs)');
        return;
      }
      _lastActionTimestamps[action.senderId] = action.timestampMs!;
    }

    // 3. Race condition window: Drop near-simultaneous identical-direction skip actions within 700ms
    if (action.type == JamActionType.skipNext ||
        action.type == JamActionType.skipPrev) {
      if (_lastSkipTime != null &&
          _lastSkipType == action.type &&
          DateTime.now().difference(_lastSkipTime!) < const Duration(milliseconds: 700)) {
        debugPrint(
            'JAM: Dropping near-simultaneous ${action.type.name} from ${action.senderId} (occurred within 700ms of last skip).');
        return;
      }
      _lastSkipTime = DateTime.now();
      _lastSkipType = action.type;
    }

    // 4. Drop redundant syncPulses if queue already has actions, if action is applying, or if track changed recently
    if (action.type == JamActionType.syncPulse) {
      if (_isProcessingAction || _actionQueue.isNotEmpty || _isApplyingRemoteAction || _isPerformingLocalAction) {
        return;
      }
      final needsQueueRecovery =
          (_playerController.queue.isEmpty || !_hasReceivedInitialSync) &&
          action.track != null;
      if (!needsQueueRecovery &&
          _lastTrackChangeTime != null &&
          DateTime.now().difference(_lastTrackChangeTime!) < const Duration(seconds: 5)) {
        return;
      }
    }

    // 5. Coalesce action queue (handling rapid slider scrubbing, duplicate play/pause, obsolete pulses):
    if (action.type == JamActionType.seek) {
      _actionQueue.removeWhere((a) => a.type == JamActionType.seek);
    } else if (action.type == JamActionType.pause || action.type == JamActionType.resume) {
      _actionQueue.removeWhere((a) => a.type == JamActionType.pause || a.type == JamActionType.resume);
    } else if (action.type == JamActionType.syncState) {
      _actionQueue.removeWhere((a) =>
          a.type == JamActionType.syncState ||
          a.type == JamActionType.syncPulse);
    } else if (action.type == JamActionType.clearQueue) {
      _actionQueue.removeWhere((a) =>
          a.type == JamActionType.setQueue ||
          a.type == JamActionType.playTrack ||
          a.type == JamActionType.syncState ||
          a.type == JamActionType.syncPulse ||
          a.type == JamActionType.seek ||
          a.type == JamActionType.pause ||
          a.type == JamActionType.resume ||
          a.type == JamActionType.addToQueue ||
          a.type == JamActionType.removeFromQueue);
    } else if (action.type == JamActionType.setQueue) {
      _actionQueue.removeWhere((a) =>
          a.type == JamActionType.setQueue ||
          a.type == JamActionType.playTrack ||
          a.type == JamActionType.syncState ||
          a.type == JamActionType.syncPulse ||
          a.type == JamActionType.seek ||
          a.type == JamActionType.pause ||
          a.type == JamActionType.resume);
    } else if (action.type == JamActionType.playTrack ||
        action.type == JamActionType.skipNext ||
        action.type == JamActionType.skipPrev) {
      _actionQueue.removeWhere((a) =>
          a.type == JamActionType.syncPulse ||
          a.type == JamActionType.seek ||
          a.type == JamActionType.pause ||
          a.type == JamActionType.resume ||
          (a.type == JamActionType.syncState && (a.queue == null || a.queue!.isEmpty)));
    }

    _actionQueue.add(action);
    if (_isProcessingAction) return;
    _isProcessingAction = true;

    while (_actionQueue.isNotEmpty) {
      final nextAction = _actionQueue.removeAt(0);
      await _executeRemoteAction(nextAction);
    }

    _isProcessingAction = false;
  }

  int _clampPositionToTrack(int targetMs, Track? track) {
    if (targetMs < 0) return 0;
    final durMs = track?.duration.inMilliseconds ??
        _playerController.duration.inMilliseconds;
    if (durMs > 0 && targetMs > durMs) {
      return durMs;
    }
    return targetMs;
  }

  Future<void> _executeRemoteAction(JamAction action) async {
    debugPrint('JAM: Handling remote action: ${action.type.name} from ${action.senderId}');

    // requestSync is purely informational and doesn't mutate player state
    if (action.type == JamActionType.requestSync) {
      if (_isHost) {
        _sendFullSyncState(action.senderId);
      }
      return;
    }

    _isApplyingRemoteAction = true;
    final isUserAction = _isUserInitiatedAction(action.type);
    if (isUserAction) {
      _lastActionBy = _findParticipantName(action.senderId) ?? action.senderId;
    }
    if (action.type != JamActionType.syncPulse) {
      _setSyncStatus(JamSyncStatus.syncing);
    } else if (isUserAction) {
      notifyListeners();
    }

    try {
      final receiveTimeMs = DateTime.now().millisecondsSinceEpoch;
      // Clamp network transit latency to [0, 1500]ms to prevent cross-device wall-clock skew
      // from introducing artificial multi-second jumps, while measuring local load time separately.
      final networkLatency = action.timestampMs != null
          ? (receiveTimeMs - action.timestampMs!).clamp(0, 1500)
          : 0;

      switch (action.type) {
        case JamActionType.requestSync:
          break;

        case JamActionType.syncState:
          await _applySyncState(action, networkLatency);
          break;

        case JamActionType.syncPulse:
          if (!_isHost) {
            await _applySyncPulse(action, networkLatency);
          }
          break;

        case JamActionType.playTrack:
          if (action.track != null) {
            debugPrint('JAM: Remote playTrack ${action.track!.title}');
            _lastTrackId = action.track!.id;
            _lastIsPlaying = action.isPlaying ?? true;
            _lastTrackChangeTime = DateTime.now();

            final loadStartMs = DateTime.now().millisecondsSinceEpoch;
            if (!_isSameTrackId(_playerController.currentTrack?.id, action.track!.id)) {
              // If the track is already in queue, skip to it to preserve queue
              final qIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, action.track!.id));
              if (qIdx != -1) {
                await _playerController.skipToQueueItem(qIdx);
              } else {
                await _playerController.playTrack(
                  action.track!,
                  autoPlay: action.isPlaying ?? true,
                );
              }
            } else if (!_playerController.isPlaying && action.isPlaying == true) {
              await _playerController.resume();
            }

            if (action.isPlaying == false && _playerController.isPlaying) {
              await _playerController.pause();
            }

            final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);
            // Only seek if starting far into the track (> 3s), never on initial track start
            final pos = action.positionMs ?? 0;
            if (pos > 3000 && _playerController.currentTrack != null) {
              final targetPosition = _clampPositionToTrack(
                pos + (action.isPlaying == true ? networkLatency + loadElapsedMs : 0),
                action.track,
              );
              await _playerController.seek(Duration(milliseconds: targetPosition));
            }
          }
          break;

        case JamActionType.pause:
          debugPrint('JAM: Remote pause');
          _lastIsPlaying = false;
          await _playerController.pause();
          if (action.track != null &&
              !_isSameTrackId(_playerController.currentTrack?.id, action.track!.id)) {
            _lastTrackId = action.track!.id;
            await _playerController.playTrack(action.track!, autoPlay: false);
          }
          if (action.positionMs != null && _playerController.currentTrack != null) {
            final drift = (_playerController.position.inMilliseconds - action.positionMs!).abs();
            if (drift > 2000) {
              final targetPos = _clampPositionToTrack(action.positionMs!, action.track);
              await _playerController.seek(Duration(milliseconds: targetPos));
            }
          }
          break;

        case JamActionType.resume:
          debugPrint('JAM: Remote resume');
          _lastIsPlaying = true;
          final loadStartMs = DateTime.now().millisecondsSinceEpoch;
          if (action.track != null &&
              !_isSameTrackId(_playerController.currentTrack?.id, action.track!.id)) {
            _lastTrackId = action.track!.id;
            _lastTrackChangeTime = DateTime.now();
            await _playerController.playTrack(action.track!);
          } else {
            await _playerController.resume();
          }
          final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);
          if (action.positionMs != null && _playerController.currentTrack != null) {
            final targetPosition = _clampPositionToTrack(
              action.positionMs! + networkLatency + loadElapsedMs,
              action.track,
            );
            final drift = (_playerController.position.inMilliseconds - targetPosition).abs();
            if (drift > 3000) {
              await _playerController.seek(Duration(milliseconds: targetPosition));
            }
          }
          break;

        case JamActionType.skipNext:
          debugPrint('JAM: Remote skipNext');
          _lastTrackChangeTime = DateTime.now();
          if (action.track != null) {
            final qIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, action.track!.id));
            if (qIdx != -1) {
              await _playerController.skipToQueueItem(qIdx);
            } else {
              await _playerController.playTrack(action.track!);
            }
          } else if (action.queueIndex != null &&
              action.queueIndex! >= 0 &&
              action.queueIndex! < _playerController.queue.length) {
            await _playerController.skipToQueueItem(action.queueIndex!);
          } else {
            await _playerController.skipToNext();
          }
          _lastTrackId = _playerController.currentTrack?.id;
          _lastIsPlaying = _playerController.isPlaying;
          break;

        case JamActionType.skipPrev:
          debugPrint('JAM: Remote skipPrev');
          _lastTrackChangeTime = DateTime.now();
          if (action.track != null) {
            final qIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, action.track!.id));
            if (qIdx != -1) {
              await _playerController.skipToQueueItem(qIdx);
            } else {
              await _playerController.playTrack(action.track!);
            }
          } else if (action.queueIndex != null &&
              action.queueIndex! >= 0 &&
              action.queueIndex! < _playerController.queue.length) {
            await _playerController.skipToQueueItem(action.queueIndex!);
          } else {
            await _playerController.skipToPrevious();
          }
          _lastTrackId = _playerController.currentTrack?.id;
          _lastIsPlaying = _playerController.isPlaying;
          break;

        case JamActionType.setQueue:
          if (action.queue != null && action.queue!.isNotEmpty) {
            debugPrint('JAM: Remote setQueue with ${action.queue!.length} tracks');
            final initialIdx = (action.queueIndex ?? 0).clamp(0, action.queue!.length - 1);
            final targetTrack = action.queue![initialIdx];
            final isSameActiveTrack = _isSameTrackId(_playerController.currentTrack?.id, targetTrack.id);
            final pos = action.positionMs ?? 0;

            _lastTrackId = targetTrack.id;
            _lastIsPlaying = action.isPlaying ?? true;
            _lastTrackChangeTime = DateTime.now();

            // If we are already playing this exact track mid-song (e.g. queue shuffle),
            // update the queue order without restarting the current audio stream!
            if (isSameActiveTrack && pos > 0) {
              await _playerController.updateQueuePreservingCurrent(
                action.queue!,
                currentIndex: initialIdx,
              );
              if (action.isPlaying == false && _playerController.isPlaying) {
                await _playerController.pause();
              } else if (action.isPlaying == true && !_playerController.isPlaying) {
                await _playerController.resume();
              }
            } else {
              final loadStartMs = DateTime.now().millisecondsSinceEpoch;
              await _playerController.playPlaylist(
                action.queue!,
                initialIndex: initialIdx,
                autoPlay: action.isPlaying ?? true,
              );
              final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);

              if (action.isPlaying == false && _playerController.isPlaying) {
                await _playerController.pause();
              }

              // Only seek if starting far into the track (> 3s), never on initial queue start
              if (pos > 3000 && _playerController.currentTrack != null) {
                final targetPosition = _clampPositionToTrack(
                  pos + (action.isPlaying == true ? networkLatency + loadElapsedMs : 0),
                  targetTrack,
                );
                await _playerController.seek(Duration(milliseconds: targetPosition));
              }
            }
          }
          break;

        case JamActionType.addToQueue:
          if (action.track != null) {
            debugPrint('JAM: Remote addToQueue: ${action.track!.title}');
            await _playerController.addToQueue(action.track!);
          }
          break;

        case JamActionType.removeFromQueue:
          final q = _playerController.queue;
          final idx = action.queueIndex;
          // 1. If queueIndex is in bounds and matches action.track, remove that exact index (supports duplicate tracks)
          if (idx != null && idx >= 0 && idx < q.length) {
            if (action.track == null || _isSameTrackId(q[idx].id, action.track!.id)) {
              debugPrint('JAM: Remote removeFromQueue at exact index $idx');
              await _playerController.removeFromQueue(idx);
              break;
            }
          }
          // 2. Fallback: Content-based removal when concurrent edits shifted the index
          if (action.track != null) {
            final actualIdx = q.indexWhere((t) => _isSameTrackId(t.id, action.track!.id));
            if (actualIdx != -1) {
              debugPrint('JAM: Remote removeFromQueue by track ID (${action.track!.title}) at index $actualIdx');
              await _playerController.removeFromQueue(actualIdx);
              break;
            }
          }
          // 3. Final fallback by index if track wasn't provided
          if (idx != null && idx >= 0 && idx < q.length) {
            debugPrint('JAM: Remote removeFromQueue by index at $idx');
            await _playerController.removeFromQueue(idx);
          }
          break;

        case JamActionType.clearQueue:
          debugPrint('JAM: Remote clearQueue');
          _lastTrackId = null;
          _lastIsPlaying = false;
          await _playerController.clearQueue();
          break;

        case JamActionType.seek:
          final loadStartMs = DateTime.now().millisecondsSinceEpoch;
          if (action.track != null &&
              !_isSameTrackId(_playerController.currentTrack?.id, action.track!.id)) {
            _lastTrackId = action.track!.id;
            _lastTrackChangeTime = DateTime.now();
            await _playerController.playTrack(action.track!, autoPlay: action.isPlaying ?? true);
          }
          final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);
          if (action.positionMs != null && _playerController.currentTrack != null) {
            final seekLatency = (networkLatency + loadElapsedMs).clamp(0, 1500);
            final targetPosition = _clampPositionToTrack(
              action.positionMs! + (_playerController.isPlaying ? seekLatency : 0),
              action.track,
            );
            debugPrint('JAM: Remote seek to $targetPosition ms');
            await _playerController.seek(Duration(milliseconds: targetPosition));
          }
          break;
      }
    } catch (e) {
      debugPrint('JAM: Error processing remote action ${action.type.name}: $e');
    } finally {
      _lastTrackId ??= _playerController.currentTrack?.id;
      if (_actionQueue.isEmpty) {
        await Future<void>.delayed(Duration.zero);
        if (_actionQueue.isEmpty) {
          _isApplyingRemoteAction = false;
          _setSyncStatus(JamSyncStatus.synced);
        }
      }
    }
  }

  Future<void> _applySyncState(JamAction action, int networkLatency) async {
    debugPrint('JAM: Applying full syncState. isPlaying: ${action.isPlaying}');
    _hasReceivedInitialSync = true;
    _initialSyncTimer?.cancel();
    _initialSyncTimer = null;

    if (action.track == null && (action.queue == null || action.queue!.isEmpty)) {
      return;
    }

    final current = _playerController.currentTrack;
    final isSameTrack = action.track != null && _isSameTrackId(current?.id, action.track!.id);
    final hasQueue = action.queue != null && action.queue!.isNotEmpty;
    final initialIdx = hasQueue
        ? (action.queueIndex ?? 0).clamp(0, action.queue!.length - 1)
        : 0;

    final loadStartMs = DateTime.now().millisecondsSinceEpoch;
    if (!isSameTrack) {
      _lastTrackId = action.track?.id ?? (hasQueue ? action.queue![initialIdx].id : null);
      _lastIsPlaying = action.isPlaying ?? true;
      _lastTrackChangeTime = DateTime.now();
      if (hasQueue) {
        await _playerController.playPlaylist(
          action.queue!,
          initialIndex: initialIdx,
          autoPlay: action.isPlaying ?? true,
        );
      } else if (action.track != null) {
        await _playerController.playTrack(
          action.track!,
          autoPlay: action.isPlaying ?? true,
        );
      }
    } else if (hasQueue && !_isSameQueue(_playerController.queue, action.queue!)) {
      // Same track is already playing, but the queue differs: update queue without restarting track!
      await _playerController.updateQueuePreservingCurrent(
        action.queue!,
        currentIndex: initialIdx,
      );
    }
    final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);

    if (action.isPlaying == false) {
      _lastIsPlaying = false;
      await _playerController.pause();
    } else if (action.isPlaying == true && !_playerController.isPlaying) {
      _lastIsPlaying = true;
      await _playerController.resume();
    }

    if (action.positionMs != null && _playerController.currentTrack != null) {
      final targetPos = _clampPositionToTrack(
        action.positionMs! + (action.isPlaying == true ? networkLatency + loadElapsedMs : 0),
        action.track,
      );
      final currentPos = _playerController.position.inMilliseconds;
      final drift = (currentPos - targetPos).abs();

      // Seek if drift is large (> 3s) or if a new track was loaded well into playback (> 3s)
      if (drift > 3000 || (!isSameTrack && targetPos > 3000)) {
        await _playerController.seek(Duration(milliseconds: targetPos));
      }
    }
  }

  Future<void> _applySyncPulse(JamAction action, int networkLatency) async {
    // 0. If local player is currently buffering or loading media, do NOT seek or disturb buffer!
    if (_playerController.isBuffering) {
      debugPrint('JAM: syncPulse ignored because player is currently buffering/loading.');
      return;
    }

    // 1. Queue recovery: If guest has empty queue or hasn't received initial sync, request full sync
    if ((_playerController.queue.isEmpty || !_hasReceivedInitialSync) && action.track != null) {
      debugPrint('JAM: syncPulse received while queue uninitialized. Requesting full sync...');
      _jamService.requestSync();
    }

    // 0.1 If local track was recently changed and already matches pulse track, ignore pulses of previous state
    if (_lastTrackChangeTime != null &&
        DateTime.now().difference(_lastTrackChangeTime!) < const Duration(seconds: 5) &&
        _playerController.currentTrack != null &&
        _isSameTrackId(_playerController.currentTrack?.id, action.track?.id)) {
      debugPrint('JAM: syncPulse ignored because local track change was recent.');
      return;
    }

    // 2. Verify Track Match
    if (action.track != null &&
        !_isSameTrackId(_playerController.currentTrack?.id, action.track!.id)) {
      debugPrint('JAM: Desync in track during syncPulse. Loading ${action.track!.title}');
      _setSyncStatus(JamSyncStatus.syncing);
      _lastTrackId = action.track!.id;
      _lastTrackChangeTime = DateTime.now();

      final loadStartMs = DateTime.now().millisecondsSinceEpoch;
      final qIdx = _playerController.queue.indexWhere((t) => _isSameTrackId(t.id, action.track!.id));
      if (qIdx != -1) {
        await _playerController.skipToQueueItem(qIdx);
      } else {
        // Track wasn't in our local queue: play it and ask Host for the full queue
        await _playerController.playTrack(
          action.track!,
          autoPlay: action.isPlaying ?? true,
        );
        _jamService.requestSync();
      }
      final loadElapsedMs = (DateTime.now().millisecondsSinceEpoch - loadStartMs).clamp(0, 10000);

      if (action.isPlaying == false && _playerController.isPlaying) {
        await _playerController.pause();
      }

      if ((action.positionMs ?? 0) > 3000 && _playerController.currentTrack != null) {
        final targetPos = _clampPositionToTrack(
          action.positionMs! + (action.isPlaying == true ? networkLatency + loadElapsedMs : 0),
          action.track,
        );
        await _playerController.seek(Duration(milliseconds: targetPos));
      }
      return;
    }

    // 3. Verify Play State
    if (action.isPlaying != null) {
      if (action.isPlaying! &&
          !_playerController.isPlaying &&
          !_playerController.isBuffering) {
        _lastIsPlaying = true;
        await _playerController.resume();
      } else if (!action.isPlaying! && _playerController.isPlaying) {
        _lastIsPlaying = false;
        await _playerController.pause();
      }
    }

    // 4. Drift Compensation (3000ms threshold, only after initial 6 seconds of playback)
    if (action.positionMs != null && action.isPlaying == true && _playerController.currentTrack != null) {
      final currentPos = _playerController.position.inMilliseconds;
      if (currentPos < 6000) {
        return; // Allow playback to settle smoothly without seeking in early seconds
      }

      final expectedPos = _clampPositionToTrack(
        action.positionMs! + networkLatency,
        action.track,
      );
      final drift = (currentPos - expectedPos).abs();

      if (drift > 3000) {
        debugPrint('JAM: Significant drift detected (${drift}ms). Seeking to $expectedPos ms...');
        _setSyncStatus(JamSyncStatus.syncing);
        await _playerController.seek(Duration(milliseconds: expectedPos));
        _setSyncStatus(JamSyncStatus.synced);
      }
    }
  }

  void _broadcastAction(JamAction action) {
    _jamService.broadcastAction(action).catchError((e) {
      debugPrint('Error broadcasting Jam action: $e');
      return false;
    });
  }

  String? _findParticipantName(String userId) {
    try {
      return _participants.firstWhere((p) => p.id == userId).username;
    } catch (_) {
      return null;
    }
  }

  String get _currentUserId => _jamService.myUserId;

  void _sendFullSyncState(String targetId) {
    final isIdle = _playerController.currentTrack == null && _playerController.queue.isEmpty;
    if (isIdle && targetId == 'all') return;
    debugPrint('JAM: Sending full sync state to $targetId');

    final currentQueue = _playerController.queue;
    final currentTrack = _playerController.currentTrack ?? (currentQueue.isNotEmpty ? currentQueue.first : null);
    int queueIndex = 0;
    if (currentTrack != null && currentQueue.isNotEmpty) {
      queueIndex = currentQueue.indexWhere((t) => _isSameTrackId(t.id, currentTrack.id));
      if (queueIndex < 0) queueIndex = 0;
    }

    final action = JamAction(
      id: _nextActionId(),
      type: JamActionType.syncState,
      track: currentTrack,
      positionMs: _playerController.position.inMilliseconds,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isPlaying: _playerController.isPlaying,
      queue: currentQueue.isNotEmpty
          ? currentQueue
          : (currentTrack != null ? [currentTrack] : null),
      queueIndex: queueIndex,
      senderId: _currentUserId,
    );

    if (targetId == 'all') {
      _broadcastAction(action);
    } else {
      _jamService.sendActionTo(targetId, action).catchError((e) {
        debugPrint('Error sending Jam sync action to $targetId: $e');
        return false;
      });
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopHeartbeat();
    _initialSyncTimer?.cancel();
    _initialSyncTimer = null;
    _hostFailoverTimer?.cancel();
    _hostFailoverTimer = null;
    _playerController.removeListener(_onPlayerStateChanged);
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _jamService.dispose();
    super.dispose();
  }
}
