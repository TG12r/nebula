import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the controller
    final controller = context.watch<PlayerController>();

    // If nothing is playing/loaded, hide the player (zero height)
    // This keeps the tree clean and "lightweight" visually
    if (controller.currentTitle == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
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
        decoration: const BoxDecoration(
          color: AppTheme.cmfBlack,
          border: Border(
            top: BorderSide(color: AppTheme.nebulaPurple, width: 2.0),
          ),
        ),
        child: Row(
          children: [
            // Album Art Placeholder / Actual Image
            Hero(
              tag: 'album_art',
              child: AspectRatio(
                aspectRatio: 1.0,
                child: controller.currentThumbnail != null
                    ? Image.network(
                        controller.currentThumbnail!,
                        fit: BoxFit.cover,
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
                    // Title (Marquee effect simulation with TextOverflow for now)
                    Text(
                      controller.currentTitle?.toUpperCase() ?? 'UNKNOWN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier New',
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.currentArtist?.toUpperCase() ??
                          'UNKNOWN ARTIST',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Play/Pause Button
            IconButton(
              onPressed: controller.togglePlay,
              icon: Icon(
                controller.isPlaying
                    ? FontAwesomeIcons.pause
                    : FontAwesomeIcons.play,
                color: AppTheme.nebulaPurple,
                size: 20,
              ),
              splashRadius: 20,
            ),

            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
