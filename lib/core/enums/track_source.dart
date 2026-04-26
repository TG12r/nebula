enum TrackSource {
  youtube,
  soundcloud;

  String get idPrefix {
    switch (this) {
      case TrackSource.youtube:
        return 'yt:';
      case TrackSource.soundcloud:
        return 'sc:';
    }
  }

  String get publicLabel {
    switch (this) {
      case TrackSource.youtube:
        return 'YT_PUBLIC';
      case TrackSource.soundcloud:
        return 'SC_PUBLIC';
    }
  }

  static TrackSource fromId(String id) {
    if (id.startsWith('sc:')) return TrackSource.soundcloud;
    // Default to youtube for backward compatibility (no prefix or yt: prefix)
    return TrackSource.youtube;
  }

  static String stripPrefix(String id) {
    if (id.startsWith('sc:')) return id.substring(3);
    if (id.startsWith('yt:')) return id.substring(3);
    return id;
  }
}
