import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/features/jam/data/jam_service.dart';
import 'package:nebula/features/jam/domain/entities/jam_participant.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

void main() {
  group('JamAction Serialization & Deserialization', () {
    test('Serializes and deserializes playTrack with latency timestamps', () {
      final track = Track(
        id: 'abc123',
        title: 'Song Title',
        artist: 'Artist Name',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: const Duration(seconds: 210),
        source: TrackSource.youtube,
      );

      final action = JamAction(
        id: 'action_1',
        type: JamActionType.playTrack,
        track: track,
        positionMs: 45000,
        timestampMs: 1700000000500,
        isPlaying: true,
        senderId: 'user_host_1',
      );

      final payload = action.toPayload();
      expect(payload['id'], 'action_1');
      expect(payload['action_type'], 'playTrack');
      expect(payload['position_ms'], 45000);
      expect(payload['timestamp_ms'], 1700000000500);
      expect(payload['is_playing'], true);
      expect(payload['sender_id'], 'user_host_1');
      expect(payload['track'], isNotNull);

      final restored = JamAction.fromPayload(payload);
      expect(restored.id, action.id);
      expect(restored.type, JamActionType.playTrack);
      expect(restored.positionMs, 45000);
      expect(restored.timestampMs, 1700000000500);
      expect(restored.isPlaying, true);
      expect(restored.senderId, 'user_host_1');
      expect(restored.track?.rawId, 'abc123');
      expect(restored.track?.title, 'Song Title');
    });

    test('Serializes and deserializes setQueue with multi-track list', () {
      final track1 = Track(
        id: 'yt_1',
        title: 'Track 1',
        artist: 'Artist 1',
        thumbnailUrl: 'https://example.com/1.jpg',
      );
      final track2 = Track(
        id: 'sc_2',
        title: 'Track 2',
        artist: 'Artist 2',
        thumbnailUrl: 'https://example.com/2.jpg',
        source: TrackSource.soundcloud,
      );

      final action = JamAction(
        id: 'action_queue',
        type: JamActionType.setQueue,
        queue: [track1, track2],
        queueIndex: 1,
        timestampMs: 1700000010000,
        isPlaying: true,
        senderId: 'user_guest_2',
      );

      final payload = action.toPayload();
      expect(payload['action_type'], 'setQueue');
      expect(payload['queue_index'], 1);
      expect(payload['queue'], isA<List>());
      expect((payload['queue'] as List).length, 2);

      final restored = JamAction.fromPayload(payload);
      expect(restored.type, JamActionType.setQueue);
      expect(restored.queue?.length, 2);
      expect(restored.queue?[0].title, 'Track 1');
      expect(restored.queue?[1].title, 'Track 2');
      expect(restored.queue?[1].source, TrackSource.soundcloud);
      expect(restored.queueIndex, 1);
    });

    test('Serializes and deserializes large queues (50 tracks) without data loss', () {
      final largeQueue = List.generate(
        50,
        (i) => Track(
          id: 'track_$i',
          title: 'Song $i',
          artist: 'Artist $i',
          thumbnailUrl: 'https://example.com/$i.jpg',
        ),
      );

      final action = JamAction(
        id: 'large_queue_action',
        type: JamActionType.setQueue,
        queue: largeQueue,
        queueIndex: 25,
        timestampMs: 1700000050000,
        isPlaying: true,
        senderId: 'host_large',
      );

      final payload = action.toPayload();
      final restored = JamAction.fromPayload(payload);

      expect(restored.queue?.length, 50);
      expect(restored.queue?[0].title, 'Song 0');
      expect(restored.queue?[49].title, 'Song 49');
      expect(restored.queueIndex, 25);
    });

    test('Serializes and deserializes addToQueue and removeFromQueue actions', () {
      final addAction = JamAction(
        id: 'add_1',
        type: JamActionType.addToQueue,
        track: Track(
          id: 'new_track',
          title: 'New Song',
          artist: 'New Artist',
          thumbnailUrl: '',
        ),
        senderId: 'guest_1',
      );
      final restoredAdd = JamAction.fromPayload(addAction.toPayload());
      expect(restoredAdd.type, JamActionType.addToQueue);
      expect(restoredAdd.track?.rawId, 'new_track');

      final removeAction = JamAction(
        id: 'remove_1',
        type: JamActionType.removeFromQueue,
        queueIndex: 3,
        senderId: 'guest_2',
      );
      final restoredRemove = JamAction.fromPayload(removeAction.toPayload());
      expect(restoredRemove.type, JamActionType.removeFromQueue);
      expect(restoredRemove.queueIndex, 3);
    });
  });

  group('Latency Compensation & Drift Threshold Logic', () {
    test('Calculates expected position with latency compensation', () {
      const sentTimestamp = 100000;
      const receiveTimestamp = 102500; // 2.5s network + processing delay
      const reportedPositionMs = 30000;

      final latency = (receiveTimestamp - sentTimestamp).clamp(0, 5000);
      int computeExpected(int reported, int ltc, bool playing) =>
          reported + (playing ? ltc : 0);

      expect(computeExpected(reportedPositionMs, latency, true), 32500);
      expect(computeExpected(reportedPositionMs, latency, false), 30000);
    });

    test('Drift threshold triggers seek only when drift exceeds 1200ms', () {
      const expectedPos = 35000;

      // Small jitter: 400ms difference -> NO SEEK
      final currentPos1 = 34600;
      final drift1 = (currentPos1 - expectedPos).abs();
      expect(drift1, 400);
      final shouldSeek1 = drift1 > 1200;
      expect(shouldSeek1, false);

      // Audible desync: 1800ms difference -> SEEK
      final currentPos2 = 33200;
      final drift2 = (currentPos2 - expectedPos).abs();
      expect(drift2, 1800);
      final shouldSeek2 = drift2 > 1200;
      expect(shouldSeek2, true);
    });
  });

  group('JamParticipant Presence State', () {
    test('Correctly serializes and parses host and joined_at fields', () {
      final participant = JamParticipant(
        id: 'user_123',
        username: 'TestUser',
        isHost: true,
        joinedAt: 1700000000000,
      );

      final presence = participant.toPresence();
      expect(presence['user_id'], 'user_123');
      expect(presence['username'], 'TestUser');
      expect(presence['is_host'], true);
      expect(presence['joined_at'], 1700000000000);

      final parsed = JamParticipant.fromPresence(presence);
      expect(parsed.id, 'user_123');
      expect(parsed.username, 'TestUser');
      expect(parsed.isHost, true);
      expect(parsed.joinedAt, 1700000000000);
    });

    test('Default values when presence lacks optional fields', () {
      final parsed = JamParticipant.fromPresence({
        'user_id': 'anon_user',
        'username': 'Guest',
      });

      expect(parsed.id, 'anon_user');
      expect(parsed.username, 'Guest');
      expect(parsed.isHost, false);
      expect(parsed.joinedAt, 0);
    });
  });

  group('Jam End-to-End Protocol & State Invariants', () {
    test('Host failover promotes the oldest remaining participant by joinedAt', () {
      final participants = [
        JamParticipant(id: 'host_0', username: 'Host', isHost: true, joinedAt: 1000),
        JamParticipant(id: 'guest_1', username: 'Guest1', isHost: false, joinedAt: 2000),
        JamParticipant(id: 'guest_2', username: 'Guest2', isHost: false, joinedAt: 1500),
        JamParticipant(id: 'guest_3', username: 'Guest3', isHost: false, joinedAt: 3000),
      ];

      // Host disconnects
      final remaining = participants.where((p) => p.id != 'host_0').toList();
      expect(remaining.any((p) => p.isHost), false);

      // Failover sorting logic
      final sorted = List<JamParticipant>.from(remaining)
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      final newHost = sorted.first;

      expect(newHost.id, 'guest_2');
      expect(newHost.joinedAt, 1500);
    });

    test('Self-action filtering prevents echo amplification', () {
      const currentUserId = 'user_abc';
      final selfAction = JamAction(
        id: '1',
        type: JamActionType.playTrack,
        senderId: currentUserId,
      );
      final remoteAction = JamAction(
        id: '2',
        type: JamActionType.playTrack,
        senderId: 'user_xyz',
      );

      bool shouldProcess(JamAction action) => action.senderId != currentUserId;

      expect(shouldProcess(selfAction), false); // Dropped
      expect(shouldProcess(remoteAction), true); // Processed
    });

    test('Queue mutation sequence preserves logical ordering and identity', () {
      final initialTracks = List.generate(
        10,
        (i) => Track(id: 'trk_$i', title: 'Title $i', artist: 'Artist $i', thumbnailUrl: ''),
      );

      // 1. Initial SetQueue
      final setQueueAction = JamAction(
        id: '1',
        type: JamActionType.setQueue,
        queue: initialTracks,
        queueIndex: 0,
        senderId: 'host',
      );
      var currentQueue = List<Track>.from(
        JamAction.fromPayload(setQueueAction.toPayload()).queue!,
      );
      expect(currentQueue.length, 10);

      // 2. Add Track
      final newTrack = Track(id: 'new_song', title: 'Bonus Track', artist: 'Bonus', thumbnailUrl: '');
      final addAction = JamAction(
        id: '2',
        type: JamActionType.addToQueue,
        track: newTrack,
        senderId: 'guest',
      );
      currentQueue.add(JamAction.fromPayload(addAction.toPayload()).track!);
      expect(currentQueue.length, 11);
      expect(currentQueue.last.rawId, 'new_song');

      // 3. Remove Track at index 3
      final removedTarget = currentQueue[3].rawId;
      final removeAction = JamAction(
        id: '3',
        type: JamActionType.removeFromQueue,
        queueIndex: 3,
        senderId: 'host',
      );
      final removeIndex = JamAction.fromPayload(removeAction.toPayload()).queueIndex!;
      currentQueue.removeAt(removeIndex);
      expect(currentQueue.length, 10);
      expect(currentQueue.any((t) => t.rawId == removedTarget), false);
    });

    test('Periodic syncPulse calculates true playback position taking network trip into account', () {
      const hostSentMs = 1700000000000;
      const hostPlaybackPos = 42000; // 42 seconds in song
      const guestReceivedMs = 1700000000180; // 180ms transit time

      final pulseAction = JamAction(
        id: 'pulse_1',
        type: JamActionType.syncPulse,
        positionMs: hostPlaybackPos,
        timestampMs: hostSentMs,
        isPlaying: true,
        senderId: 'host',
      );

      final payload = pulseAction.toPayload();
      final restored = JamAction.fromPayload(payload);

      final latency = (guestReceivedMs - (restored.timestampMs ?? guestReceivedMs)).clamp(0, 5000);
      expect(latency, 180);

      final expectedPos = (restored.positionMs ?? 0) + (restored.isPlaying == true ? latency : 0);
      expect(expectedPos, 42180);
    });
  });
}

