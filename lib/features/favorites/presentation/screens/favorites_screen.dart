import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/shared/widgets/widgets.dart';

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
                                  ).colorScheme.onSurface.withValues(alpha: 0.3),
                                ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          // Action Buttons Row
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
                                          .read<JamController>()
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
                                                .withValues(alpha: 0.5),
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.nebulaPurple,
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
                                              .read<JamController>()
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: favoritesCtrl.favorites.length,
                              itemBuilder: (context, index) {
                                final track = favoritesCtrl.favorites[index];

                                return Selector<PlayerController, (String?, bool)>(
                                  selector: (_, p) => (p.currentTrack?.id, p.isPlaying),
                                  builder: (_, playState, __) {
                                    final isCurrent = playState.$1 == track.id;
                                    final isPlaying = isCurrent && playState.$2;

                                    return NebulaTrackTile(
                                      track: track,
                                      isCurrentTrack: isCurrent,
                                      isPlaying: isPlaying,
                                      indexNumber: (index + 1).toString().padLeft(2, '0'),
                                      enableSwipeToQueue: true,
                                      onSwipeQueue: () async {
                                        await context
                                            .read<JamController>()
                                            .addToQueue(track);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text("Added to queue"),
                                              duration: Duration(seconds: 1),
                                            ),
                                          );
                                        }
                                      },
                                      enableSwipeToRemove: true,
                                      onSwipeRemove: () async {
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

                                        if (confirm == true && context.mounted) {
                                          favoritesCtrl.toggleFavorite(track);
                                        }
                                        return false;
                                      },
                                      trailing: Consumer<DownloadController>(
                                        builder: (context, downloader, _) {
                                          final isDownloaded =
                                              downloader.isDownloaded(track.id);
                                          final isDownloading =
                                              downloader.isDownloading(track.id);
                                          final progress =
                                              downloader.getProgress(track.id);

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
                                            .read<JamController>()
                                            .playPlaylist(
                                              favoritesCtrl.favorites,
                                              initialIndex: index,
                                              shuffle: _isShuffleEnabled,
                                            );
                                      },
                                    );
                                  },
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
