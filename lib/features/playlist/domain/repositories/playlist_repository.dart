import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';

abstract class PlaylistRepository {
  Future<List<Playlist>> getPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> deletePlaylist(String playlistId);

  Future<List<Track>> getPlaylistTracks(String playlistId);
  Future<void> addTrackToPlaylist(String playlistId, Track track);
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId);
}
