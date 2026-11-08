import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';

class FakePlaylistRepository implements PlaylistRepository {
  List<Playlist> storedPlaylists = [];
  List<String> customOrder = [];
  String? savedSortType;

  FakePlaylistRepository({List<Playlist>? initial}) {
    if (initial != null) {
      storedPlaylists = List.from(initial);
    }
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    return List.from(storedPlaylists);
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final p = Playlist(id: 'pl_${DateTime.now().millisecondsSinceEpoch}', name: name, userId: 'u1');
    storedPlaylists.insert(0, p);
    return p;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    storedPlaylists.removeWhere((p) => p.id == playlistId);
  }

  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async => [];

  @override
  Future<void> addTrackToPlaylist(String playlistId, Track track) async {}

  @override
  Future<void> addTracksToPlaylist(String playlistId, List<Track> tracks) async {}

  @override
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {}

  @override
  Future<List<String>> getPlaylistsContainingTrack(String trackId) async => [];

  @override
  Future<void> savePlaylistsOrder(List<String> playlistIds) async {
    customOrder = List.from(playlistIds);
  }

  @override
  Future<List<String>> getPlaylistsOrder() async {
    return List.from(customOrder);
  }

  @override
  Future<void> savePlaylistSortType(String sortType) async {
    savedSortType = sortType;
  }

  @override
  Future<String?> getPlaylistSortType() async {
    return savedSortType;
  }
}

void main() {
  group('Playlist Organization & Sorting Tests', () {
    late FakePlaylistRepository repo;
    final p1 = Playlist(id: '1', name: 'Cyberpunk', userId: 'u1', trackCount: 5);
    final p2 = Playlist(id: '2', name: 'Ambient', userId: 'u1', trackCount: 12);
    final p3 = Playlist(id: '3', name: 'Synthwave', userId: 'u1', trackCount: 2);

    setUp(() {
      repo = FakePlaylistRepository(initial: [p1, p2, p3]);
    });

    test('reorderPlaylists shifts items and persists custom order', () async {
      final controller = PlaylistController(repo);
      await pumpEventQueue();

      expect(controller.playlists.map((p) => p.name).toList(), ['Cyberpunk', 'Ambient', 'Synthwave']);

      // Reorder: move 'Synthwave' (index 2) to top (index 0)
      await controller.reorderPlaylists(2, 0);

      expect(controller.playlists.map((p) => p.name).toList(), ['Synthwave', 'Cyberpunk', 'Ambient']);
      expect(controller.sortType, PlaylistSortType.custom);
      expect(repo.customOrder, ['3', '1', '2']);
      expect(repo.savedSortType, PlaylistSortType.custom.name);
    });

    test('reorderPlaylists moving item downwards shifts indices accurately', () async {
      final controller = PlaylistController(repo);
      await pumpEventQueue();

      // Move 'Cyberpunk' (index 0) to after 'Ambient' (index 1 -> drop at 2)
      await controller.reorderPlaylists(0, 2);

      expect(controller.playlists.map((p) => p.name).toList(), ['Ambient', 'Cyberpunk', 'Synthwave']);
      expect(repo.customOrder, ['2', '1', '3']);
    });

    test('setSortType nameAsc sorts alphabetically from A to Z', () async {
      final controller = PlaylistController(repo);
      await pumpEventQueue();

      await controller.setSortType(PlaylistSortType.nameAsc);

      expect(controller.playlists.map((p) => p.name).toList(), ['Ambient', 'Cyberpunk', 'Synthwave']);
      expect(repo.savedSortType, PlaylistSortType.nameAsc.name);
    });

    test('setSortType nameDesc sorts alphabetically from Z to A', () async {
      final controller = PlaylistController(repo);
      await pumpEventQueue();

      await controller.setSortType(PlaylistSortType.nameDesc);

      expect(controller.playlists.map((p) => p.name).toList(), ['Synthwave', 'Cyberpunk', 'Ambient']);
      expect(repo.savedSortType, PlaylistSortType.nameDesc.name);
    });

    test('setSortType tracksCount sorts by number of tracks descending', () async {
      final controller = PlaylistController(repo);
      await pumpEventQueue();

      await controller.setSortType(PlaylistSortType.tracksCount);

      // p2 (12 tracks), p1 (5 tracks), p3 (2 tracks)
      expect(controller.playlists.map((p) => p.name).toList(), ['Ambient', 'Cyberpunk', 'Synthwave']);
      expect(controller.playlists.map((p) => p.trackCount).toList(), [12, 5, 2]);
      expect(repo.savedSortType, PlaylistSortType.tracksCount.name);
    });
  });
}

