import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
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
    return JamAction(
      id: payload['id'] as String? ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
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
      senderId: payload['sender_id'] as String? ?? '',
    );
  }
}

/// Handles communication for Jam sessions using Supabase Realtime Broadcast.
class JamService {
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  String? _currentCode;
  
  bool isHost = false;
  late final String myUserId;

  final _actionController = StreamController<JamAction>.broadcast();
  final _participantsController = StreamController<List<JamParticipant>>.broadcast();
  final _connectionReadyController = StreamController<String>.broadcast();

  /// Stream of incoming actions from other participants.
  Stream<JamAction> get onAction => _actionController.stream;

  /// Stream of current participants in the Jam.
  Stream<List<JamParticipant>> get participantsStream => _participantsController.stream;

  /// Stream emitted when a specific participant is ready to receive sync actions.
  Stream<String> get onConnectionReady => _connectionReadyController.stream;

  /// The current Jam code, or null if not in a Jam.
  String? get currentCode => _currentCode;

  /// Whether we are currently in a Jam session.
  bool get isInJam => _channel != null && _currentCode != null;

  JamService(this._supabase) {
    final authId = _supabase.auth.currentUser?.id ?? 'anon';
    final deviceSuffix = Random.secure().nextInt(9999999).toString();
    myUserId = '${authId}_$deviceSuffix';
  }

  /// Creates a new Jam session con a random 6-character code.
  Future<String> createJam() async {
    isHost = true;
    final code = _generateCode();
    await _subscribeToChannel(code);
    return code;
  }

  /// Joins an existing Jam session by its code.
  Future<void> joinJam(String code) async {
    isHost = false;
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.length != 6) {
      throw ArgumentError('JAM code must be 6 characters');
    }
    await _subscribeToChannel(normalizedCode);
  }

  /// Leaves the current Jam session and cleans up resources.
  Future<void> leaveJam() async {
    if (_channel != null) {
      await _supabase.removeChannel(_channel!);
      _channel = null;
    }
    _currentCode = null;
    _knownParticipants.clear();
    _processedMessageIds.clear();
    _participantsController.add([]);
  }

  /// Requests state synchronization from the Jam host.
  Future<void> requestSync() async {
    await sendActionTo(
      'host',
      JamAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        type: JamActionType.requestSync,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        senderId: myUserId,
      ),
    );
  }

  /// Broadcasts an action to all participants via Supabase Broadcast.
  Future<void> broadcastAction(JamAction action) async {
    if (_channel == null) return;
    
    await _channel!.sendBroadcastMessage(
      event: 'jam_action',
      payload: {
        'target_id': 'all',
        'action': action.toPayload(),
      },
    );
  }

  /// Sends an action to a specific participant via Supabase Broadcast.
  Future<void> sendActionTo(String targetId, JamAction action) async {
    if (_channel == null) return;

    await _channel!.sendBroadcastMessage(
      event: 'jam_action',
      payload: {
        'target_id': targetId,
        'action': action.toPayload(),
      },
    );
  }

  /// Disposes all resources. Call when the service is no longer needed.
  void dispose() {
    leaveJam();
    _actionController.close();
    _participantsController.close();
    _connectionReadyController.close();
  }

  // --- Private ---

  Future<void> _subscribeToChannel(String code) async {
    if (isInJam) await leaveJam();

    _currentCode = code;
    final channelName = 'jam:$code';

    final user = _supabase.auth.currentUser;
    final metadata = user?.userMetadata;
    final username = metadata?['full_name'] as String? ?? user?.email?.split('@')[0] ?? 'Guest';

    _channel = _supabase.channel(
      channelName,
      opts: const RealtimeChannelConfig(self: false), // Disabled self to prevent natural echo loops
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
          if (_processedMessageIds.length > 100) {
            _processedMessageIds.remove(_processedMessageIds.first);
          }
          
          // Ignore our own actions
          if (action.senderId != myUserId) {
            _actionController.add(action);
          }
        } catch (e) {
          debugPrint('Error parsing jam_action payload: $e');
        }
      },
    );

    _channel!.onPresenceSync((_) => _updateParticipants());
    _channel!.onPresenceJoin((_) => _updateParticipants());
    _channel!.onPresenceLeave((_) => _updateParticipants());

    _channel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.track({
          'user_id': myUserId,
          'username': username,
          'is_host': isHost,
          'joined_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  /// Updates the presence state when host status changes.
  Future<void> updateHostPresence(bool newIsHost) async {
    isHost = newIsHost;
    if (_channel != null) {
      final user = _supabase.auth.currentUser;
      final metadata = user?.userMetadata;
      final username = metadata?['full_name'] as String? ??
          user?.email?.split('@')[0] ??
          'Guest';
      await _channel!.track({
        'user_id': myUserId,
        'username': username,
        'is_host': isHost,
        'joined_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  final Set<String> _knownParticipants = {};
  final Set<String> _processedMessageIds = {};

  void _updateParticipants() {
    if (_channel == null) return;

    final presences = _channel!.presenceState();
    final participants = <JamParticipant>[];
    
    for (final state in presences) {
      for (final presence in state.presences) {
        try {
          final p = JamParticipant.fromPresence(presence.payload);
          participants.add(p);
          
          // If I am the Host, and I see a new Guest, notify that they are ready to receive sync state
          if (isHost && p.id != myUserId && !_knownParticipants.contains(p.id)) {
            _knownParticipants.add(p.id);
            debugPrint('JAM_SERVICE: Host detected new Guest (${p.id}). Emitting connection ready...');
            // Since we are using Supabase Broadcast, they are ready immediately!
            _connectionReadyController.add(p.id);
          }
        } catch (e) {
          debugPrint('Error parsing presence: $e');
        }
      }
    }

    // Remove people who left from _knownParticipants
    final currentIds = participants.map((p) => p.id).toSet();
    _knownParticipants.removeWhere((id) => !currentIds.contains(id));

    _participantsController.add(participants);
    debugPrint('JAM_SERVICE: Participants updated. Count: ${participants.length}');
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
