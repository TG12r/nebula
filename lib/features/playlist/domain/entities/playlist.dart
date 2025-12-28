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

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'userId': userId, 'trackCount': trackCount};
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      userId: map['userId'] ?? '',
      trackCount: map['trackCount'] ?? 0,
    );
  }
}
