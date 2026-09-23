import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Select only core metadata so MiniPlayer does not rebuild on position ticks
    final currentTitle = context.select<PlayerController, String?>((p) => p.currentTitle);
    if (currentTitle == null) {
      return const SizedBox.shrink();
    }

    final currentArtist = context.select<PlayerController, String?>((p) => p.currentArtist);
    final currentThumbnail = context.select<PlayerController, String?>((p) => p.currentThumbnail);
    final isPlaying = context.select<PlayerController, bool>((p) => p.isPlaying);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const FullPlayerScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  const begin = Offset(0.0, 1.0);
                  const end = Offset.zero;
                  const curve = Curves.easeInOutQuart;

                  var tween = Tween(
                    begin: begin,
                    end: end,
                  ).chain(CurveTween(curve: curve));

                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
          ),
        );
      },
      child: Container(
        height: 70,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.cmfBlack,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.0,
            ),
          ),
        ),
        child: Stack(
          children: [
            // Discrete Top Progress Bar - Only this Selector rebuilds during playback
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Selector<PlayerController, (int, int)>(
                selector: (_, p) => (p.position.inMilliseconds, p.duration.inMilliseconds),
                builder: (_, times, __) {
                  final pos = times.$1;
                  final dur = times.$2;
                  final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.0,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.nebulaPurple),
                  );
                },
              ),
            ),

            // Content
            Row(
              children: [
                // Album Art
                Hero(
                  tag: 'album_art',
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: currentThumbnail != null
                        ? NebulaImage(
                            url: currentThumbnail,
                            fit: BoxFit.cover,
                            isThumbnail: true,
                          )
                        : Container(
                            color: AppTheme.cmfDarkGrey,
                            child: const Center(
                              child: Icon(
                                FontAwesomeIcons.music,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                  ),
                ),

                // Info & Controls
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title (Marquee effect for long titles)
                        NebulaMarquee(
                          text: currentTitle.toUpperCase(),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier New',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentArtist?.toUpperCase() ?? 'UNKNOWN ARTIST',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Jam indicator
                Consumer<JamController>(
                  builder: (context, jam, _) {
                    if (!jam.isInJam) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppTheme.nebulaPurple.withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'JAM',
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: AppTheme.nebulaPurple,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    );
                  },
                ),

                // Play/Pause Button
                IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    context.read<JamController>().togglePlay();
                  },
                  icon: Icon(
                    isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                    color: AppTheme.nebulaPurple,
                    size: 20,
                  ),
                  splashRadius: 20,
                ),

                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
