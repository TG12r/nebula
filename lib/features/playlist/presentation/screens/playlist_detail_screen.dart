import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
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
                      Expanded(
                        child: Column(
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
                      ),
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
                          // Action Buttons Row
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
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

                          // Reorderable Track List
                          Expanded(
                            child: ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount:
                                  playlistCtrl.currentPlaylistTracks.length,
                              onReorder: (oldIndex, newIndex) {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = playlistCtrl.currentPlaylistTracks
                                    .removeAt(oldIndex);
                                playlistCtrl.currentPlaylistTracks.insert(
                                  newIndex,
                                  item,
                                );
                              },
                              itemBuilder: (context, index) {
                                final track =
                                    playlistCtrl.currentPlaylistTracks[index];

                                return Selector<PlayerController, (String?, bool)>(
                                  key: ValueKey('playlist_track_${track.id}_$index'),
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

                                        if (confirm == true && context.mounted) {
                                          try {
                                            await context
                                                .read<PlaylistController>()
                                                .removeTrackFromPlaylist(
                                                  widget.playlist.id,
                                                  track.id,
                                                );
                                          } catch (e) {
                                            debugPrint("Error removing: $e");
                                          }
                                        }
                                        return false;
                                      },
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                                    right: 8.0,
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
                                                    ? null
                                                    : () => downloader
                                                          .downloadTrack(track),
                                              );
                                            },
                                          ),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: const Padding(
                                              padding: EdgeInsets.only(
                                                left: 4.0,
                                                right: 8.0,
                                              ),
                                              child: Icon(
                                                Icons.drag_handle,
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        context
                                            .read<JamController>()
                                            .playPlaylist(
                                              playlistCtrl.currentPlaylistTracks,
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
        borderRadius: BorderRadius.vertical(top: Radius.zero),
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
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _searchController.text.trim() == trimmed) {
        context.read<PlayerController>().search(trimmed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      onChanged: _onSearchChanged,
                      onSubmitted: (query) {
                        _debounceTimer?.cancel();
                        player.search(query.trim());
                      },
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
                        ).colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
                  itemCount: player.searchResults.length,
                  itemBuilder: (context, index) {
                    final track = player.searchResults[index];
                    final playlistCtrl = context.watch<PlaylistController>();
                    final isAdded = playlistCtrl.currentPlaylistTracks.any(
                      (t) => t.id == track.id,
                    );

                    return NebulaTrackTile(
                      track: track,
                      trailing: IconButton(
                        icon: Icon(
                          isAdded ? Icons.check : Icons.add_circle_outline,
                        ),
                        color: isAdded
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.primary,
                        onPressed: isAdded
                            ? null
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
