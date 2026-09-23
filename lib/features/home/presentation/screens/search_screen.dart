import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/screens/full_player_screen.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';

typedef _SearchResultState = ({
  List<Track> searchResults,
  bool isSearching,
  List<String> searchHistory,
  String? activeTrackId,
  bool isBuffering,
});

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  String? _loadingTrackId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {});
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _searchController.text.trim() == trimmed) {
        context.read<PlayerController>().search(trimmed);
      }
    });
  }

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

          // Search Input with Loading Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Consumer<SettingsController>(
                  builder: (context, settings, _) {
                    return NebulaInput(
                      label: 'INPUT COMMAND',
                      controller: _searchController,
                      hintText: '> Search database...',
                      technicalSpec: 'MODE: QUERY // DB: ${settings.searchSource.publicLabel}',
                      suffixIcon: const Icon(Icons.search),
                      onChanged: _onSearchChanged,
                      onSubmitted: (query) {
                        _debounceTimer?.cancel();
                        if (query.trim().isNotEmpty) {
                          context.read<PlayerController>().search(query.trim());
                        }
                      },
                    );
                  },
                ),
                Selector<PlayerController, bool>(
                  selector: (_, p) => p.isSearching,
                  builder: (_, isSearching, __) {
                    if (!isSearching) return const SizedBox(height: 2);
                    return const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppTheme.nebulaPurple,
                        backgroundColor: Colors.transparent,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Results List - Isolated from audio playback position ticks
          Expanded(
            child: Selector<PlayerController, _SearchResultState>(
              selector: (_, p) => (
                searchResults: p.searchResults,
                isSearching: p.isSearching,
                searchHistory: p.searchHistory,
                activeTrackId: p.currentTrack?.id,
                isBuffering: p.isBuffering,
              ),
              builder: (context, state, child) {
                if (state.searchResults.isEmpty) {
                  if (state.searchHistory.isNotEmpty &&
                      _searchController.text.isEmpty &&
                      !state.isSearching) {
                    return _buildHistoryList(context, state.searchHistory);
                  }

                  if (state.isSearching) {
                    return const SizedBox(); // Handled by linear loader
                  }

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.radar,
                          size: 36,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '[NO_SIGNAL // ZERO_RESULTS]',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            color: Colors.white.withValues(alpha: 0.35),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96, left: 16, right: 16),
                  itemCount: state.searchResults.length,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    final video = state.searchResults[index];
                    final isBufferingCurrent =
                        state.isBuffering && state.activeTrackId == video.id;
                    final isLoading =
                        _loadingTrackId == video.id || isBufferingCurrent;
                    final isCurrent = state.activeTrackId == video.id;

                    return NebulaTrackTile(
                      track: video,
                      isCurrentTrack: isCurrent,
                      isPlaying: isCurrent && !isBufferingCurrent,
                      isLoading: isLoading,
                      indexNumber: (index + 1).toString().padLeft(2, '0'),
                      enableSwipeToQueue: true,
                      onSwipeQueue: () async {
                        await context.read<JamController>().addToQueue(video);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added "${video.title}" to queue'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isLoading
                                  ? Icons.hourglass_empty
                                  : (isCurrent ? Icons.volume_up : Icons.play_arrow),
                              color: isCurrent ? AppTheme.nebulaPurple : Colors.white,
                            ),
                            onPressed: isLoading
                                ? null
                                : () => _playTrack(context, video, openPlayer: false),
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add, color: Colors.white70),
                            onPressed: () => _showTrackMenu(context, video),
                          ),
                        ],
                      ),
                      onTap: isLoading
                          ? null
                          : () => _playTrack(context, video, openPlayer: true),
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

  Future<void> _playTrack(
    BuildContext context,
    Track video, {
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
    try {
      await context.read<JamController>().playTrack(video);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }

    if (context.mounted) {
      setState(() => _loadingTrackId = null);
    }
  }

  void _showTrackMenu(BuildContext context, Track track) {
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
          builder: (context, setSheetState) {
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
                        setSheetState(() {});
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
                      future: playlistCtrl.getPlaylistsContainingTrack(track.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
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
                                setSheetState(() {
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

  Widget _buildHistoryList(BuildContext context, List<String> searchHistory) {
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
                onPressed: () => context.read<PlayerController>().clearHistory(),
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
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: searchHistory.length,
            itemBuilder: (context, index) {
              final query = searchHistory[index];
              return ListTile(
                leading: Icon(
                  Icons.history,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                title: Text(
                  query,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  onPressed: () =>
                      context.read<PlayerController>().deleteHistoryItem(query),
                ),
                onTap: () {
                  _searchController.text = query;
                  context.read<PlayerController>().search(query);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
