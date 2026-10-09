import 'package:nebula/features/playlist/domain/entities/importable_playlist.dart';

abstract class PlaylistImportProvider {
  String get name;
  bool canHandle(String input);
  Future<ImportablePlaylist> fetchPlaylist(String input);
}
