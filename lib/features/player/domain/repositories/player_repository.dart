import 'package:audio_service/audio_service.dart';
import 'package:nebula/features/player/domain/entities/track.dart';

abstract class PlayerRepository {
  // Actions
  Future<String?> play(Track track, {bool autoPlay = true});
  Future<void> setQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  });
  Future<void> updateQueuePreservingCurrent(
    List<Track> tracks, {
    required int currentIndex,
  });
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> skipToQueueItem(int index);
  Future<void> pause();
  Future<void> resume(); // distinct from play(id)
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<List<Track>> search(String query);
  void dispose();

  // State Streams
  double get volume;
  Stream<double> get volumeStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get isPlayingStream;
  Stream<Track?> get currentTrackStream;
  Stream<List<Track>> get queueStream;
  Stream<AudioProcessingState> get processingStateStream;

  // Queue Management
  Future<void> addToQueue(Track track);
  Future<void> removeFromQueue(int index);
  Future<void> clearQueue();
  Future<void> shuffleQueue();
}
