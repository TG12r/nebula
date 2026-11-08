import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

/// Supported actions that can be broadcast across a Jam session.
enum JamActionType {
  playTrack,
  pause,
  resume,
  skipNext,
  skipPrev,
  addToQueue,
  removeFromQueue,
  clearQueue,
  setQueue,
  seek,
  requestSync,
  syncState,
  syncPulse,
}

/// A single action broadcast across the Jam channel.
class JamAction {
  final String id;
  final JamActionType type;
  final Track? track;
  final int? positionMs;
  final int? timestampMs;
  final bool? isPlaying;
  final List<Track>? queue;
  final int? queueIndex;
  final String senderId;

  const JamAction({
    required this.id,
    required this.type,
    this.track,
    this.positionMs,
    this.timestampMs,
    this.isPlaying,
    this.queue,
    this.queueIndex,
    required this.senderId,
  });

  Map<String, dynamic> toPayload() {
    return {
      'id': id,
      'action_type': type.name,
      if (track != null) 'track': track!.toMap(),
      if (positionMs != null) 'position_ms': positionMs,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (isPlaying != null) 'is_playing': isPlaying,
      if (queue != null) 'queue': queue!.map((t) => t.toMap()).toList(),
      if (queueIndex != null) 'queue_index': queueIndex,
      'sender_id': senderId,
    };
  }

  factory JamAction.fromPayload(Map<String, dynamic> payload) {
    final sender = payload['sender_id'] as String? ?? '';
    return JamAction(
      id: payload['id'] as String? ??
          '${sender}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}',
      type: JamActionType.values.byName(payload['action_type'] as String),
      track: payload['track'] != null
          ? Track.fromMap(Map<String, dynamic>.from(payload['track'] as Map))
          : null,
      positionMs: payload['position_ms'] as int?,
      timestampMs: payload['timestamp_ms'] as int?,
      isPlaying: payload['is_playing'] as bool?,
      queue: payload['queue'] != null
          ? (payload['queue'] as List)
              .map((item) =>
                  Track.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList()
          : null,
      queueIndex: payload['queue_index'] as int?,
      senderId: sender,
    );
  }
}

/// Exception thrown when attempting to join a Jam room code that has no active participants.
class JamSessionNotFoundException implements Exception {
  final String code;
  const JamSessionNotFoundException(this.code);

  String get message => 'JAM SESSION "$code" NOT FOUND OR INACTIVE';

  @override
  String toString() => message;
}

class _JamLifecycleObserver with WidgetsBindingObserver {
  final void Function(Duration pausedDuration) onResumedFromBackground;
  DateTime? _pausedAt;

  _JamLifecycleObserver(this.onResumedFromBackground);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final elapsed = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      onResumedFromBackground(elapsed);
    }
  }
}

/// Handles communication for Jam sessions using Supabase Realtime Broadcast & Presence.
class JamService {
  final SupabaseClient _supabase;
  final NebulaAudioHandler? _audioHandler;
  final Duration _presenceLeaveGracePeriod;

  RealtimeChannel? _channel;
  String? _currentCode;

  bool isHost = false;
  late String myUserId;
  int _joinedAt = 0;
  int _actionSeq = 0;

  final _actionController = StreamController<JamAction>.broadcast();
  final _participantsController =
      StreamController<List<JamParticipant>>.broadcast();
  final _connectionReadyController = StreamController<String>.broadcast();
  final _reconnectedController = StreamController<void>.broadcast();

  Completer<void>? _peerDetectedCompleter;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  _JamLifecycleObserver? _lifecycleObserver;
  bool _batteryExemptionRequested = false;

  /// Stream of incoming actions from other participants.
  Stream<JamAction> get onAction => _actionController.stream;

  /// Stream of current participants in the Jam.
  Stream<List<JamParticipant>> get participantsStream =>
      _participantsController.stream;

  /// Stream emitted when a specific participant is ready to receive sync actions.
  Stream<String> get onConnectionReady => _connectionReadyController.stream;

  /// Stream emitted when the channel reconnects after a temporary disconnect or background sleep.
  Stream<void> get onReconnected => _reconnectedController.stream;

