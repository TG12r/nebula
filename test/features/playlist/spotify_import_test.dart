import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/playlist/data/services/spotify_import_provider.dart';

void main() {
  group('SpotifyImportProvider Tests', () {
    final provider = SpotifyImportProvider();

    test('canHandle detects valid Spotify playlist links and IDs', () {
      expect(
        provider.canHandle('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        isTrue,
      );
      expect(
        provider.canHandle('https://open.spotify.com/intl-es/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123xyz'),
        isTrue,
      );
      expect(
        provider.canHandle('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        isTrue,
      );
      expect(
        provider.canHandle('37i9dQZF1DXcBWIGoYBM5M'),
        isTrue,
      );
      expect(
        provider.canHandle('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isFalse,
      );
      expect(
        provider.canHandle('not_a_valid_url'),
        isFalse,
      );
    });

    test('extractPlaylistId parses ID accurately', () {
      expect(
        provider.extractPlaylistId('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(
        provider.extractPlaylistId('https://open.spotify.com/intl-fr/playlist/37i9dQZF1DXcBWIGoYBM5M?si=test'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(
        provider.extractPlaylistId('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(
        provider.extractPlaylistId('37i9dQZF1DXcBWIGoYBM5M'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
    });

    test('fetchPlaylist retrieves and parses public playlist metadata and tracks', () async {
      // Test with a standard public Spotify editorial playlist ID
      final result = await provider.fetchPlaylist('37i9dQZF1DXcBWIGoYBM5M');

      expect(result.id, equals('37i9dQZF1DXcBWIGoYBM5M'));
      expect(result.title.isNotEmpty, isTrue);
      expect(result.tracks.isNotEmpty, isTrue);
      expect(result.trackCount, greaterThan(0));

      final firstTrack = result.tracks.first;
      expect(firstTrack.title.isNotEmpty, isTrue);
      expect(firstTrack.artist.isNotEmpty, isTrue);
      expect(firstTrack.duration, greaterThan(Duration.zero));
    });
  });
}
