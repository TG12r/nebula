import 'package:flutter/material.dart';

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
                _buildMixCard(context, 'LOFI_CODE', Colors.purple),
                _buildMixCard(context, 'SYNTH_WAVE', Colors.cyan),
                _buildMixCard(context, 'DEEP_FOCUS', Colors.blue),
                _buildMixCard(context, 'AMBIENT_LAB', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixCard(BuildContext context, String title, Color accent) {
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
          onTap: () {
            // Trigger mix
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
