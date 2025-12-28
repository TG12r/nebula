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
                            'EMPTY PLAYLIST',
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: playlistCtrl.currentPlaylistTracks.length,
                        itemBuilder: (context, index) {
                          final track =
                              playlistCtrl.currentPlaylistTracks[index];
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
                              // Remove from Playlist button (Optional)
                              // trailing: IconButton(...)
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
