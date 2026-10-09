import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nebula/features/playlist/domain/entities/importable_playlist.dart';
import 'package:nebula/features/playlist/domain/services/playlist_import_service.dart';

class SpotifyImportProvider implements PlaylistImportProvider {
  final Dio _dio;

  SpotifyImportProvider({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                  'Accept-Language': 'en-US,en;q=0.9',
                },
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
              ),
            );

  @override
  String get name => 'Spotify';

  static final RegExp _spotifyUrlPattern = RegExp(
    r'(?:spotify\.com/(?:[a-zA-Z-]+/)?playlist/|spotify:playlist:)([a-zA-Z0-9]{15,30})',
    caseSensitive: false,
  );

  static final RegExp _spotifyIdPattern = RegExp(r'^[a-zA-Z0-9]{22}$');

  @override
  bool canHandle(String input) {
    final trimmed = input.trim();
    return _spotifyUrlPattern.hasMatch(trimmed) || _spotifyIdPattern.hasMatch(trimmed);
  }

  String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    final match = _spotifyUrlPattern.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    if (_spotifyIdPattern.hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  @override
  Future<ImportablePlaylist> fetchPlaylist(String input) async {
    final playlistId = extractPlaylistId(input);
    if (playlistId == null) {
      throw Exception('Invalid Spotify playlist URL or ID.');
    }

    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';

    try {
      final response = await _dio.get(embedUrl);
      final html = response.data.toString();

      final nextDataRegex = RegExp(
        r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>',
      );
      final match = nextDataRegex.firstMatch(html);

      if (match == null) {
        throw Exception(
          'Could not retrieve playlist metadata. Make sure the playlist is public.',
        );
      }

      final jsonRaw = match.group(1)!;
      final parsed = jsonDecode(jsonRaw) as Map<String, dynamic>;

      final entity =
          parsed['props']?['pageProps']?['state']?['data']?['entity']
              as Map<String, dynamic>?;

      if (entity == null) {
        throw Exception(
          'Playlist not found or is private. Only public Spotify playlists can be imported.',
        );
      }

      final title = (entity['name'] ?? entity['title'] ?? 'Spotify Playlist') as String;
      final description = entity['subtitle'] as String?;

      // Extract cover art
      String? coverUrl;
      if (entity['visualIdentity'] != null &&
          entity['visualIdentity']['image'] is List) {
        final images = entity['visualIdentity']['image'] as List;
        if (images.isNotEmpty) {
          // Get the last one (usually highest resolution) or first
          coverUrl = images.last['url'] as String?;
        }
      }

      final trackListRaw = (entity['trackList'] as List?) ?? [];
      final tracks = <ImportableTrack>[];

      for (final raw in trackListRaw) {
        if (raw is Map) {
          final tTitle = (raw['title'] as String?)?.trim();
          final tArtist = (raw['subtitle'] as String?)?.trim();
          final durationMs = raw['duration'] as int? ?? 0;

          if (tTitle != null && tTitle.isNotEmpty) {
            tracks.add(
              ImportableTrack(
                title: tTitle,
                artist: (tArtist != null && tArtist.isNotEmpty)
                    ? tArtist
                    : 'Unknown Artist',
                duration: Duration(milliseconds: durationMs),
              ),
            );
          }
        }
      }

      if (tracks.isEmpty) {
        throw Exception('The playlist is empty or no public tracks could be found.');
      }

      return ImportablePlaylist(
        id: playlistId,
        title: title,
        description: description,
        coverUrl: coverUrl,
        tracks: tracks,
        sourceName: 'Spotify',
      );
    } on DioException catch (e) {
      debugPrint('SpotifyImportProvider Dio error: $e');
      if (e.response?.statusCode == 404) {
        throw Exception('Spotify playlist not found. Check if the link is correct.');
      }
      throw Exception('Failed to connect to Spotify. Check your internet connection.');
    } catch (e) {
      debugPrint('SpotifyImportProvider error: $e');
      if (e is Exception) rethrow;
      throw Exception('Error importing Spotify playlist: $e');
    }
  }
}
