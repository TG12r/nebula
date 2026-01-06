import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
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
                            widget.playlist.name.toUpperCase(),
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
                                  .deletePlaylist(widget.playlist.id);
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
                        return const Center(
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
                          // Action Buttons Row (Like Spotify/Apple Music)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment
                                  .end, // Align bottoms so label floats on top
                              children: [
                                // Left Side: Download, Add/Other actions
                                Consumer<DownloadController>(
                                  builder: (context, downloader, _) {
                                    return Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.download_rounded,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                          onPressed: () {
                                            downloader.downloadPlaylist(
                                              playlistCtrl
                                                  .currentPlaylistTracks,
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
                                        // Placeholder for 'Like' or 'Add'
                                        IconButton(
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                            color: Colors.white54,
                                            size: 28,
                                          ),
                                          onPressed: () {
                                            _showAddTracksModal(context);
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                const Spacer(),

                                IconButton(
                                  icon: Icon(
                                    Icons.shuffle,
                                    color: _isShuffleEnabled
                                        ? AppTheme.nebulaPurple
                                        : Colors.white, // Toggle Color
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isShuffleEnabled = !_isShuffleEnabled;
                                    });

                                    // If active, shuffle the remaining queue immediately
                                    if (_isShuffleEnabled) {
                                      // Optional: Check if we are currently playing *this* playlist?
                                      // User request: "Si empiezo... y lo activo se haga shuffle a la cola"
                                      // Safest to just call shuffleQueue() which shuffles "Next Up".
                                      // It won't hurt if playing something else, just shuffles the user's queue.
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
                                // Compact Industrial Play Button
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "BTN: PLAY_LIST",
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
                                      height:
                                          48, // Slightly shorter than standard 56
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.nebulaPurple,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius
                                                .zero, // Sharp corners like NebulaButton
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                        ),
                                        onPressed: () {
                                          context
                                              .read<PlayerController>()
                                              .playPlaylist(
                                                playlistCtrl
                                                    .currentPlaylistTracks,
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
                                      return false; // Don't remove from list
                                    } else if (direction ==
                                        DismissDirection.endToStart) {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: AppTheme.cmfDarkGrey,
                                          title: const Text(
                                            'REMOVE TRACK?',
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
                                          try {
                                            await context
                                                .read<PlaylistController>()
                                                .removeTrackFromPlaylist(
                                                  widget.playlist.id,
                                                  track.id,
                                                );
                                            // Since controller updates correctly now, we can return false
                                            // and let the consumer rebuild.
                                            // Or return true if we want the local list removal animation.
                                            // But controller calls notifyListeners() which rebuilds this list.
                                            // If we return true here, UI removes item THEN Consumer rebuilds.
                                            // It's safer to return false and let Consumer update.
                                            return false;
                                          } catch (e) {
                                            debugPrint("Error removing: $e");
                                            return false;
                                          }
                                        }
                                      }
                                      return false;
                                    }
                                    return false;
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white10),
                                      color: Colors.white.withOpacity(0.05),
                                    ),
                                    child: ListTile(
                                      onTap: () {
                                        context
                                            .read<PlayerController>()
                                            .playPlaylist(
                                              playlistCtrl
                                                  .currentPlaylistTracks,
                                              initialIndex: index,
                                            );
                                      },
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
                                                  padding:
                                                      const EdgeInsets.only(
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

  void _showAddTracksModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.zero), // Industrial
      ),
      builder: (context) {
        return _AddTracksModal(playlist: widget.playlist);
      },
    );
  }
}

class _AddTracksModal extends StatefulWidget {
  final Playlist playlist;

  const _AddTracksModal({required this.playlist});

  @override
  State<_AddTracksModal> createState() => _AddTracksModalState();
}

class _AddTracksModalState extends State<_AddTracksModal> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We use a high viewport fraction or fixed height for the modal
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DATABASE QUERY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      'ADD TRACKS',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: -1.0,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Consumer<PlayerController>(
              builder: (context, player, _) {
                return Column(
                  children: [
                    NebulaInput(
                      label: 'SEARCH TRACKS',
                      controller: _searchController,
                      hintText: '> Enter song name...',
                      technicalSpec: 'TARGET: ${widget.playlist.name}',
                      onSubmitted: (query) => player.search(query),
                    ),
                    if (player.isSearching)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Results
          Expanded(
            child: Consumer<PlayerController>(
              builder: (context, player, _) {
                if (player.searchResults.isEmpty) {
                  return Center(
                    child: Text(
                      player.isSearching ? "SCANNING..." : "NO DATA",
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: player.searchResults.length,
                  itemBuilder: (context, index) {
                    final track = player.searchResults[index];
                    // Listen to playlist changes to update icon instantly
                    final playlistCtrl = context.watch<PlaylistController>();
                    final isAdded = playlistCtrl.currentPlaylistTracks.any(
                      (t) => t.id == track.id,
                    );

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        color: Colors.white10,
                        child: Image.network(
                          track.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, o, s) =>
                              const Icon(Icons.music_note),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Courier New',
                          fontWeight: FontWeight.bold,
                          color: isAdded
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5)
                              : null, // Dim title if added
                        ),
                      ),
                      subtitle: Text(
                        track.artist,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface
                              .withOpacity(isAdded ? 0.3 : 0.6),
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isAdded ? Icons.check : Icons.add_circle_outline,
                        ),
                        color: isAdded
                            ? Theme.of(context).colorScheme.primary.withOpacity(
                                0.5,
                              ) // Dimmed primary for check
                            : Theme.of(context).colorScheme.primary,
                        onPressed: isAdded
                            ? null // Disable if added
                            : () async {
                                try {
                                  await playlistCtrl.addTrackToPlaylist(
                                    widget.playlist.id,
                                    track,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "ADDED: ${track.title.toUpperCase()}",
                                        ),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("ERROR: $e"),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
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
    );
  }
}
