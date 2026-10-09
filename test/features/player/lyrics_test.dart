import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/features/player/domain/entities/lyrics.dart';
import 'package:nebula/features/player/data/datasources/lyrics_service.dart';

void main() {
  group('Lyrics Entity & LRC Parsing Tests', () {
    test('Lyrics.fromLrc parses standard LRC format into sorted LyricLines', () {
      const lrcContent = '''
[ti:Midnight City]
[ar:M83]
[al:Hurry Up, We're Dreaming]
[00:00.00] Waiting in a car
[00:15.50] Waiting for a ride in the dark
[00:28.12] The night city grows
[01:05.80] Look and see her, how she sparkles
''';

      final lyrics = Lyrics.fromLrc(
        synced: lrcContent,
      );

      expect(lyrics.isSynced, isTrue);
      expect(lyrics.syncedLyrics.length, 4);

      // Verify line 1
      expect(lyrics.syncedLyrics[0].text, 'Waiting in a car');
      expect(lyrics.syncedLyrics[0].timestamp, Duration.zero);

      // Verify line 2
      expect(lyrics.syncedLyrics[1].text, 'Waiting for a ride in the dark');
      expect(lyrics.syncedLyrics[1].timestamp, const Duration(seconds: 15, milliseconds: 500));

      // Verify line 3
      expect(lyrics.syncedLyrics[2].text, 'The night city grows');
      expect(lyrics.syncedLyrics[2].timestamp, const Duration(seconds: 28, milliseconds: 120));

      // Verify line 4
      expect(lyrics.syncedLyrics[3].text, 'Look and see her, how she sparkles');
      expect(lyrics.syncedLyrics[3].timestamp, const Duration(minutes: 1, seconds: 5, milliseconds: 800));
    });

    test('Lyrics.getLineAt returns the correct active line according to duration', () {
      const lrcContent = '''
[00:05.00] Line One
[00:10.00] Line Two
[00:20.00] Line Three
''';

      final lyrics = Lyrics.fromLrc(
        synced: lrcContent,
      );

      // Before first line
      expect(lyrics.getLineAt(const Duration(seconds: 2)), isNull);

      // At or after first line, before second
      final line1 = lyrics.getLineAt(const Duration(seconds: 5));
      expect(line1?.text, 'Line One');

      final line1Late = lyrics.getLineAt(const Duration(seconds: 9));
      expect(line1Late?.text, 'Line One');

      // Second line
      final line2 = lyrics.getLineAt(const Duration(seconds: 15));
      expect(line2?.text, 'Line Two');

      // Third line onwards
      final line3 = lyrics.getLineAt(const Duration(seconds: 35));
      expect(line3?.text, 'Line Three');
    });

    test('Lyrics handles plain un-synced text gracefully', () {
      const plain = 'First line\nSecond line\nThird line';
      final lyrics = Lyrics(
        plainLyrics: plain,
      );

      expect(lyrics.isSynced, isFalse);
      expect(lyrics.hasContent, isTrue);
      expect(lyrics.plainLyrics, plain);
      expect(lyrics.syncedLyrics, isEmpty);
    });

    test('Lyrics handles empty or null content safely', () {
      final emptyLyrics = Lyrics.fromLrc(
        synced: '',
      );

      expect(emptyLyrics.syncedLyrics, isEmpty);
      expect(emptyLyrics.isSynced, isFalse);
      expect(emptyLyrics.hasContent, isFalse);
      expect(emptyLyrics.getLineAt(const Duration(seconds: 10)), isNull);
    });
  });

  group('LyricsService Title Cleaning Tests', () {
    test('cleanTrackTitle strips YouTube music noise and features for high LRCLib hit rate', () {
      expect(
        LyricsService.cleanTrackTitle('Starboy (Official Video) [feat. Daft Punk]'),
        'Starboy',
      );

      expect(
        LyricsService.cleanTrackTitle('Blinding Lights (Official Audio)'),
        'Blinding Lights',
      );

      expect(
        LyricsService.cleanTrackTitle('Save Your Tears (Remix) [Music Video]'),
        'Save Your Tears',
      );

      expect(
        LyricsService.cleanTrackTitle('Levitating ft. DaBaby'),
        'Levitating',
      );

      expect(
        LyricsService.cleanTrackTitle('Get Lucky (feat. Pharrell Williams)'),
        'Get Lucky',
      );

      expect(
        LyricsService.cleanTrackTitle('Shape of You [Official Lyric Video]'),
        'Shape of You',
      );

      expect(
        LyricsService.cleanTrackTitle('SA!KORO - ME VUELVO DEL DIM (PROD. MILANEZIE) #GRACIAS SA!KO', 'SA!KORO'),
        'ME VUELVO DEL DIM',
      );

      expect(
        LyricsService.cleanTrackTitle('Bizarrap & Shakira - Bzrp Music Sessions, Vol. 53 (Video Oficial)', 'Bizarrap'),
        'Bzrp Music Sessions, Vol. 53',
      );
    });
  });
}
