class Track {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.duration = Duration.zero,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration.inSeconds,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      artist: map['artist'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      duration: Duration(seconds: map['duration'] ?? 0),
    );
  }
}
