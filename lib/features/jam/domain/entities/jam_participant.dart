/// Represents a participant in a Jam session.
/// Built from Supabase Presence state.
class JamParticipant {
  final String id;
  final String username;
  final bool isHost;
  final int joinedAt;

  const JamParticipant({
    required this.id,
    required this.username,
    this.isHost = false,
    this.joinedAt = 0,
  });

  factory JamParticipant.fromPresence(Map<String, dynamic> state) {
    return JamParticipant(
      id: state['user_id'] as String? ?? '',
      username: state['username'] as String? ?? 'UNKNOWN',
      isHost: state['is_host'] as bool? ?? false,
      joinedAt: state['joined_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toPresence() {
    return {
      'user_id': id,
      'username': username,
      'is_host': isHost,
      'joined_at': joinedAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JamParticipant &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
