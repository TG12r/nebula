import 'package:nebula/features/player/domain/entities/track.dart';

abstract class PlayerRepository {
  // Actions
  Future<String?> play(String videoId);
  Future<void> pause();
  Future<void> resume(); // distinct from play(id)
  Future<void> seek(Duration position);
  Future<List<Track>> search(String query);
  void dispose();

  // State Streams
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get isPlayingStream;
  Stream<Track?> get currentTrackStream;
}
