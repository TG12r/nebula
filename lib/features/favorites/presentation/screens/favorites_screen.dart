import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';

import 'package:nebula/features/player/presentation/widgets/mini_player.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isShuffleEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
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
                      Expanded(
                        child: Column(
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
                      ),
                    ],
                  ),
                ),

                // Consumer List
                Expanded(
                  child: Consumer<FavoritesController>(
                    builder: (context, favoritesCtrl, child) {
                      if (favoritesCtrl.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (favoritesCtrl.favorites.isEmpty) {
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

                      return Column(
                        children: [
                          // Action Buttons Row (Like PlaylistDetailScreen)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Download All
                                Consumer<DownloadController>(
                                  builder: (context, downloader, _) {
                                    return IconButton(
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      onPressed: () {
                                        downloader.downloadPlaylist(
                                          favoritesCtrl.favorites,
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "Downloading favorites...",
                                            ),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),

                                const Spacer(),

                                IconButton(
                                  icon: Icon(
                                    Icons.shuffle,
                                    color: _isShuffleEnabled
                                        ? AppTheme.nebulaPurple
                                        : Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isShuffleEnabled = !_isShuffleEnabled;
                                    });

                                    if (_isShuffleEnabled) {
                                      context
                                          .read<PlayerController>()
                                          .shuffleQueue();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text("Queue Shuffled"),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                // Play All Button
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "BTN: PLAY_FAVS",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 10,
                                            letterSpacing: 1.0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.5),
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.nebulaPurple,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.zero,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                        ),
                                        onPressed: () {
                                          context
                                              .read<PlayerController>()
                                              .playPlaylist(
                                                favoritesCtrl.favorites,
                                                shuffle: _isShuffleEnabled,
                                              );
                                        },
                                        child: const Text(
                                          "PLAY ALL",
                                          style: TextStyle(
                                            fontFamily: 'Courier New',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: favoritesCtrl.favorites.length,
                              itemBuilder: (context, index) {
                                final track = favoritesCtrl.favorites[index];
                                return Dismissible(
                                  key: ValueKey(track.id),
                                  direction: DismissDirection.horizontal,
                                  background: Container(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    color: Colors.green,
                                    child: const Icon(
                                      Icons.queue_music,
                                      color: Colors.white,
                                    ),
                                  ),
                                  secondaryBackground: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    color: Colors.red,
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    if (direction ==
                                        DismissDirection.startToEnd) {
                                      context
                                          .read<PlayerController>()
                                          .addToQueue(track);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text("Added to queue"),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                      return false;
                                    } else if (direction ==
                                        DismissDirection.endToStart) {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: AppTheme.cmfDarkGrey,
                                          title: const Text(
                                            'REMOVE FROM FAVORITES?',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'Courier New',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text(
                                                'CANCEL',
                                                style: TextStyle(
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text(
                                                'REMOVE',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        if (context.mounted) {
                                          favoritesCtrl.toggleFavorite(track);
                                          // Toggle removes it from list immediately via NotifyListeners
                                          // So we return false to avoid Dismissible confusion, or true if we handle it
                                          // Just like Playlist, false is safer with Consumer rebuild
                                          return false;
                                        }
                                      }
                                      return false;
                                    }
                                    return false;
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.1),
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
                                      trailing: Consumer<DownloadController>(
                                        builder: (context, downloader, _) {
                                          final isDownloaded = downloader
                                              .isDownloaded(track.id);
                                          final isDownloading = downloader
                                              .isDownloading(track.id);
                                          final progress = downloader
                                              .getProgress(track.id);

                                          if (isDownloading) {
                                            return SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                value: progress,
                                                strokeWidth: 2,
                                                color: AppTheme.nebulaPurple,
                                              ),
                                            );
                                          }

                                          return IconButton(
                                            icon: Icon(
                                              isDownloaded
                                                  ? Icons.offline_pin
                                                  : Icons.download_outlined,
                                              color: isDownloaded
                                                  ? AppTheme.nebulaPurple
                                                  : Colors.white54,
                                            ),
                                            onPressed: isDownloaded
                                                ? null
                                                : () => downloader
                                                      .downloadTrack(track),
                                          );
                                        },
                                      ),
                                      onTap: () {
                                        context
                                            .read<PlayerController>()
                                            .playPlaylist(
                                              favoritesCtrl.favorites,
                                              initialIndex: index,
                                              shuffle: _isShuffleEnabled,
                                            );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
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
