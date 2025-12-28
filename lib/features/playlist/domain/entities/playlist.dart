class Playlist {
  final String id;
  final String name;
  final String userId;
  final int trackCount;

  Playlist({
    required this.id,
    required this.name,
    required this.userId,
    this.trackCount = 0,
  });
}
