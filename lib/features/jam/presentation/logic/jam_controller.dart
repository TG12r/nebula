import 'dart:async';
import 'dart:math';

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
/// - Anti-echo guard to prevent infinite broadcast loops.
/// - Network latency and loading time compensation using timestamps.
/// - Continuous periodic heartbeat (syncPulse) by the Host with 1200ms drift threshold.
/// - Complete queue and playlist synchronization across all devices.
/// - Automatic host migration if the current host disconnects.
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

  // Guard to prevent echo loops when applying remote actions
  bool _isApplyingRemoteAction = false;
  bool _isProcessingAction = false;
  final List<JamAction> _actionQueue = [];
  bool _hasReceivedInitialSync = false;

  // Active sync timer for guests to guarantee initial state arrival
  Timer? _initialSyncTimer;
  int _syncRequestAttempts = 0;

  // Heartbeat timer for host drift correction
  Timer? _heartbeatTimer;
  int _pulseCounter = 0;

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

  JamController(this._jamService, this._playerController, [String? userId]) {
    _initStreams();
  }

  void _initStreams() {
    // Listen for remote Jam actions
    _subscriptions.add(
      _jamService.onAction.listen(_handleRemoteAction),
    );

    // Listen for participant changes & handle host failover
    _subscriptions.add(
      _jamService.participantsStream.listen((participants) {
        _participants = participants;

        // Auto host failover: If no host exists, oldest participant becomes Host
        if (_isInJam && participants.isNotEmpty) {
          final hasHost = participants.any((p) => p.isHost);
          if (!hasHost) {
            final sorted = List<JamParticipant>.from(participants)
              ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
            final oldest = sorted.first;

            if (oldest.id == _currentUserId && !_isHost) {
              debugPrint('JAM: Host left. Promoting self ($_currentUserId) to Host.');
              _isHost = true;
              _jamService.updateHostPresence(true);
              _startHeartbeat();
              _sendFullSyncState('all');
            }
          }
        }

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
          if (_isHost) {
            _sendFullSyncState('all');
          } else {
            _jamService.requestSync();
          }
        }
      }),
    );

    // Listen to PlayerController state changes
    _playerController.addListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() {
    // CRITICAL: If applying a remote action, suppress broadcast to eliminate echo loops!
    if (!_isInJam || _isApplyingRemoteAction) return;

    if (_playerController.isBuffering) {
      _setSyncStatus(JamSyncStatus.buffering);
    } else if (_syncStatus == JamSyncStatus.buffering) {
      _setSyncStatus(JamSyncStatus.synced);
    }

    // ONLY the Host broadcasts natural, unprompted player state changes
    // (such as when a track naturally finishes and advances to the next track)
    if (!_isHost) return;

    final currentTrack = _playerController.currentTrack;
    final isPlaying = _playerController.isPlaying;

    bool trackChanged = false;
    bool playStateChanged = false;

    if (currentTrack?.id != _lastTrackId) {
      trackChanged = true;
      _lastTrackId = currentTrack?.id;
      _lastIsPlaying = isPlaying;
    } else if (isPlaying != _lastIsPlaying) {
      playStateChanged = true;
      _lastIsPlaying = isPlaying;
    }

    if (trackChanged && currentTrack != null) {
      debugPrint('JAM: Host track changed naturally. Broadcasting new track: ${currentTrack.title}');
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.playTrack,
        track: currentTrack,
        positionMs: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: isPlaying,
        senderId: _currentUserId,
      ));
    } else if (playStateChanged) {
      debugPrint('JAM: Host play state changed naturally ($isPlaying). Broadcasting.');
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    _jamCode = code;
    _startHeartbeat();
    notifyListeners();
    return code;
  }

  /// Joins an existing Jam session by code.
  Future<void> joinJam(String code) async {
    _hasReceivedInitialSync = false;
    await _jamService.joinJam(code);
    _isInJam = true;
    _isHost = false;
    _jamCode = code.trim().toUpperCase();
    _stopHeartbeat();
    notifyListeners();

    // Active handshake: Proactively request sync every 1200ms until initial state arrives (up to 5 attempts)
    _initialSyncTimer?.cancel();
    _syncRequestAttempts = 0;
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
    _syncRequestAttempts = 0;
    await _jamService.leaveJam();
    _isInJam = false;
    _isHost = false;
    _jamCode = null;
    _participants = [];
    _lastActionBy = null;
    _hasReceivedInitialSync = false;
    _actionQueue.clear();
    _isProcessingAction = false;
    _syncStatus = JamSyncStatus.synced;
    notifyListeners();
  }

  // --- Jam-Aware Player Actions ---

  /// Play a specific track, broadcasting to all peers if active.
  Future<void> playTrack(Track track) async {
    await _playerController.playTrack(track);

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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

    await _playerController.playPlaylist(
      listToPlay,
      initialIndex: targetIndex,
      shuffle: false,
    );

    if (_isInJam && listToPlay.isNotEmpty) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    final success = await _playerController.playMix(query);
    if (success && _isInJam && _playerController.queue.isNotEmpty) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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

  /// Pause playback, broadcasting exact position and timestamp.
  Future<void> pause() async {
    final pos = _playerController.position.inMilliseconds;
    await _playerController.pause();

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    await _playerController.resume();

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    await _playerController.skipToNext();

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.skipNext,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Skip to previous track.
  Future<void> skipToPrevious() async {
    await _playerController.skipToPrevious();

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.skipPrev,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Add a track to the queue, broadcasting to all peers.
  Future<void> addToQueue(Track track) async {
    await _playerController.addToQueue(track);

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.addToQueue,
        track: track,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Remove a track from the queue by index.
  Future<void> removeFromQueue(int index) async {
    await _playerController.removeFromQueue(index);

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.removeFromQueue,
        queueIndex: index,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: _currentUserId,
      ));
    }
  }

  /// Shuffle the queue, broadcasting the new queue order.
  Future<void> shuffleQueue() async {
    await _playerController.shuffleQueue();

    if (_isInJam && _playerController.queue.isNotEmpty) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.setQueue,
        track: _playerController.currentTrack,
        queue: _playerController.queue,
        queueIndex: 0,
        positionMs: _playerController.position.inMilliseconds,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isPlaying: _playerController.isPlaying,
        senderId: _currentUserId,
      ));
    }
  }

  /// Seek to position, broadcasting to all peers with timestamp.
  Future<void> seek(Duration position) async {
    await _playerController.seek(position);

    if (_isInJam) {
      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    _pulseCounter = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isHost || !_isInJam) return;
      if (_playerController.currentTrack == null && _playerController.queue.isEmpty) return;

      _pulseCounter++;
      // Every 6th pulse (30 seconds), broadcast full syncState to maintain total queue parity
      if (_pulseCounter % 6 == 0) {
        _sendFullSyncState('all');
        return;
      }

      _broadcastAction(JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
    _pulseCounter = 0;
  }

  void _setSyncStatus(JamSyncStatus status) {
    if (_syncStatus != status) {
      _syncStatus = status;
      notifyListeners();
    }
  }

  Future<void> _handleRemoteAction(JamAction action) async {
    if (action.senderId == _currentUserId) return; // Prevent self-echo

    // If currently processing a state change, drop periodic syncPulses to avoid interrupting loading
    if (_isProcessingAction && action.type == JamActionType.syncPulse) {
      return;
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

  Future<void> _executeRemoteAction(JamAction action) async {
    debugPrint('JAM: Handling remote action: ${action.type.name} from ${action.senderId}');
    _isApplyingRemoteAction = true;
    _setSyncStatus(JamSyncStatus.syncing);
    _lastActionBy = _findParticipantName(action.senderId);
    notifyListeners();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final latency = action.timestampMs != null
          ? (now - action.timestampMs!).clamp(0, 5000)
          : 0;

      switch (action.type) {
        case JamActionType.requestSync:
          if (_isHost) {
            _sendFullSyncState(action.senderId);
          }
          break;

        case JamActionType.syncState:
          await _applySyncState(action, latency);
          break;

        case JamActionType.syncPulse:
          if (!_isHost) {
            await _applySyncPulse(action, latency);
          }
          break;

        case JamActionType.playTrack:
          if (action.track != null) {
            debugPrint('JAM: Remote playTrack ${action.track!.title}');
            final targetPosition =
                (action.positionMs ?? 0) + (action.isPlaying == true ? latency : 0);
            if (_playerController.currentTrack?.id != action.track!.id) {
              await _playerController.playTrack(action.track!);
            } else if (!_playerController.isPlaying && action.isPlaying == true) {
              await _playerController.resume();
            }
            if (targetPosition > 300 && _playerController.currentTrack != null) {
              await _playerController.seek(Duration(milliseconds: targetPosition));
            }
          }
          break;

        case JamActionType.pause:
          debugPrint('JAM: Remote pause');
          await _playerController.pause();
          if (action.track != null &&
              _playerController.currentTrack?.id != action.track!.id) {
            await _playerController.playTrack(action.track!, autoPlay: false);
          }
          if (action.positionMs != null && _playerController.currentTrack != null) {
            await _playerController.seek(Duration(milliseconds: action.positionMs!));
          }
          break;

        case JamActionType.resume:
          debugPrint('JAM: Remote resume');
          final targetPosition =
              (action.positionMs ?? _playerController.position.inMilliseconds) + latency;
          if (action.track != null &&
              _playerController.currentTrack?.id != action.track!.id) {
            await _playerController.playTrack(action.track!);
          } else {
            await _playerController.resume();
          }
          if (targetPosition > 300 && _playerController.currentTrack != null) {
            await _playerController.seek(Duration(milliseconds: targetPosition));
          }
          break;

        case JamActionType.skipNext:
          await _playerController.skipToNext();
          break;

        case JamActionType.skipPrev:
          await _playerController.skipToPrevious();
          break;

        case JamActionType.setQueue:
          if (action.queue != null && action.queue!.isNotEmpty) {
            debugPrint('JAM: Remote setQueue with ${action.queue!.length} tracks');
            final initialIdx = action.queueIndex ?? 0;
            await _playerController.playPlaylist(
              action.queue!,
              initialIndex: initialIdx,
            );
            final targetPosition =
                (action.positionMs ?? 0) + (action.isPlaying == true ? latency : 0);
            if (targetPosition > 300 && _playerController.currentTrack != null) {
              await _playerController.seek(Duration(milliseconds: targetPosition));
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
          if (action.queueIndex != null) {
            debugPrint('JAM: Remote removeFromQueue at ${action.queueIndex}');
            await _playerController.removeFromQueue(action.queueIndex!);
          }
          break;

        case JamActionType.clearQueue:
          // Local clear if needed
          break;

        case JamActionType.seek:
          if (action.track != null &&
              _playerController.currentTrack?.id != action.track!.id) {
            await _playerController.playTrack(action.track!, autoPlay: action.isPlaying ?? true);
          }
          if (action.positionMs != null && _playerController.currentTrack != null) {
            final targetPosition =
                action.positionMs! + (_playerController.isPlaying ? latency : 0);
            debugPrint('JAM: Remote seek to $targetPosition ms');
            await _playerController.seek(Duration(milliseconds: targetPosition));
          }
          break;
      }
    } catch (e) {
      debugPrint('JAM: Error processing remote action ${action.type.name}: $e');
    } finally {
      // Delay releasing guard slightly to absorb any synchronous listener updates
      await Future.delayed(const Duration(milliseconds: 250));
      _isApplyingRemoteAction = false;
      _setSyncStatus(JamSyncStatus.synced);
    }
  }

  Future<void> _applySyncState(JamAction action, int latency) async {
    debugPrint('JAM: Applying full syncState. isPlaying: ${action.isPlaying}');
    _hasReceivedInitialSync = true;
    _initialSyncTimer?.cancel();
    _initialSyncTimer = null;

    final current = _playerController.currentTrack;
    final isSameTrack = action.track != null && current?.id == action.track!.id;

    if (!isSameTrack) {
      if (action.queue != null && action.queue!.isNotEmpty) {
        final initialIdx = action.queueIndex ?? 0;
        await _playerController.playPlaylist(
          action.queue!,
          initialIndex: initialIdx,
        );
      } else if (action.track != null) {
        await _playerController.playTrack(
          action.track!,
          autoPlay: action.isPlaying ?? true,
        );
      }
    }

    if (action.isPlaying == false) {
      await _playerController.pause();
    } else if (action.isPlaying == true && !_playerController.isPlaying) {
      await _playerController.resume();
    }

    if (action.positionMs != null && _playerController.currentTrack != null) {
      final targetPos =
          action.positionMs! + (action.isPlaying == true ? latency : 0);
      await _playerController.seek(Duration(milliseconds: targetPos));
    }
  }

  Future<void> _applySyncPulse(JamAction action, int latency) async {
    // 0. If local player is currently buffering or loading media, do NOT seek or disturb buffer!
    if (_playerController.isBuffering) {
      debugPrint('JAM: syncPulse ignored because player is currently buffering/loading.');
      return;
    }

    // 1. Verify Track Match
    if (action.track != null &&
        _playerController.currentTrack?.id != action.track!.id) {
      debugPrint('JAM: Desync in track during syncPulse. Loading ${action.track!.title}');
      await _playerController.playTrack(
        action.track!,
        autoPlay: action.isPlaying ?? true,
      );
    }

    // 2. Queue recovery: If guest has empty queue but host is playing, request full sync
    if ((_playerController.queue.isEmpty || !_hasReceivedInitialSync) && action.track != null) {
      debugPrint('JAM: syncPulse received but queue is empty or not initialized. Requesting full sync...');
      _jamService.requestSync();
    }

    // 3. Verify Play State
    if (action.isPlaying != null) {
      if (action.isPlaying! &&
          !_playerController.isPlaying &&
          !_playerController.isBuffering) {
        await _playerController.resume();
      } else if (!action.isPlaying! && _playerController.isPlaying) {
        await _playerController.pause();
      }
    }

    // 4. Drift Compensation with 1200ms threshold
    if (action.positionMs != null && action.isPlaying == true && _playerController.currentTrack != null) {
      final expectedPos = action.positionMs! + latency;
      final currentPos = _playerController.position.inMilliseconds;
      final drift = (currentPos - expectedPos).abs();

      if (drift > 1200) {
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
    if (_playerController.currentTrack == null && _playerController.queue.isEmpty) return;
    debugPrint('JAM: Sending full sync state to $targetId');

    final currentQueue = _playerController.queue;
    final currentTrack = _playerController.currentTrack ?? (currentQueue.isNotEmpty ? currentQueue.first : null);
    int queueIndex = 0;
    if (currentTrack != null && currentQueue.isNotEmpty) {
      queueIndex = currentQueue.indexWhere((t) => t.id == currentTrack.id);
      if (queueIndex < 0) queueIndex = 0;
    }

    final action = JamAction(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
  void dispose() {
    _stopHeartbeat();
    _initialSyncTimer?.cancel();
    _initialSyncTimer = null;
    _playerController.removeListener(_onPlayerStateChanged);
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _jamService.dispose();
    super.dispose();
  }
}
