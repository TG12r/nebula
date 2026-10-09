class ImportableTrack {
  final String title;
  final String artist;
  final Duration duration;

  const ImportableTrack({
    required this.title,
    required this.artist,
    this.duration = Duration.zero,
  });

  String get searchPayload => '$artist - $title';

  @override
  String toString() => '$artist - $title';
}

class ImportablePlaylist {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final List<ImportableTrack> tracks;
  final String sourceName;

  const ImportablePlaylist({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    required this.tracks,
    required this.sourceName,
  });

  int get trackCount => tracks.length;
}
