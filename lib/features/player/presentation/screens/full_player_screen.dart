import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  @override
  @override
  Widget build(BuildContext context) {
    // We rely on Selectors for updates, so we don't need context.watch here
    // keeping the tree static where possible.

    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        children: [
          // Background Grid (Static)
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Colors.white.withOpacity(0.15),
                step: 24.0,
                radius: 1.5,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'NOW PLAYING',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.nebulaPurple,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                const Spacer(),

                // Artwork (Selector for thumbnail only)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Hero(
                    tag: 'album_art',
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.cmfDarkGrey,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.nebulaPurple.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Selector<PlayerController, String?>(
                          selector: (_, p) => p.currentThumbnail,
                          builder: (_, thumbnail, __) {
                            return thumbnail != null
                                ? Image.network(thumbnail, fit: BoxFit.cover)
                                : const Center(
                                    child: Icon(
                                      FontAwesomeIcons.music,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Info Section (Selector for Title/Artist)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Selector<PlayerController, String?>(
                        selector: (_, p) => p.currentTitle,
                        builder: (_, title, __) => Text(
                          title?.toUpperCase() ?? 'UNKNOWN TRACK',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                                letterSpacing: -0.5,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Selector<PlayerController, String?>(
                        selector: (_, p) => p.currentArtist,
                        builder: (_, artist, __) => Text(
                          artist?.toUpperCase() ?? 'UNKNOWN ARTIST',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white.withOpacity(0.6),
                                fontFamily: 'Courier New',
                                letterSpacing: 1.0,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Seek Bar (Selector for Position/Duration)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Selector<PlayerController, (Duration, Duration)>(
                    selector: (_, p) => (p.position, p.duration),
                    builder: (_, data, __) {
                      final position = data.$1;
                      final duration = data.$2;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white.withOpacity(0.1),
                              thumbColor: Colors.white,
                              trackHeight: 2.0,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14.0,
                              ),
                            ),
                            child: Slider(
                              value: position.inSeconds.toDouble().clamp(
                                0.0,
                                duration.inSeconds.toDouble(),
                              ),
                              max: duration.inSeconds.toDouble() > 0
                                  ? duration.inSeconds.toDouble()
                                  : 1.0,
                              onChanged: (value) {
                                context.read<PlayerController>().seek(
                                  Duration(seconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // Controls (Selector for IsPlaying)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () {},
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.nebulaPurple.withOpacity(0.2),
                        border: Border.all(color: AppTheme.nebulaPurple),
                      ),
                      child: Selector<PlayerController, bool>(
                        selector: (_, p) => p.isPlaying,
                        builder: (_, isPlaying, __) {
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: AppTheme.nebulaPurple,
                              size: 40,
                            ),
                            onPressed: () =>
                                context.read<PlayerController>().togglePlay(),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }
}
