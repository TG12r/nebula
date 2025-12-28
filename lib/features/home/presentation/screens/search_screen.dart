import 'package:flutter/material.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    // Note: Background and MiniPlayer are now handled by MainScreen
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
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
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Search & Results Section
          Expanded(
            child: Consumer<PlayerController>(
              builder: (context, player, child) {
                return Column(
                  children: [
                    // Search Input
                    NebulaInput(
                      label: 'INPUT COMMAND',
                      controller: _searchController,
                      hintText: '> Search database...',
                      technicalSpec: 'MODE: QUERY // DB: YT_PUBLIC',
                      suffixIcon: player.isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.search),
                      onSubmitted: (query) {
                        player.search(query);
                      },
                    ),

                    const SizedBox(height: 20),

                    // Results List
                    Expanded(
                      child: player.searchResults.isEmpty
                          ? Center(
                              child: Text(
                                'NO DATA',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      fontFamily: 'Courier New',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                    ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: player.searchResults.length,
                              itemBuilder: (context, index) {
                                final video = player.searchResults[index];
                                return ListTile(
                                  leading: Container(
                                    width: 50,
                                    height: 50,
                                    color: Colors.black12,
                                    child: Image.network(
                                      video.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, o, s) =>
                                          const Icon(Icons.music_note),
                                    ),
                                  ),
                                  title: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Courier New',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(video.artist),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.play_arrow),
                                    onPressed: () async {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Initializing Stream connection...',
                                          ),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                      final error = await player
                                          .playYoutubeVideo(video.id);
                                      if (mounted && error != null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(error),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
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
}
