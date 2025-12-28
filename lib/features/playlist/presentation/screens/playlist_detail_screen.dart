import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUSTOM_PLAYLIST',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.blueAccent,
                                  letterSpacing: 1.0,
                                ),
                          ),
                          Text(
                            playlist.name.toUpperCase(),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  letterSpacing: -1.0,
                                  color: Colors.white,
                                ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: AppTheme.cmfDarkGrey,
                              title: const Text(
                                'DELETE PLAYLIST?',
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
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    'DELETE',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            if (context.mounted) {
                              await context
                                  .read<PlaylistController>()
                                  .deletePlaylist(playlist.id);
                              Navigator.pop(context);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Track List
                Expanded(
                  child: Consumer<PlaylistController>(
                    builder: (context, playlistCtrl, child) {
                      if (playlistCtrl.isLoadingDetails) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (playlistCtrl.currentPlaylistTracks.isEmpty) {
                        return Center(
                          child: Text(
                            "EMPTY PLAYLIST",
                            style: TextStyle(
                              color: Colors.white54,
                              fontFamily: 'Courier New',
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          // Action Buttons
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              children: [
                                // Play All
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.black,
                                    ),
                                    label: const Text(
                                      "PLAY ALL",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Courier New',
                                      ),
                                    ),
                                    onPressed: () {
                                      context
                                          .read<PlayerController>()
                                          .playPlaylist(
                                            playlistCtrl.currentPlaylistTracks,
                                          );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Download All
                                Consumer<DownloadController>(
                                  builder: (context, downloader, _) {
                                    return SizedBox(
                                      width: 60,
                                      height: 50, // Match typical button height
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.cmfDarkGrey,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            side: const BorderSide(
                                              color: Colors.white24,
                                            ),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.download_rounded,
                                        ),
                                        onPressed: () {
                                          downloader.downloadPlaylist(
                                            playlistCtrl.currentPlaylistTracks,
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Downloading playlist...",
                                              ),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // Tracks
                          Expanded(
                            child: ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount:
                                  playlistCtrl.currentPlaylistTracks.length,
                              onReorder: (oldIndex, newIndex) {
                                // Call controller to reorder
                                // playlistCtrl.reorder(oldIndex, newIndex);
                                // For now, implementing local reorder logic here or in controller
                                // Note: newIndex > oldIndex needs adjustment
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = playlistCtrl.currentPlaylistTracks
                                    .removeAt(oldIndex);
                                playlistCtrl.currentPlaylistTracks.insert(
                                  newIndex,
                                  item,
                                );
                                // TODO: Persist to DB
                              },
                              itemBuilder: (context, index) {
                                final track =
                                    playlistCtrl.currentPlaylistTracks[index];
                                // Key is required for ReorderableListView
                                return Container(
                                  key: ValueKey(track.id),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white10),
                                    color: Colors.white.withOpacity(0.05),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.white10,
                                      child: Image.network(
                                        track.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        cacheWidth:
                                            100, // Performance optimization
                                      ),
                                    ),
                                    title: Text(
                                      track.title.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Courier New',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Download Icon
                                        Consumer<DownloadController>(
                                          builder: (context, downloader, _) {
                                            final isDownloaded = downloader
                                                .isDownloaded(track.id);
                                            final isDownloading = downloader
                                                .isDownloading(track.id);
                                            final progress = downloader
                                                .getProgress(track.id);

                                            if (isDownloading) {
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 16.0,
                                                ),
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        value: progress,
                                                        strokeWidth: 2,
                                                        color: AppTheme
                                                            .nebulaPurple,
                                                      ),
                                                ),
                                              );
                                            }

                                            return IconButton(
                                              icon: Icon(
                                                isDownloaded
                                                    ? Icons.offline_pin
                                                    : Icons.download_outlined,
                                                size: 20,
                                                color: isDownloaded
                                                    ? AppTheme.nebulaPurple
                                                    : Colors.white24,
                                              ),
                                              onPressed: isDownloaded
                                                  ? null // Already downloaded
                                                  : () => downloader
                                                        .downloadTrack(track),
                                            );
                                          },
                                        ),
                                        // Drag Handle
                                        const Icon(
                                          Icons.drag_handle,
                                          color: Colors.white24,
                                        ),
                                      ],
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

          // MiniPlayer
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
