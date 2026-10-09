import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class InnerTubeSearchResult {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;

  const InnerTubeSearchResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
  });

  @override
  String toString() =>
      'InnerTubeSearchResult(id: $id, title: $title, artist: $artist, duration: $duration)';
}

class InnerTubeSearchService {
  final Dio _dio;

  InnerTubeSearchService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  static const String _ytMusicSearchUrl =
      'https://music.youtube.com/youtubei/v1/search';
  static const String _ytWebSearchUrl =
      'https://www.youtube.com/youtubei/v1/search';

  static const Map<String, String> _ytMusicHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Content-Type': 'application/json',
    'Referer': 'https://music.youtube.com/',
    'Origin': 'https://music.youtube.com',
  };

  static const Map<String, String> _ytWebHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Content-Type': 'application/json',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  /// Cleans titles and artist names from noise that harms search accuracy
  static String sanitizeQuery(String text) {
    var cleaned = text.replaceAll('\u00A0', ' '); // Non-breaking space
    // Remove featured artists markers in brackets
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[](?:feat\.|ft\.|with|featuring)[^\)\]]*[\)\]]', caseSensitive: false),
      ' ',
    );
    // Remove remaster/edition markers
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[\(\[](?:remastered|remaster|deluxe|bonus track|anniversary|edition|version|mono|stereo)[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      ' ',
    );
    // Remove trailing remaster/live tags
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*-\s*(?:remastered|live|radio edit|mono|stereo|bonus track).*$', caseSensitive: false),
      ' ',
    );
    // Replace commas, semicolons with space
    cleaned = cleaned.replaceAll(RegExp(r'[,;]'), ' ');
    // Collapse multiple whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  /// Parses duration strings like "3:45" or "1:02:15" into a [Duration]
  static Duration parseDuration(String? text) {
    if (text == null || text.trim().isEmpty) return Duration.zero;
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return Duration.zero;
  }

  /// Searches InnerTube. Prioritizes YouTube Music (audio/songs), falls back to YouTube Web.
  Future<List<InnerTubeSearchResult>> search(String query) async {
    final sanitized = sanitizeQuery(query);
    if (sanitized.isEmpty) return [];

    // 1. Try YouTube Music (WEB_REMIX)
    try {
      final musicResults = await _searchYtMusic(sanitized);
      if (musicResults.isNotEmpty) {
        return musicResults;
      }
    } catch (e) {
      debugPrint('InnerTube Music search failed ($sanitized): $e');
    }

    // 2. Fallback to YouTube Web (WEB)
    try {
      final webResults = await _searchYtWeb(sanitized);
      if (webResults.isNotEmpty) {
        return webResults;
      }
    } catch (e) {
      debugPrint('InnerTube Web search failed ($sanitized): $e');
    }

    return [];
  }

  Future<List<InnerTubeSearchResult>> _searchYtMusic(String query) async {
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': query,
    };

    final response = await _dio.post(
      _ytMusicSearchUrl,
      data: payload,
      options: Options(headers: _ytMusicHeaders),
    );

    if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
      return [];
    }

    final data = response.data as Map<String, dynamic>;
    final tabs = (data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?) ?? [];
    if (tabs.isEmpty) return [];

    final sections = (tabs.first['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?) ?? [];
    final results = <InnerTubeSearchResult>[];

    for (final sec in sections) {
      // 1. Check musicCardShelfRenderer (Top result)
      if (sec['musicCardShelfRenderer'] != null) {
        final card = sec['musicCardShelfRenderer'] as Map<String, dynamic>;
        final videoId = card['onTap']?['watchEndpoint']?['videoId'] as String?;
        if (videoId != null && videoId.isNotEmpty) {
          final titleRuns = (card['title']?['runs'] as List?) ?? [];
          final title = titleRuns.map((r) => r['text'] ?? '').join().trim();

          final subtitleRuns = (card['subtitle']?['runs'] as List?) ?? [];
          String artist = '';
          Duration duration = Duration.zero;

          for (final run in subtitleRuns) {
            final t = (run['text'] as String?)?.trim() ?? '';
            if (t.contains(':')) {
              duration = parseDuration(t);
            } else if (artist.isEmpty &&
                t != '&' &&
                t != '•' &&
                !t.toLowerCase().contains('views') &&
                !t.toLowerCase().contains('video') &&
                !t.toLowerCase().contains('song')) {
              artist = t;
            }
          }

          final thumbs = (card['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?) ?? [];
          final thumbUrl = thumbs.isNotEmpty
              ? (thumbs.last['url'] as String? ?? 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg')
              : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

          results.add(
            InnerTubeSearchResult(
              id: videoId,
              title: title.isNotEmpty ? title : query,
              artist: artist.isNotEmpty ? artist : 'Unknown',
              duration: duration,
              thumbnailUrl: thumbUrl,
            ),
          );
        }
      }

      // 2. Check itemSectionRenderer (Song / Video list items)
      if (sec['itemSectionRenderer'] != null) {
        final contents = (sec['itemSectionRenderer']['contents'] as List?) ?? [];
        for (final item in contents) {
          final r = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          if (r == null) continue;

          final videoId = r['playlistItemData']?['videoId'] as String? ??
              r['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String?;

          if (videoId == null || videoId.isEmpty) continue;

          // Flex columns contain title, artist, duration
          final flexCols = (r['flexColumns'] as List?) ?? [];
          String itemTitle = '';
          String itemArtist = '';
          Duration itemDuration = Duration.zero;

          if (flexCols.isNotEmpty) {
            final col0Runs = (flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?) ?? [];
            itemTitle = col0Runs.map((rn) => rn['text'] ?? '').join().trim();
          }

          if (flexCols.length > 1) {
            final col1Runs = (flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?) ?? [];
            for (final run in col1Runs) {
              final t = (run['text'] as String?)?.trim() ?? '';
              if (t.contains(':')) {
                itemDuration = parseDuration(t);
              } else if (itemArtist.isEmpty &&
                  t != '•' &&
                  !t.toLowerCase().contains('song') &&
                  !t.toLowerCase().contains('video') &&
                  !t.toLowerCase().contains('plays') &&
                  !t.toLowerCase().contains('views')) {
                itemArtist = t;
              }
            }
          }

          final thumbs = (r['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?) ?? [];
          final thumbUrl = thumbs.isNotEmpty
              ? (thumbs.last['url'] as String? ?? 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg')
              : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

          results.add(
            InnerTubeSearchResult(
              id: videoId,
              title: itemTitle.isNotEmpty ? itemTitle : query,
              artist: itemArtist.isNotEmpty ? itemArtist : 'Unknown',
              duration: itemDuration,
              thumbnailUrl: thumbUrl,
            ),
          );
        }
      }
    }

    return results;
  }

  Future<List<InnerTubeSearchResult>> _searchYtWeb(String query) async {
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': query,
    };

    final response = await _dio.post(
      _ytWebSearchUrl,
      data: payload,
      options: Options(headers: _ytWebHeaders),
    );

    if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
      return [];
    }

    final data = response.data as Map<String, dynamic>;
    final twoCol = data['contents']?['twoColumnSearchResultsRenderer'];
    final sectionList = twoCol?['primaryContents']?['sectionListRenderer'];
    final sections = (sectionList?['contents'] as List?) ?? [];
    final results = <InnerTubeSearchResult>[];

    for (final sec in sections) {
      final items = (sec['itemSectionRenderer']?['contents'] as List?) ?? [];
      for (final item in items) {
        final video = item['videoRenderer'] as Map<String, dynamic>?;
        if (video == null) continue;

        final videoId = video['videoId'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        final titleRuns = (video['title']?['runs'] as List?) ?? [];
        final title = titleRuns.map((r) => r['text'] ?? '').join().trim();

        final ownerRuns = (video['ownerText']?['runs'] as List?) ?? [];
        final artist = ownerRuns.map((r) => r['text'] ?? '').join().trim();

        final lengthText = video['lengthText']?['simpleText'] as String?;
        final duration = parseDuration(lengthText);

        final thumbs = (video['thumbnail']?['thumbnails'] as List?) ?? [];
        final thumbUrl = thumbs.isNotEmpty
            ? (thumbs.last['url'] as String? ?? 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg')
            : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

        results.add(
          InnerTubeSearchResult(
            id: videoId,
            title: title.isNotEmpty ? title : query,
            artist: artist.isNotEmpty ? artist : 'Unknown',
            duration: duration,
            thumbnailUrl: thumbUrl,
          ),
        );
      }
    }

    return results;
  }
}
