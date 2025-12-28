import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';

import 'package:nebula/features/player/presentation/widgets/mini_player.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        // Wrap in Stack
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      // ... (Rest of Header)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PLAYLIST_01',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.nebulaPurple,
                                  letterSpacing: 1.0,
                                ),
                          ),
                          Text(
                            'FAVORITES',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  letterSpacing: -1.0,
                                  color: Colors.white,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ... (Consumer List)
                Expanded(
                  child: Consumer<FavoritesController>(
                    builder: (context, favoritesCtrl, child) {
                      if (favoritesCtrl.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (favoritesCtrl.favorites.isEmpty) {
                        // ... Empty State
                        return Center(
                          child: Text(
                            'NO TRACKS SAVED',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontFamily: 'Courier New',
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.3),
                                ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          80,
                        ), // Add bottom padding for MiniPlayer
                        itemCount: favoritesCtrl.favorites.length,
                        itemBuilder: (context, index) {
                          // ... List Item ...
                          final track = favoritesCtrl.favorites[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.1),
                              ),
                              color: Colors.white.withOpacity(0.05),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(8),
                              leading: Container(
                                width: 50,
                                height: 50,
                                color: AppTheme.cmfDarkGrey,
                                child: track.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        track.thumbnailUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(
                                        Icons.music_note,
                                        color: Colors.white,
                                      ),
                              ),
                              title: Text(
                                track.title.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Courier New',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                track.artist.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Text(
                                  '<3',
                                  style: TextStyle(
                                    fontFamily: 'Courier New',
                                    color: AppTheme.nebulaPurple,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.0,
                                    fontSize: 18,
                                  ),
                                ),
                                onPressed: () {
                                  favoritesCtrl.toggleFavorite(track);
                                },
                              ),
                              onTap: () {
                                context
                                    .read<PlayerController>()
                                    .playYoutubeVideo(track.id);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // MiniPlayer Overlay
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }
}
