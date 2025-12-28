import 'package:flutter/material.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Custom App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NEBULA',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(letterSpacing: -1.0),
                          ),
                          Text(
                            'ONLINE',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: 1.0,
                                ),
                          ),
                        ],
                      ),
                      // TODO: Add Profile/Settings Icon
                      Container(
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
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Content Placeholder
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'YOUR LIBRARY',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'IS EMPTY',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                              ),
                        ),
                        const SizedBox(height: 32),
                        NebulaButton(
                          label: 'DISCOVER',
                          technicalLabel: 'ACT: BROWSE / MODE: PUBLIC',
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Loading audio stream...'),
                              ),
                            );
                            // NCS - Fearless (Static Video)
                            context.read<PlayerController>().playYoutubeVideo(
                              'bFMeA03Q9k8',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Mini Player (Pinned to bottom)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // Wrap in SafeArea to respect system navigation bar (III O <)
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }
}
