import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

class HomeFeedScreen extends StatelessWidget {
  const HomeFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
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

            const SizedBox(height: 40),

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
            final success = await context.read<PlayerController>().playMix(
              query,
            );
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
