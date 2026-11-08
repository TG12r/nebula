import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';

/// Jam Session screen — shows participants, current track, and session controls.
/// Follows Nebula CMF design: monochrome, dot-grid background, Courier New,
/// sharp corners, technical labels, no vibrant gradients.
class JamScreen extends StatefulWidget {
  const JamScreen({super.key});

  @override
  State<JamScreen> createState() => _JamScreenState();
}

class _JamScreenState extends State<JamScreen> {
  bool _isPopping = false;
  double? _dragValue;

  void _safePop() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    Navigator.pop(context);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
    }
    return '${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        children: [
          // Dot-grid background (Cached into GPU layer)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: GridPainter(
                  color: Colors.white.withValues(alpha: 0.08),
                  step: 24.0,
                  radius: 1.5,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Consumer2<JamController, PlayerController>(
              builder: (context, jam, player, _) {
                if (!jam.isInJam) {
                  if (!_isPopping) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _safePop();
                    });
                  }
                  return const SizedBox.shrink();
                }

                final currentTrackRawId = player.currentTrack != null
                    ? TrackSource.stripPrefix(player.currentTrack!.id)
                    : null;

                return SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Header ---
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: _safePop,
                            ),
                            Column(
                              children: [
                                Text(
                                  'JAM SESSION',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppTheme.nebulaPurple,
                                        letterSpacing: 2.0,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                _buildSyncBadge(context, jam.syncStatus),
                              ],
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Code Display ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: GestureDetector(
                          onTap: () {
                            if (jam.jamCode != null) {
                              Clipboard.setData(
                                ClipboardData(text: jam.jamCode!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'CODE COPIED',
                                    style: TextStyle(fontFamily: 'Courier New'),
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppTheme.nebulaPurple.withValues(alpha: 0.3),
                                width: 1,
                              ),
                              color: Colors.white.withValues(alpha: 0.02),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'CHANNEL CODE',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        fontSize: 10,
                                        letterSpacing: 2.0,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      jam.jamCode ?? '------',
                                      style: const TextStyle(
                                        fontFamily: 'Courier New',
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 8,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.copy,
                                      color: Colors.white.withValues(alpha: 0.3),
                                      size: 16,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'TAP TO COPY',
                                  style: TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white.withValues(alpha: 0.2),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // --- Participants ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'PARTICIPANTS  [${jam.participants.length}]',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.nebulaPurple,
                                    letterSpacing: 2.0,
                                  ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Participant List
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: jam.participants.isEmpty
                            ? Text(
                                'WAITING FOR PEERS...',
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 12,
                                ),
                              )
                            : Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: jam.participants.map((participant) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: participant.isHost
                                            ? AppTheme.nebulaPurple
                                            : Colors.white.withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                      color: participant.isHost
                                          ? AppTheme.nebulaPurple.withValues(alpha: 0.08)
                                          : Colors.white.withValues(alpha: 0.03),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: participant.isHost
                                                ? AppTheme.nebulaPurple
                                                : Colors.white54,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          participant.username.toUpperCase(),
                                          style: const TextStyle(
                                            fontFamily: 'Courier New',
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (participant.isHost) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.nebulaPurple,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                            child: const Text(
                                              'HOST',
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),

                      const SizedBox(height: 24),

                      // --- Now Playing in Jam ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'NOW PLAYING',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.nebulaPurple,
                                    letterSpacing: 2.0,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Current track info + Controls
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                            color: Colors.white.withValues(alpha: 0.02),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: player.currentTrack == null
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FullPlayerScreen(),
                                          ),
                                        );
                                      },
                                child: Row(
                                  children: [
                                    // Album Art
                                    ClipRRect(
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: player.currentThumbnail != null
                                            ? NebulaImage(
                                                url: player.currentThumbnail!,
                                                fit: BoxFit.cover,
                                                isThumbnail: true,
                                              )
                                            : Container(
                                                color: AppTheme.cmfDarkGrey,
                                                child: const Icon(
                                                  Icons.music_note,
                                                  color: Colors.white24,
                                                  size: 20,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Track Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            player.currentTitle?.toUpperCase() ??
                                                'NO TRACK LOADED',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Courier New',
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            player.currentArtist?.toUpperCase() ??
                                                'UNKNOWN ARTIST',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Courier New',
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (player.currentTrack != null)
                                      Icon(
                                        Icons.open_in_full,
                                        size: 14,
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              if (player.currentTrack != null) ...[
                                const SizedBox(height: 12),
                                StreamBuilder<Duration>(
                                  stream: player.positionStream,
                                  initialData: player.position,
                                  builder: (context, snapshot) {
                                    final pos = snapshot.data ?? player.position;
                                    final dur = player.duration;
                                    final maxMs = dur.inMilliseconds > 0
                                        ? dur.inMilliseconds.toDouble()
                                        : 1.0;
                                    final currentMs = (_dragValue ??
                                            pos.inMilliseconds.toDouble())
                                        .clamp(0.0, maxMs);

                                    return Column(
                                      children: [
                                        SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 2,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                  enabledThumbRadius: 5,
                                                ),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                  overlayRadius: 12,
                                                ),
                                            activeTrackColor:
                                                AppTheme.nebulaPurple,
                                            inactiveTrackColor: Colors.white12,
                                            thumbColor: AppTheme.nebulaPurple,
                                          ),
                                          child: Slider(
                                            min: 0.0,
                                            max: maxMs,
                                            value: currentMs,
                                            onChanged: dur.inMilliseconds > 0
                                                ? (val) {
                                                    setState(() {
                                                      _dragValue = val;
                                                    });
                                                  }
                                                : null,
                                            onChangeEnd: dur.inMilliseconds > 0
                                                ? (val) {
                                                    setState(() {
                                                      _dragValue = null;
                                                    });
                                                    jam.seek(
                                                      Duration(
                                                        milliseconds:
                                                            val.round(),
                                                      ),
                                                    );
                                                  }
                                                : null,
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDuration(
                                                Duration(
                                                  milliseconds:
                                                      currentMs.round(),
                                                ),
                                              ),
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                fontSize: 10,
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatDuration(dur),
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                fontSize: 10,
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],

                              const SizedBox(height: 12),

                              // Direct Playback Controls
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous),
                                    color: Colors.white70,
                                    iconSize: 26,
                                    onPressed: () => jam.skipToPrevious(),
                                  ),
                                  const SizedBox(width: 16),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppTheme.nebulaPurple,
                                        width: 1,
                                      ),
                                      color: AppTheme.nebulaPurple.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        player.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      color: AppTheme.nebulaPurple,
                                      iconSize: 28,
                                      onPressed: () => jam.togglePlay(),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    icon: const Icon(Icons.skip_next),
                                    color: Colors.white70,
                                    iconSize: 26,
                                    onPressed: () => jam.skipToNext(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Last action by
                      if (jam.lastActionBy != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'LAST ACTION BY: ${jam.lastActionBy!.toUpperCase()}',
                            style: TextStyle(
                              fontFamily: 'Courier New',
                              color: AppTheme.nebulaPurple.withValues(alpha: 0.5),
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // --- Shared Queue Section ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'UP NEXT  [${player.queue.length}]',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppTheme.nebulaPurple,
                                    letterSpacing: 2.0,
                                  ),
                            ),
                            if (player.queue.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => jam.shuffleQueue(),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.shuffle,
                                            size: 14,
                                            color: Colors.white.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'SHUFFLE',
                                            style: TextStyle(
                                              fontFamily: 'Courier New',
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => jam.clearQueue(),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.clear_all,
                                            size: 14,
                                            color: Colors.redAccent.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'CLEAR',
                                            style: TextStyle(
                                              fontFamily: 'Courier New',
                                              color: Colors.redAccent.withValues(
                                                alpha: 0.7,
                                              ),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Queue List
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: player.queue.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'QUEUE IS EMPTY. ADD TRACKS FROM SEARCH OR PLAYLISTS.',
                                  style: TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white.withValues(alpha: 0.3),
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: player.queue.length,
                                itemBuilder: (context, index) {
                                  final track = player.queue[index];
                                  final isCurrent = currentTrackRawId != null &&
                                      TrackSource.stripPrefix(track.id) ==
                                          currentTrackRawId;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isCurrent
                                            ? AppTheme.nebulaPurple.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                        width: 1,
                                      ),
                                      color: isCurrent
                                          ? AppTheme.nebulaPurple.withValues(
                                              alpha: 0.05,
                                            )
                                          : Colors.white.withValues(alpha: 0.01),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      onTap: () {
                                        if (!isCurrent) {
                                          jam.skipToQueueItem(index);
                                        }
                                      },
                                      leading: ClipRRect(
                                        child: SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: NebulaImage(
                                            url: track.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            isThumbnail: true,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        track.title.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Courier New',
                                          color: isCurrent
                                              ? AppTheme.nebulaPurple
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Text(
                                        track.artist.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Courier New',
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          fontSize: 10,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white38,
                                        ),
                                        onPressed: () =>
                                            jam.removeFromQueue(index),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 32),

                      // --- Leave Jam Button ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              _isPopping = true;
                              await jam.leaveJam();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.redAccent,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              side: const BorderSide(
                                color: Colors.redAccent,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'LEAVE JAM',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Colors.redAccent,
                                    fontFamily: 'Courier New',
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBadge(BuildContext context, JamSyncStatus status) {
    Color color;
    String label;
    switch (status) {
      case JamSyncStatus.synced:
        color = const Color(0xFF00FF66);
        label = 'SYNC: LOCKED';
        break;
      case JamSyncStatus.syncing:
        color = const Color(0xFFFFB800);
        label = 'SYNC: ADJUSTING';
        break;
      case JamSyncStatus.buffering:
        color = const Color(0xFF00E5FF);
        label = 'SYNC: BUFFERING';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Courier New',
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
