import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/playlist/presentation/screens/playlist_detail_screen.dart'; // We will create this next

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIBRARY',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(letterSpacing: -1.0),
                    ),
                    Text(
                      'YOUR_COLLECTIONS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.add,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => _showCreatePlaylistDialog(context),
                ),
              ],
            ),
          ),

          Expanded(
            child: Consumer<PlaylistController>(
              builder: (context, playlistCtrl, child) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  children: [
                    // Favorites Card (Always First)
                    _buildCollectionCard(
                      context,
                      title: 'LIKED SONGS',
                      subtitle: 'AUTO_PLAYLIST // <3',
                      color: AppTheme.nebulaPurple,
                      icon: Icons.favorite,
                      isSpecial: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FavoritesScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // User Playlists
                    ...playlistCtrl.playlists.map((playlist) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _buildCollectionCard(
                          context,
                          title: playlist.name.toUpperCase(),
                          subtitle:
                              'CUSTOM_PLAYLIST // ${playlist.trackCount} TRACKS',
                          color: Colors.blueAccent,
                          icon: Icons.album,
                          onTap: () {
                            // Navigate into detail
                            context
                                .read<PlaylistController>()
                                .loadPlaylistDetails(playlist.id);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlaylistDetailScreen(playlist: playlist),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),

                    if (playlistCtrl.playlists.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 32.0),
                          child: Text(
                            "CREATE A PLAYLIST TO START",
                            style: TextStyle(
                              fontFamily: 'Courier New',
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cmfDarkGrey,
        title: const Text(
          'NEW PLAYLIST',
          style: TextStyle(fontFamily: 'Courier New', color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'PLAYLIST NAME',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<PlaylistController>().createPlaylist(
                  controller.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text(
              'CREATE',
              style: TextStyle(color: AppTheme.nebulaPurple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    bool isSpecial = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cmfDarkGrey,
          border: Border.all(
            color: Colors.white.withOpacity(isSpecial ? 0.2 : 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Center(
                child: Text(
                  icon == Icons.favorite ? '<3' : '[P]',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: -2.0,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.3),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
