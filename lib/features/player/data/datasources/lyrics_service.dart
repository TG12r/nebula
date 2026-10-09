import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/player/domain/entities/lyrics.dart';

class LyricsService {
  final Dio _dio;
  final Map<String, Lyrics> _memoryCache = {};

  LyricsService([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://lrclib.net/api',
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
                headers: {
                  'User-Agent': 'NebulaMusicApp/1.1.0 (https://github.com/nebula)',
                },
              ),
            );

  /// Strips common YouTube video noise, hashtags, producers, and leading artist tags to maximize metadata matches on LRCLib
  static String cleanTrackTitle(String rawTitle, [String? artist]) {
    var title = rawTitle;

    // 1. Remove hashtags (e.g. #GRACIAS SA!KO, #shorts, etc.)
    title = title.replaceAll(RegExp(r'#.*$'), '');

    // 2. Remove common video/audio parenthesized/bracketed metadata
    title = title
        .replaceAll(RegExp(r'\s*\(.*?official.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?official.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?music video.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?music video.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?video oficial.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?video oficial.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?lyric.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?lyric.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?letra.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?letra.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?hd.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?hd.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?4k.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?4k.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?audio.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?audio.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?remix.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?remix.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?prod\.?.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?prod\.?.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(.*?visualizer.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[.*?visualizer.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[\(\[]\s*(?:feat|ft)\.?\s+.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(?:feat|ft)\.?\s+.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\|\s*.*$'), '')
        .replaceAll(RegExp(r'\s*//\s*.*$'), '');

    // 3. Strip leading artist prefix if present: "Artist - Title" or "Artist: Title"
    if (artist != null && artist.trim().isNotEmpty) {
      final cleanArt = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
      final escapedArtist = RegExp.escape(cleanArt);
      title = title.replaceFirst(RegExp('^$escapedArtist\\s*[-–—:]\\s*', caseSensitive: false), '');
    }

    // 4. If title has "Artist - Title" format, check if the first part matches artist
    final dashSplit = title.split(RegExp(r'\s+[-–—]\s+'));
    if (dashSplit.length >= 2) {
      final possibleArtist = dashSplit[0].trim().toLowerCase();
      if (artist != null && (artist.toLowerCase().contains(possibleArtist) || possibleArtist.contains(artist.toLowerCase()))) {
        title = dashSplit.sublist(1).join(' - ');
      }
    }

    return title.trim();
  }

  Future<Lyrics?> getLyrics({
    required String trackId,
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    // 1. Check in-memory cache
    if (_memoryCache.containsKey(trackId)) {
      return _memoryCache[trackId];
    }

    final cleanArtist = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
    final cleanTitle = cleanTrackTitle(title, cleanArtist);

    Lyrics? parseResponse(Map<String, dynamic> data) {
      final lyrics = Lyrics.fromLrc(
        plain: data['plainLyrics'] as String?,
        synced: data['syncedLyrics'] as String?,
      );
      return lyrics.hasContent ? lyrics : null;
    }

    // 2. Exact match attempt via /api/get (unconstrained by duration first to allow intro/outro deltas)
    try {
      final queryParams = <String, dynamic>{
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      };

      final response = await _dio.get('/get', queryParameters: queryParams);
      if (response.statusCode == 200 && response.data != null) {
        final lyrics = parseResponse(response.data as Map<String, dynamic>);
        if (lyrics != null) {
          _memoryCache[trackId] = lyrics;
          return lyrics;
        }
      }
    } catch (_) {
      // 404 or connection failure, continue to fallback search
    }

    // 3. Fallback search attempts via /api/search (try "$artist $title", then "$title")
    final searchCandidates = [
      if (cleanArtist.isNotEmpty) '$cleanArtist $cleanTitle'.trim(),
      cleanTitle,
    ];

    for (final candidate in searchCandidates) {
      if (candidate.isEmpty) continue;
      try {
        final searchResponse = await _dio.get('/search', queryParameters: {'q': candidate});

        if (searchResponse.statusCode == 200 && searchResponse.data is List) {
          final results = searchResponse.data as List;
          if (results.isNotEmpty) {
            // Prioritize results that provide synced lyrics
            Map<String, dynamic>? bestResult;
            for (final item in results) {
              if (item is Map<String, dynamic>) {
                final synced = item['syncedLyrics'] as String?;
                if (synced != null && synced.trim().isNotEmpty) {
                  bestResult = item;
                  break;
                }
              }
            }
            bestResult ??= results.first as Map<String, dynamic>;

            final lyrics = parseResponse(bestResult);
            if (lyrics != null) {
              _memoryCache[trackId] = lyrics;
              return lyrics;
            }
          }
        }
      } catch (e) {
        debugPrint('LyricsService: Search query failed for "$candidate": $e');
      }
    }

    return null;
  }
}