  /// The current Jam code, or null if not in a Jam.
  String? get currentCode => _currentCode;

  /// Whether we are currently in a Jam session.
  bool get isInJam => _channel != null && _currentCode != null;

  bool _isSubscribed = false;
  bool _wasEverSubscribed = false;

  /// Whether the realtime channel is connected and subscribed.
  bool get isSubscribed => _channel != null && _isSubscribed;

  JamService(
    this._supabase, {
    NebulaAudioHandler? audioHandler,
    Duration presenceLeaveGracePeriod = const Duration(seconds: 6),
  }) : _audioHandler = audioHandler,
       _presenceLeaveGracePeriod = presenceLeaveGracePeriod {
    _refreshUserId();
    _tryRegisterLifecycleObserver();
  }

  void _tryRegisterLifecycleObserver() {
    try {
      final observer = _JamLifecycleObserver(_onAppResumed);
      WidgetsBinding.instance.addObserver(observer);
      _lifecycleObserver = observer;
    } catch (_) {
      // Running in non-widget test context
    }
  }

  void _onAppResumed(Duration pausedDuration) {
    if (!isInJam) return;

    debugPrint(
      'JAM_SERVICE: App resumed after ${pausedDuration.inSeconds}s in background. Verifying Jam channel health...',
    );
    if (!_isSubscribed) {
      _scheduleReconnect(immediate: true);
    } else {
      unawaited(_trackPresence());
      // Only trigger full state resync if the app was truly backgrounded for >= 3s
      if (pausedDuration >= const Duration(seconds: 3) &&
          !_reconnectedController.isClosed) {
        _reconnectedController.add(null);
      }
    }
  }

  void _refreshUserId() {
    final authId = _supabase.auth.currentUser?.id ?? 'anon';
    final deviceSuffix = Random.secure().nextInt(9999999).toString();
    myUserId = '${authId}_$deviceSuffix';
  }

  /// Generates a collision-free action ID scoped to this client session.
  String nextActionId([String prefix = 'act']) {
    return '${prefix}_${myUserId}_${DateTime.now().microsecondsSinceEpoch}_${++_actionSeq}';
  }

  /// Creates a new Jam session with a random 6-character code.
  Future<String> createJam() async {
    isHost = true;
    _refreshUserIdIfNeeded();
    _joinedAt = DateTime.now().millisecondsSinceEpoch;
    final code = _generateCode();
    await _subscribeToChannel(code);
    _activateBackgroundSupport(code);
    return code;
  }

  /// Joins an existing Jam session by its code.
  /// If [verifyRoomExists] is true, waits up to [roomCheckTimeout] to confirm at least one peer is present.
  Future<void> joinJam(
    String code, {
    bool verifyRoomExists = true,
    Duration roomCheckTimeout = const Duration(milliseconds: 2500),
  }) async {
    isHost = false;
    _refreshUserIdIfNeeded();
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.length != 6) {
      throw ArgumentError('JAM code must be 6 characters');
    }
    _joinedAt = DateTime.now().millisecondsSinceEpoch;
    _peerDetectedCompleter = Completer<void>();

    await _subscribeToChannel(normalizedCode);

    if (verifyRoomExists) {
      // Also fire an immediate sync request so the Host can reply via Broadcast
      // even before Presence state finishes converging.
      unawaited(requestSync());
      try {
        await _peerDetectedCompleter!.future.timeout(roomCheckTimeout);
      } on TimeoutException {
        debugPrint(
          'JAM_SERVICE: No active peers found in Jam $normalizedCode. Leaving ghost channel.',
        );
        await leaveJam();
        throw JamSessionNotFoundException(normalizedCode);
      } finally {
        _peerDetectedCompleter = null;
      }
    } else {
      _peerDetectedCompleter = null;
    }

