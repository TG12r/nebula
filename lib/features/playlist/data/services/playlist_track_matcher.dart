import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/core/services/innertube_search_service.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/playlist/domain/entities/importable_playlist.dart';

class PlaylistTrackMatcher {
  final yt_lib.YoutubeExplode _yt;
  final InnerTubeSearchService _innerTube;
  final bool _autoClose;

  PlaylistTrackMatcher({
    yt_lib.YoutubeExplode? yt,
    InnerTubeSearchService? innerTube,
  })  : _yt = yt ?? yt_lib.YoutubeExplode(),
        _innerTube = innerTube ?? InnerTubeSearchService(),
        _autoClose = yt == null;

  /// Attempts to find a matching playable YouTube track for the given importable track
  Future<Track?> matchTrack(ImportableTrack track) async {
    final cleanTitle = InnerTubeSearchService.sanitizeQuery(track.title);
    final cleanArtist = InnerTubeSearchService.sanitizeQuery(track.artist);
    final firstArtist = cleanArtist.split(RegExp(r'[,;&]')).first.trim();

    final queries = <String>[
      if (cleanArtist.isNotEmpty && cleanTitle.isNotEmpty) '$cleanArtist $cleanTitle',
      if (firstArtist.isNotEmpty && firstArtist != cleanArtist && cleanTitle.isNotEmpty)
        '$firstArtist $cleanTitle',
      if (cleanTitle.isNotEmpty && firstArtist.isNotEmpty) '$cleanTitle $firstArtist',
      if (cleanTitle.isNotEmpty) cleanTitle,
    ];

    // 1. Primary: Fast, non-redirecting InnerTube JSON API (YouTube Music + YouTube Web)
    for (final q in queries) {
      try {
        final candidates = await _innerTube.search(q);
        if (candidates.isNotEmpty) {
          InnerTubeSearchResult bestMatch = candidates.first;

          // Pick match with closest duration if available
          if (track.duration > Duration.zero) {
            for (final candidate in candidates.take(6)) {
              if (candidate.duration > Duration.zero) {
                final diff =
                    (candidate.duration.inSeconds - track.duration.inSeconds).abs();
                if (diff <= 15) {
                  bestMatch = candidate;
                  break;
                }
              }
            }
          }

          return Track(
            id: bestMatch.id,
            title: track.title, // Keep clean original metadata from Spotify
            artist: track.artist,
            thumbnailUrl: bestMatch.thumbnailUrl,
            duration: bestMatch.duration > Duration.zero
                ? bestMatch.duration
                : track.duration,
            source: TrackSource.youtube,
          );
        }
      } catch (e) {
        debugPrint('InnerTube matching error for query "$q": $e');
      }
    }

    // 2. Secondary: Fallback to YoutubeExplode if InnerTube returned no candidates
    final fallbackQuery = queries.isNotEmpty ? queries.first : '${track.artist} ${track.title}';
    try {
      final searchResults = await _yt.search.search(fallbackQuery);
      if (searchResults.isNotEmpty) {
        yt_lib.Video bestMatch = searchResults.first;
        if (track.duration > Duration.zero) {
          for (final video in searchResults.take(5)) {
            final vidDuration = video.duration ?? Duration.zero;
            if (vidDuration > Duration.zero) {
              final diff =
                  (vidDuration.inSeconds - track.duration.inSeconds).abs();
              if (diff <= 15) {
                bestMatch = video;
                break;
              }
            }
          }
        }
        return _buildTrack(track, bestMatch);
      }
    } catch (e) {
      debugPrint('YoutubeExplode fallback error for "${track.searchPayload}": $e');
    }

    return null;
  }

  Track _buildTrack(ImportableTrack original, yt_lib.Video video) {
    return Track(
      id: video.id.value,
      title: original.title,
      artist: original.artist,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration ?? original.duration,
      source: TrackSource.youtube,
    );
  }

  void dispose() {
    if (_autoClose) {
      _yt.close();
    }
  }
}
