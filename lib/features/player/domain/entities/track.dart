import 'package:nebula/core/enums/track_source.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final TrackSource source;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.duration = Duration.zero,
    this.source = TrackSource.youtube,
  });

  /// The ID used for storage/DB, includes the source prefix
  String get storageId => '${source.idPrefix}${TrackSource.stripPrefix(id)}';

  /// The raw ID without prefix (e.g. YouTube Video ID or SoundCloud Track ID)
  String get rawId => TrackSource.stripPrefix(id);

  Map<String, dynamic> toMap() {
    return {
      'id': storageId,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration.inSeconds,
      'source': source.name,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    final id = map['id'] ?? '';
    return Track(
      id: id,
      title: map['title'] ?? '',
      artist: map['artist'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      duration: Duration(seconds: map['duration'] ?? 0),
      source: map['source'] != null
          ? TrackSource.values.byName(map['source'])
          : TrackSource.fromId(id),
    );
  }
}
