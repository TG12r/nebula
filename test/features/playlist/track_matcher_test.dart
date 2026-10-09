import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/playlist/domain/entities/importable_playlist.dart';
import 'package:nebula/features/playlist/data/services/playlist_track_matcher.dart';

void main() {
  test('PlaylistTrackMatcher matches tracks from user log accurately', () async {
    final matcher = PlaylistTrackMatcher();

    final testTracks = [
      ImportableTrack(
        title: 'Juanito Alimaña',
        artist: 'Héctor Lavoe, Willie Colón',
        duration: const Duration(minutes: 5, seconds: 44),
      ),
      ImportableTrack(
        title: 'Pedro Navaja',
        artist: 'Willie Colón, Rubén Blades',
        duration: const Duration(minutes: 7, seconds: 21),
      ),
      ImportableTrack(
        title: 'El Cantante',
        artist: 'Héctor Lavoe',
        duration: const Duration(minutes: 10, seconds: 20),
      ),
      ImportableTrack(
        title: 'El Gran Varón',
        artist: 'Willie Colón',
        duration: const Duration(minutes: 6, seconds: 5),
      ),
    ];

    for (final track in testTracks) {
      final matched = await matcher.matchTrack(track);
      expect(matched, isNotNull);
      expect(matched!.id.isNotEmpty, isTrue);
    }

    matcher.dispose();
  });
}
