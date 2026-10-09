class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  @override
  String toString() => '[${timestamp.inSeconds}s]: $text';
}

class Lyrics {
  final String? plainLyrics;
  final List<LyricLine> syncedLyrics;

  const Lyrics({
    this.plainLyrics,
    this.syncedLyrics = const [],
  });

  bool get isSynced => syncedLyrics.isNotEmpty;
  bool get hasContent => (plainLyrics != null && plainLyrics!.trim().isNotEmpty) || isSynced;

  /// Returns the active LyricLine at the given [position]
  LyricLine? getLineAt(Duration position) {
    if (!isSynced) return null;
    LyricLine? active;
    for (final line in syncedLyrics) {
      if (position >= line.timestamp) {
        active = line;
      } else {
        break;
      }
    }
    return active;
  }

  /// Parses standard LRC formatted string: "[mm:ss.xx] Lyric text"
  static Lyrics fromLrc({String? plain, String? synced}) {
    if (synced == null || synced.trim().isEmpty) {
      return Lyrics(plainLyrics: plain, syncedLyrics: const []);
    }

    final List<LyricLine> lines = [];
    final regExp = RegExp(r'^\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)$');

    for (final rawLine in synced.split('\n')) {
      final line = rawLine.trim();
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final millisStr = match.group(3) ?? '0';
        final millis = millisStr.length == 2
            ? (int.tryParse(millisStr) ?? 0) * 10
            : (int.tryParse(millisStr) ?? 0);

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          lines.add(LyricLine(timestamp: duration, text: text));
        }
      }
    }

    // Sort by timestamp just in case
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Lyrics(
      plainLyrics: plain,
      syncedLyrics: lines,
    );
  }
}
