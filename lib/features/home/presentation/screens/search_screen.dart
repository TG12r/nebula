import 'package:flutter/material.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _loadingTrackId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEARCH',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(letterSpacing: -1.0),
                ),
                Text(
                  'DATABASE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),

          // Search & Results Section
          Expanded(
            child: Consumer<PlayerController>(
              builder: (context, player, child) {
                return Column(
                  children: [
                    // Search Input with Loading Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        children: [
                          NebulaInput(
                            label: 'INPUT COMMAND',
                            controller: _searchController,
                            hintText: '> Search database...',
                            technicalSpec: 'MODE: QUERY // DB: YT_PUBLIC',
                            suffixIcon: const Icon(Icons.search),
                            onSubmitted: (query) => player.search(query),
                          ),
                          if (player.isSearching)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: AppTheme.nebulaPurple,
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Results List
                    Expanded(
                      child: player.searchResults.isEmpty
                          ? (player.searchHistory.isNotEmpty &&
                                    _searchController.text.isEmpty &&
                                    !player.isSearching)
                                ? _buildHistoryList(context, player)
                                : Center(
                                    child: player.isSearching
                                        ? const SizedBox() // Handled by linear loader
                                        : Text(
                                            'NO DATA',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  fontFamily: 'Courier New',
                                                  color: Colors.white30,
                                                ),
                                          ),
                                  )
                          : ListView.builder(
                              itemCount: player.searchResults.length,
                              // Use keyboardDismissBehavior to dismiss keyboard on scroll (better UX)
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemBuilder: (context, index) {
                                final video = player.searchResults[index];
                                final isBufferingCurrent =
                                    player.isBuffering &&
                                    player.currentTrack?.id == video.id;
                                final isLoading =
                                    _loadingTrackId == video.id ||
                                    isBufferingCurrent;

                                return Dismissible(
                                  key: Key(video.id),
                                  direction: DismissDirection.startToEnd,
                                  background: Container(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20.0),
                                    color: AppTheme.nebulaPurple,
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.queue_music,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'ADD TO QUEUE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Courier New',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    if (direction ==
                                        DismissDirection.startToEnd) {
                                      await player.addToQueue(video);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Added "${video.title}" to queue',
                                          ),
                                          duration: const Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                    return false; // Don't remove from list
                                  },
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.black12,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Image.network(
                                            video.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, o, s) =>
                                                const Icon(Icons.music_note),
                                          ),
                                          if (isLoading)
                                            Container(
                                              color: Colors.black54,
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    title: Text(
                                      video.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontFamily: 'Courier New',
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    subtitle: Text(video.artist),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            isLoading
                                                ? Icons.hourglass_empty
                                                : Icons.play_arrow,
                                          ),
                                          onPressed: isLoading
                                              ? null
                                              : () => _playTrack(
                                                  context,
                                                  player,
                                                  video,
                                                  openPlayer: false,
                                                ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.playlist_add),
                                          onPressed: () =>
                                              _showTrackMenu(context, video),
                                        ),
                                      ],
                                    ),
                                    onTap: isLoading
                                        ? null
                                        : () => _playTrack(
                                            context,
                                            player,
                                            video,
                                            openPlayer: true,
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
    );
  }

  Future<void> _playTrack(
    BuildContext context,
    PlayerController player,
    dynamic video, {
    required bool openPlayer,
  }) async {
    setState(() => _loadingTrackId = video.id);

    // 1. Navigate Interface IMMEDIATELY (Optimistic)
    if (openPlayer) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FullPlayerScreen()),
      );
    }

    // 2. Start Playback Logic (Async/Heavy)
    // We do NOT await this before navigating.
    final error = await player.playYoutubeVideo(video);

    if (context.mounted) {
      setState(() => _loadingTrackId = null);

      if (error != null) {
        // Show error on whatever screen is top (Search or Player)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTrackMenu(BuildContext context, dynamic track) {
    final favoritesCtrl = context.read<FavoritesController>();
    final playlistCtrl = context.read<PlaylistController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cmfBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.zero),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "MANAGE TRACK",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Favorites Toggle
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.favorite,
                      color: AppTheme.nebulaPurple,
                    ),
                    title: const Text(
                      "LIKED SONGS",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Courier New',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Switch(
                      value: favoritesCtrl.isFavorite(track.id),
                      activeColor: AppTheme.nebulaPurple,
                      onChanged: (_) {
                        favoritesCtrl.toggleFavorite(track);
                        setState(() {}); // Refresh UI
                      },
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  const Text(
                    "PLAYLISTS",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'Courier New',
                    ),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: FutureBuilder<List<String>>(
                      future: playlistCtrl.getPlaylistsContainingTrack(
                        track.id,
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        final containingIds = snapshot.data!;

                        return ListView(
                          children: playlistCtrl.playlists.map((playlist) {
                            final isAdded = containingIds.contains(playlist.id);
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                playlist.name.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Courier New',
                                ),
                              ),
                              value: isAdded,
                              activeColor: AppTheme.nebulaPurple,
                              onChanged: (val) async {
                                if (val == true) {
                                  await playlistCtrl.addTrackToPlaylist(
                                    playlist.id,
                                    track,
                                  );
                                } else {
                                  await playlistCtrl.removeTrackFromPlaylist(
                                    playlist.id,
                                    track.id,
                                  );
                                }
                                // Force refresh of future?
                                // Ideally we setState, but future builder might not rerun.
                                // Simpler: Just setState inside this builder?
                                // FutureBuilder creates check once.
                                // We need to manage `containingIds` state manually for instant feedback.
                                setState(() {
                                  if (val == true) {
                                    containingIds.add(playlist.id);
                                  } else {
                                    containingIds.remove(playlist.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryList(BuildContext context, PlayerController player) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HISTORY',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
              TextButton(
                onPressed: () => player.clearHistory(),
                child: Text(
                  'CLEAR',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: player.searchHistory.length,
            itemBuilder: (context, index) {
              final query = player.searchHistory[index];
              return ListTile(
                leading: const Icon(
                  Icons.history,
                  size: 18,
                  color: Colors.white54,
                ),
                title: Text(
                  query,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    color: Colors.white70,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white30,
                  ),
                  onPressed: () => player.deleteHistoryItem(query),
                ),
                onTap: () {
                  _searchController.text = query;
                  player.search(query);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
