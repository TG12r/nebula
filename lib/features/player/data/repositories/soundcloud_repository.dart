import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:soundcloud_explode_dart/soundcloud_explode_dart.dart' as sc_lib;
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/core/enums/track_source.dart';

class SoundCloudRepository {
  final sc_lib.SoundcloudClient _sc = sc_lib.SoundcloudClient();

  Future<List<Track>> searchTracks(String query) async {
    try {
      debugPrint("SoundCloud: Searching for $query");
      final stream = _sc.search(query, searchFilter: sc_lib.SearchFilter.tracks);
      
      final List<Track> tracks = [];
      
      // Collect the first batch of results
      await for (final Iterable<sc_lib.SearchResult> batch in stream.take(1)) {
        debugPrint("SoundCloud: Found batch items");
        for (final result in batch) {
          // We use dynamic access if the type check is failing
          try {
            final dynamic res = result;
            final String id = res.id.toString();
            final String title = res.title?.toString() ?? 'Unknown Title';
            final String artist = res.user?.username?.toString() ?? 'Unknown Artist';
            final String thumb = res.artworkUrl?.toString() ?? '';
            final int durationMs = (res.duration as num?)?.toInt() ?? 0;

            tracks.add(Track(
              id: 'sc:$id',
              title: title,
              artist: artist,
              thumbnailUrl: thumb,
              duration: Duration(milliseconds: durationMs),
              source: TrackSource.soundcloud,
            ));
          } catch (e) {
            debugPrint("SoundCloud: Error parsing result item: $e");
          }
        }
      }
      
      return tracks;
    } catch (e) {
      debugPrint("SoundCloud: Search error: $e");
      return [];
    }
  }

  Future<String?> getStreamUrl(String trackId) async {
    try {
      final rawId = TrackSource.stripPrefix(trackId);
      final streams = await _sc.tracks.getStreams(int.parse(rawId));
      
      if (streams.isNotEmpty) {
        return streams.first.url;
      }
      return null;
    } catch (e) {
      debugPrint("SoundCloud: Stream URL error: $e");
      return null;
    }
  }

  void dispose() {
    // No close() in this version
  }
}
