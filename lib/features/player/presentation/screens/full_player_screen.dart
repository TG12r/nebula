import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  @override
  Widget build(BuildContext context) {
    // We rely on Selectors for updates, so we don't need context.watch here
    // keeping the tree static where possible.

    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        children: [
          // Background Grid (Static)
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Colors.white.withOpacity(0.15),
                step: 24.0,
                radius: 1.5,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'NOW PLAYING',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.nebulaPurple,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                const Spacer(),

                Expanded(
                  flex: 4,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 350,
                          maxHeight: 350,
                        ),
                        child: Hero(
                          tag: 'album_art',
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppTheme.cmfDarkGrey,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.nebulaPurple.withOpacity(
                                      0.2,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Selector<PlayerController, String?>(
                                selector: (_, p) => p.currentThumbnail,
                                builder: (_, thumbnail, __) {
                                  return thumbnail != null
                                      ? Image.network(
                                          thumbnail,
                                          fit: BoxFit.cover,
                                        )
                                      : const Center(
                                          child: Icon(
                                            FontAwesomeIcons.music,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Info Section (Selector for Title/Artist)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Selector<PlayerController, String?>(
                        selector: (_, p) => p.currentTitle,
                        builder: (_, title, __) => Text(
                          title?.toUpperCase() ?? 'UNKNOWN TRACK',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                                letterSpacing: -0.5,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Selector<PlayerController, String?>(
                        selector: (_, p) => p.currentArtist,
                        builder: (_, artist, __) => Text(
                          artist?.toUpperCase() ?? 'UNKNOWN ARTIST',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white.withOpacity(0.6),
                                fontFamily: 'Courier New',
                                letterSpacing: 1.0,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Seek Bar (Selector for Position/Duration)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Selector<PlayerController, (Duration, Duration)>(
                    selector: (_, p) => (p.position, p.duration),
                    builder: (_, data, __) {
                      final position = data.$1;
                      final duration = data.$2;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white.withOpacity(0.1),
                              thumbColor: Colors.white,
                              trackHeight: 2.0,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14.0,
                              ),
                            ),
                            child: Slider(
                              value: position.inSeconds.toDouble().clamp(
                                0.0,
                                duration.inSeconds.toDouble(),
                              ),
                              max: duration.inSeconds.toDouble() > 0
                                  ? duration.inSeconds.toDouble()
                                  : 1.0,
                              onChanged: (value) {
                                context.read<PlayerController>().seek(
                                  Duration(seconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // Controls (Selector for IsPlaying)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Download Button
                    Consumer<DownloadController>(
                      builder: (context, downloader, _) {
                        final track = context
                            .read<PlayerController>()
                            .currentTrack;
                        if (track == null)
                          return const SizedBox(width: 48); // Placeholder

                        final isDownloaded = downloader.isDownloaded(track.id);
                        final isDownloading = downloader.isDownloading(
                          track.id,
                        );
                        final progress = downloader.getProgress(track.id);

                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                isDownloaded
                                    ? Icons.offline_pin
                                    : Icons.download,
                                color: isDownloaded
                                    ? AppTheme.nebulaPurple
                                    : (isDownloading
                                          ? Colors.white38
                                          : Colors.white),
                                size: 22,
                              ),
                              onPressed: isDownloaded
                                  ? () => downloader.deleteTrack(track.id)
                                  : (isDownloading
                                        ? null
                                        : () =>
                                              downloader.downloadTrack(track)),
                            ),
                            if (isDownloading)
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 2,
                                  color: AppTheme.nebulaPurple,
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    // Like Button
                    Consumer2<PlayerController, FavoritesController>(
                      builder: (context, player, favorites, _) {
                        final track = player.currentTrack;
                        final isLiked =
                            track != null && favorites.isFavorite(track.id);
                        return IconButton(
                          icon: Text(
                            '<3',
                            style: TextStyle(
                              fontFamily: 'Courier New',
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.0,
                              fontSize: 22,
                              color: isLiked
                                  ? AppTheme.nebulaPurple
                                  : Colors.white,
                            ),
                          ),
                          onPressed: () {
                            if (track != null) {
                              if (!isLiked) {
                                // Will be added to favorites, show modal
                                favorites.toggleFavorite(track);
                                _showAddToPlaylistModal(context, track);
                              } else {
                                // Will be removed
                                favorites.toggleFavorite(track);
                              }
                            }
                          },
                        );
                      },
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () =>
                          context.read<PlayerController>().skipToPrevious(),
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.nebulaPurple.withOpacity(0.2),
                        border: Border.all(color: AppTheme.nebulaPurple),
                      ),
                      child: Selector<PlayerController, bool>(
                        selector: (_, p) => p.isPlaying,
                        builder: (_, isPlaying, __) {
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: AppTheme.nebulaPurple,
                              size: 40,
                            ),
                            onPressed: () =>
                                context.read<PlayerController>().togglePlay(),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () =>
                          context.read<PlayerController>().skipToNext(),
                    ),

                    // Balance Spacer
                    const SizedBox(width: 48),
                  ],
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),

          // Queue Drawer at Bottom (Draggable)
          DraggableScrollableSheet(
            initialChildSize: 0.15, // Increased visibility
            minChildSize: 0.12,
            maxChildSize: 0.6,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.cmfDarkGrey.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Consumer<PlayerController>(
                  builder: (context, player, _) {
                    final queue = player.queue;

                    return CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        // Handle & Header
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Handle
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16.0,
                                  ),
                                  child: Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),

                              // Header
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'UP NEXT',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppTheme.nebulaPurple,
                                            letterSpacing: 2.0,
                                          ),
                                    ),
                                    const Spacer(),
                                    // Could add "Clear Queue" here
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Queue List or Empty State
                        if (queue.isEmpty)
                          SliverFillRemaining(
                            child: Center(
                              child: Text(
                                'Queue is empty',
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final track = queue[index];
                              final isCurrent =
                                  track.id == player.currentTrack?.id;

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    track.thumbnailUrl,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: Colors.white12),
                                  ),
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? AppTheme.nebulaPurple
                                        : Colors.white,
                                    fontFamily: 'Courier New',
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  track.artist,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.white24,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      player.removeFromQueue(index),
                                ),
                              );
                            }, childCount: queue.length),
                          ),

                        // Bottom Padding for safe scrolling
                        const SliverToBoxAdapter(child: SizedBox(height: 50)),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  void _showAddToPlaylistModal(BuildContext context, dynamic track) {
    final playlistCtrl = context.read<PlaylistController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cmfBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.zero),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: MediaQuery.of(context).size.height * 0.5,
              decoration: BoxDecoration(
                color: AppTheme.cmfDarkGrey,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppTheme.nebulaPurple.withOpacity(0.3),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "MANAGE TRACK",
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.white, letterSpacing: -1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
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
                    trailing: Consumer<FavoritesController>(
                      builder: (context, favs, _) {
                        return Switch(
                          value: favs.isFavorite(track.id),
                          activeColor: AppTheme.nebulaPurple,
                          onChanged: (_) {
                            favs.toggleFavorite(track);
                          },
                        );
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
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
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
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Added to ${playlist.name}",
                                        ),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } else {
                                  await playlistCtrl.removeTrackFromPlaylist(
                                    playlist.id,
                                    track.id,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Removed from ${playlist.name}",
                                        ),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                }
                                // Update local state for immediate feedback
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
}
