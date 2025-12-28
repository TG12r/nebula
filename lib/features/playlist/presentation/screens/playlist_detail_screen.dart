import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';

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
                          // Play Button Header
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 8.0,
                            ),
                            child: SizedBox(
                              width: double.infinity,
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
                                  context.read<PlayerController>().playPlaylist(
                                    playlistCtrl.currentPlaylistTracks,
                                  );
                                },
                              ),
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
                                    // Drag handle is automatic on trailing, but we can customize
                                    trailing: const Icon(
                                      Icons.drag_handle,
                                      color: Colors.white24,
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