    _activateBackgroundSupport(normalizedCode);
  }

  void _activateBackgroundSupport(String code) {
    _audioHandler?.setJamSessionActive(true, jamCode: code);
    _startKeepAliveTimer();
    unawaited(_requestAndroidBackgroundExemption());
  }

  Future<void> _requestAndroidBackgroundExemption() async {
    if (_batteryExemptionRequested) return;
    try {
      if (Platform.isAndroid) {
        _batteryExemptionRequested = true;
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } catch (e) {
      debugPrint('JAM_SERVICE: Battery optimization request skipped: $e');
    }
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isInJam) {
        _keepAliveTimer?.cancel();
        _keepAliveTimer = null;
        return;
      }
      if (_isSubscribed) {
        // Periodic presence heartbeat keeps both Host and Guest sockets active
        // across mobile NATs and background Wi-Fi power saving.
        unawaited(_trackPresence());
      } else if (!_isReconnecting) {
        _scheduleReconnect(immediate: true);
      }
    });
  }

  void _refreshUserIdIfNeeded() {
    final currentAuth = _supabase.auth.currentUser?.id;
    if (currentAuth != null && !myUserId.startsWith('${currentAuth}_')) {
      final deviceSuffix = Random.secure().nextInt(9999999).toString();
      myUserId = '${currentAuth}_$deviceSuffix';
    } else if (currentAuth == null && !myUserId.startsWith('anon_')) {
      final deviceSuffix = Random.secure().nextInt(9999999).toString();
      myUserId = 'anon_$deviceSuffix';
    }
  }

  /// Leaves the current Jam session and cleans up resources.
  Future<void> leaveJam() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;

    for (final timer in _pendingLeaveTimers.values) {
      timer.cancel();
    }
    _pendingLeaveTimers.clear();
    _lastSeenParticipants.clear();

    final channelToLeave = _channel;
    final wasSub = _isSubscribed;
    _isSubscribed = false;
    _wasEverSubscribed = false;
    _joinedAt = 0;
    _peerDetectedCompleter = null;
    _channel = null;
    _currentCode = null;
    _knownParticipants.clear();
    _processedMessageIds.clear();

    _audioHandler?.setJamSessionActive(false);

    if (channelToLeave != null) {
      if (wasSub) {
        try {
          await channelToLeave
              .sendBroadcastMessage(
                event: 'jam_leave',
                payload: {'user_id': myUserId},
              )
              .timeout(const Duration(milliseconds: 500));
          await channelToLeave.untrack().timeout(
            const Duration(milliseconds: 500),
          );
        } catch (_) {}
      }
      try {
        await _supabase.removeChannel(channelToLeave);
      } catch (_) {}
    }

    if (!_participantsController.isClosed) {
      _participantsController.add([]);
    }
  }

  /// Requests state synchronization from the Jam host.
  Future<void> requestSync() async {
    await sendActionTo(
      'host',
      JamAction(
        id: nextActionId(),
        type: JamActionType.requestSync,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: myUserId,
      ),
    );
  }

  /// Waits until the channel is in subscribed state or timeout expires.
  Future<bool> _ensureSubscribed({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_channel == null) return false;
    if (_isSubscribed) return true;

    final start = DateTime.now();
    while (!_isSubscribed && _channel != null) {
      if (DateTime.now().difference(start) > timeout) {
        debugPrint(
          'JAM_SERVICE: Timed out waiting for channel to be subscribed.',
        );
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return _isSubscribed;
  }

  /// Broadcasts an action to all participants via Supabase Broadcast with automatic retry.
  Future<bool> broadcastAction(JamAction action, {int maxRetries = 3}) async {
    if (_channel == null) return false;

    final ready = await _ensureSubscribed();
    if (!ready || _channel == null) {
      debugPrint(
        'JAM_SERVICE: broadcastAction (${action.type.name}) skipped: channel not subscribed.',
      );
      return false;
    }

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final status = await _channel!.sendBroadcastMessage(
          event: 'jam_action',
          payload: {
            'target_id': 'all',
            'action': action.toPayload(),
          },
        );

        if (status == ChannelResponse.ok) {
          debugPrint(
            'JAM_SERVICE: broadcastAction ${action.type.name} delivered successfully.',
          );
          return true;
        }

        debugPrint(
          'JAM_SERVICE: broadcastAction ${action.type.name} returned $status (attempt $attempt/$maxRetries)',
        );
      } catch (e) {
        debugPrint('JAM_SERVICE: Error in broadcastAction attempt $attempt: $e');
      }

      if (attempt < maxRetries) {
        await Future.delayed(
          Duration(milliseconds: 150 * pow(2, attempt - 1).toInt()),
        );
      }
    }

    debugPrint(
      'JAM_SERVICE: Failed to broadcast action ${action.type.name} after $maxRetries attempts.',
    );
    return false;
  }

  /// Sends an action to a specific participant via Supabase Broadcast with automatic retry.
  Future<bool> sendActionTo(
    String targetId,
    JamAction action, {
    int maxRetries = 3,
  }) async {
    if (_channel == null) return false;

    final ready = await _ensureSubscribed();
    if (!ready || _channel == null) {
      debugPrint(
        'JAM_SERVICE: sendActionTo ($targetId) skipped: channel not subscribed.',
      );
      return false;
    }

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final status = await _channel!.sendBroadcastMessage(
          event: 'jam_action',
          payload: {
            'target_id': targetId,
            'action': action.toPayload(),
          },
        );

        if (status == ChannelResponse.ok) {
          debugPrint(
            'JAM_SERVICE: sendActionTo ($targetId) ${action.type.name} delivered successfully.',
          );
          return true;
        }

        debugPrint(
          'JAM_SERVICE: sendActionTo ($targetId) ${action.type.name} returned $status (attempt $attempt/$maxRetries)',
        );
      } catch (e) {
        debugPrint('JAM_SERVICE: Error in sendActionTo attempt $attempt: $e');
      }

      if (attempt < maxRetries) {
        await Future.delayed(
          Duration(milliseconds: 150 * pow(2, attempt - 1).toInt()),
        );
      }
    }

    debugPrint(
      'JAM_SERVICE: Failed sendActionTo ($targetId) ${action.type.name} after $maxRetries attempts.',
    );
    return false;
  }

  /// Disposes all resources. Call when the service is no longer needed.
  void dispose() {
    if (_lifecycleObserver != null) {
      try {
        WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      } catch (_) {}
      _lifecycleObserver = null;
    }
    leaveJam();
    _actionController.close();
    _participantsController.close();
    _connectionReadyController.close();
    _reconnectedController.close();
  }

  // --- Private ---

  String _currentUsername() {
    final user = _supabase.auth.currentUser;
    final metadata = user?.userMetadata;
    return metadata?['full_name'] as String? ??
        user?.email?.split('@')[0] ??
        'Guest';
  }

  Future<void> _trackPresence() async {
    if (_channel == null || !_isSubscribed) return;
    try {
      await _channel!.track({
        'user_id': myUserId,
        'username': _currentUsername(),
        'is_host': isHost,
        'joined_at':
            _joinedAt > 0 ? _joinedAt : DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('JAM_SERVICE: Error tracking presence: $e');
    }
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_currentCode == null || _isReconnecting) return;
    _reconnectTimer?.cancel();
    final delay = immediate
        ? Duration.zero
        : const Duration(milliseconds: 1500);
    _reconnectTimer = Timer(delay, () async {
      final code = _currentCode;
      if (code == null || _isSubscribed || _isReconnecting) return;
      _isReconnecting = true;
      debugPrint('JAM_SERVICE: Attempting automatic channel reconnect to $code...');
      try {
        await _subscribeToChannel(code, isReconnectAttempt: true);
      } catch (e) {
        debugPrint('JAM_SERVICE: Reconnect attempt failed: $e');
      } finally {
        _isReconnecting = false;
      }
    });
  }

  Future<void> _subscribeToChannel(
    String code, {
    bool isReconnectAttempt = false,
  }) async {
    if (!isReconnectAttempt && isInJam) {
      await leaveJam();
    } else if (isReconnectAttempt && _channel != null) {
      try {
        await _supabase.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }

    _currentCode = code;
    if (_joinedAt == 0) {
      _joinedAt = DateTime.now().millisecondsSinceEpoch;
    }
    final channelName = 'jam:$code';

    _channel = _supabase.channel(
      channelName,
      opts: RealtimeChannelConfig(
        self: false, // Disabled self to prevent natural echo loops
        key: myUserId, // Fixed presence key per device to prevent ghost duplicate presences
      ),
    );

    // Listen for Jam Actions via Broadcast
    _channel!.onBroadcast(
      event: 'jam_action',
      callback: (payload) {
        try {
          final data = Map<String, dynamic>.from(payload);
          final targetId = data['target_id'] as String?;

          // Ignore if not meant for everyone, not meant for me, and not targeted to host when I am host
          if (targetId != 'all' &&
              targetId != myUserId &&
              !(targetId == 'host' && isHost)) {
            return;
          }

          final actionPayload = Map<String, dynamic>.from(data['action']);
          final action = JamAction.fromPayload(actionPayload);

          // Ignore if we already processed this exact message (idempotency)
          if (_processedMessageIds.contains(action.id)) {
            return;
          }
          _processedMessageIds.add(action.id);

          // Keep set small
          if (_processedMessageIds.length > 200) {
            _processedMessageIds.remove(_processedMessageIds.first);
          }

          // Ignore our own actions
          if (action.senderId != myUserId) {
            // Receiving an action proves this peer is still active: cancel any pending leave timer!
            _pendingLeaveTimers.remove(action.senderId)?.cancel();

            if (_peerDetectedCompleter != null &&
                !_peerDetectedCompleter!.isCompleted) {
              _peerDetectedCompleter!.complete();
            }
            _actionController.add(action);
          }
        } catch (e) {
          debugPrint('Error parsing jam_action payload: $e');
        }
      },
    );

    // Listen for explicit graceful leave events so intentional exits update in 0ms
    _channel!.onBroadcast(
      event: 'jam_leave',
      callback: (payload) {
        try {
          final leavingId = payload['user_id'] as String?;
          if (leavingId != null && leavingId.isNotEmpty) {
            _pendingLeaveTimers.remove(leavingId)?.cancel();
            _lastSeenParticipants.remove(leavingId);
            _knownParticipants.remove(leavingId);
            _updateParticipants();
          }
        } catch (_) {}
      },
    );

    _channel!.onPresenceSync((_) => _updateParticipants());
    _channel!.onPresenceJoin((_) => _updateParticipants());
    _channel!.onPresenceLeave((_) => _updateParticipants());

    final completer = Completer<void>();

    _channel!.subscribe((status, [error]) async {
      debugPrint(
        'JAM_SERVICE: Channel subscription status: $status, error: $error',
      );
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          final isReconnection =
              isReconnectAttempt || (!_isSubscribed && _wasEverSubscribed);
          _isSubscribed = true;
          _wasEverSubscribed = true;

          await _trackPresence();

          if (!completer.isCompleted) {
            completer.complete();
          }

          if (isReconnection && !_reconnectedController.isClosed) {
            debugPrint(
              'JAM_SERVICE: Channel reconnected! Emitting onReconnected event.',
            );
            _reconnectedController.add(null);
          }
          break;

        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _isSubscribed = false;
          if (!completer.isCompleted) {
            completer.completeError(
              error ?? Exception('Failed to subscribe to channel: $status'),
            );
          } else if (_currentCode != null) {
            // Channel dropped after initial subscription (e.g. mobile network switch or background doze):
            // schedule automatic reconnection without dropping the Jam session!
            _scheduleReconnect();
          }
          break;
      }
    });

    try {
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Timed out connecting to Jam channel $code');
        },
      );
    } catch (e) {
      debugPrint('JAM_SERVICE: Connection failed or timed out: $e');
      if (!isReconnectAttempt) {
        await leaveJam();
      }
      rethrow;
    }
  }

  /// Updates the presence state when host status changes, preserving original join timestamp.
  Future<void> updateHostPresence(bool newIsHost) async {
    isHost = newIsHost;
    if (_channel != null && _isSubscribed) {
      if (newIsHost) {
        // Seed existing participants so promotion doesn't re-fire onConnectionReady for existing peers
        for (final state in _channel!.presenceState()) {
          for (final presence in state.presences) {
            try {
              final p = JamParticipant.fromPresence(presence.payload);
              if (p.id.isNotEmpty && p.id != myUserId) {
                _knownParticipants.add(p.id);
              }
            } catch (_) {}
          }
        }
      }

      await _trackPresence();
    }
  }

  final Set<String> _knownParticipants = {};
  final Set<String> _processedMessageIds = {};
  final Map<String, JamParticipant> _lastSeenParticipants = {};
  final Map<String, Timer> _pendingLeaveTimers = {};

  void _updateParticipants() {
    if (_channel == null) return;

    final presences = _channel!.presenceState();
    final Map<String, JamParticipant> deduplicated = {};

    for (final state in presences) {
      for (final presence in state.presences) {
        try {
          final p = JamParticipant.fromPresence(presence.payload);
          if (p.id.isEmpty) continue;

          // Keep latest presence entry per user_id (preferring earliest non-zero joinedAt)
          final existing = deduplicated[p.id];
          if (existing == null) {
            deduplicated[p.id] = p;
          } else {
            final earliestJoin = (existing.joinedAt > 0 && p.joinedAt > 0)
                ? min(existing.joinedAt, p.joinedAt)
                : (existing.joinedAt > 0 ? existing.joinedAt : p.joinedAt);
            deduplicated[p.id] = JamParticipant(
              id: p.id,
              username: p.username,
              isHost: p.isHost,
              joinedAt: earliestJoin,
            );
          }

          if (p.id != myUserId &&
              _peerDetectedCompleter != null &&
              !_peerDetectedCompleter!.isCompleted) {
            _peerDetectedCompleter!.complete();
          }

          // Participant is actively present: cancel any pending disconnect grace timer
          _pendingLeaveTimers.remove(p.id)?.cancel();
          _lastSeenParticipants[p.id] = deduplicated[p.id]!;

          // If I am the Host, and I see a new Guest, notify that they are ready to receive sync state
          if (isHost && p.id != myUserId && !_knownParticipants.contains(p.id)) {
            _knownParticipants.add(p.id);
            debugPrint(
              'JAM_SERVICE: Host detected new Guest (${p.id}). Emitting connection ready...',
            );
            _connectionReadyController.add(p.id);
          }
        } catch (e) {
          debugPrint('Error parsing presence: $e');
        }
      }
    }

    // Apply grace period for peers that momentarily disappeared from presenceState()
    // due to mobile app-switching (e.g. WhatsApp) or brief Wi-Fi/cellular socket handoffs.
    if (_presenceLeaveGracePeriod > Duration.zero) {
      for (final entry in _lastSeenParticipants.entries.toList()) {
        final peerId = entry.key;
        if (peerId == myUserId) continue;
        if (!deduplicated.containsKey(peerId)) {
          // Retain peer during grace window so UI and Host role don't flicker
          deduplicated[peerId] = entry.value;
          _pendingLeaveTimers.putIfAbsent(peerId, () {
            debugPrint(
              'JAM_SERVICE: Peer $peerId missing from presence; starting ${_presenceLeaveGracePeriod.inSeconds}s grace timer...',
            );
            return Timer(_presenceLeaveGracePeriod, () {
              _pendingLeaveTimers.remove(peerId);
              _lastSeenParticipants.remove(peerId);
              _knownParticipants.remove(peerId);
              debugPrint(
                'JAM_SERVICE: Peer $peerId grace period expired; marking as disconnected.',
              );
              _updateParticipants();
            });
          });
        }
      }
    } else {
      final currentIds = deduplicated.keys.toSet();
      _lastSeenParticipants.removeWhere((id, _) => !currentIds.contains(id));
      _knownParticipants.removeWhere((id) => !currentIds.contains(id));
    }

    final participants = deduplicated.values.toList()
      ..sort((a, b) {
        final cmp = a.joinedAt.compareTo(b.joinedAt);
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });

    if (!_participantsController.isClosed) {
      _participantsController.add(participants);
    }
    debugPrint(
      'JAM_SERVICE: Participants updated. Count: ${participants.length}',
    );
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
