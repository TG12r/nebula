import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/jam/presentation/widgets/jam_bottom_sheet.dart';
import 'package:nebula/features/jam/presentation/screens/jam_screen.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class HomeFeedScreen extends StatelessWidget {
  const HomeFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 96.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NEBULA',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(letterSpacing: -1.0),
                    ),
                    Text(
                      'SYSTEM: ONLINE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Jam Button with status & count
                    Consumer<JamController>(
                      builder: (context, jam, _) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            InkWell(
                              onTap: () {
                                if (jam.isInJam) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const JamScreen(),
                                    ),
                                  );
                                } else {
                                  JamBottomSheet.show(context);
                                }
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: jam.isInJam
                                      ? AppTheme.nebulaPurple.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: jam.isInJam
                                        ? AppTheme.nebulaPurple
                                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Icon(
                                  jam.isInJam ? Icons.people : Icons.people_outline,
                                  color: jam.isInJam
                                      ? AppTheme.nebulaPurple
                                      : Theme.of(context).colorScheme.onSurface,
                                  size: 20,
                                ),
                              ),
                            ),
                            if (jam.isInJam && jam.participants.isNotEmpty)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.nebulaPurple,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${jam.participants.length}',
                                    style: const TextStyle(
                                      fontFamily: 'Courier New',
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.2),
                          ),
                        ),
                        child: const Icon(Icons.menu),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Recently Played Section (Isolated from position ticks)
            Selector<PlayerController, List<Track>>(
              selector: (_, p) => p.playbackHistory,
              builder: (context, playbackHistory, child) {
                if (playbackHistory.isEmpty) return const SizedBox();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECENT_LOGS',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: playbackHistory.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final track = playbackHistory[index];
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(
                              bottom: 8,
                            ), // Shadow space
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const FullPlayerScreen(),
                                  ),
                                );
                                // Play as playlist (Queue = History)
                                context.read<JamController>().playPlaylist(
                                  playbackHistory,
                                  initialIndex: index,
                                );
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thumbnail
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black12,
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                      child: NebulaImage(
                                        url: track.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        isThumbnail: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Title
                                  Text(
                                    track.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Courier New',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

            // Featured Section
            Text(
              'FEATURED_MIXES',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 16),

            // Grid of Mixes
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildMixCard(
                  context,
                  'NIGHTCORE_CODE',
                  Colors.purple,
                  'nightcore mix',
                ),
                _buildMixCard(
                  context,
                  'SYNTH_WAVE',
                  Colors.cyan,
                  'synthwave mix',
                ),
                _buildMixCard(
                  context,
                  'DEEP_FOCUS',
                  Colors.blue,
                  'deep focus music',
                ),
                _buildMixCard(
                  context,
                  'AMBIENT_LAB',
                  Colors.green,
                  'ambient space music',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixCard(
    BuildContext context,
    String title,
    Color accent,
    String query,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Initializing $title Sequence...'),
                duration: const Duration(seconds: 1),
                backgroundColor: accent,
              ),
            );
            final success = await context.read<JamController>().playMix(
              query,
            );
            // Note: playMix internally calls playPlaylist on PlayerController.
            // In a Jam, the host's queue is set but not broadcast track-by-track.
            // This is acceptable since mixes are local discovery features.
            if (!success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Connection Failed. Try on Desktop/Mobile.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.bolt, color: accent, size: 16),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
