import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LIBRARY',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(letterSpacing: -1.0),
            ),
            Text(
              'PERSONAL_DB',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            Center(
              child: Text(
                'NO DATA LOGGED',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: 'Courier New',
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
