import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:nebula/features/playlist/domain/entities/playlist.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/playlist/presentation/screens/playlist_detail_screen.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        children: [
          // Background dot grid
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: GridPainter(
                  color: Colors.white.withValues(alpha: 0.12),
                  step: 24.0,
                  radius: 1.5,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header CMF
                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LIBRARY',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  letterSpacing: -1.0,
                                  fontFamily: 'Courier New',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Consumer<PlaylistController>(
                            builder: (context, playlistCtrl, _) {
                              return Text(
                                'YOUR_COLLECTIONS // [ORDER: ${_getSortLabel(playlistCtrl.sortType)}]',
                                style: TextStyle(
                                  fontFamily: 'Courier New',
                                  color: AppTheme.nebulaPurple,
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Botón Organizar / Ordenar
                          Consumer<PlaylistController>(
                            builder: (context, playlistCtrl, _) {
                              return InkWell(
                                onTap: () => _showSortBottomSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cmfDarkGrey,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sort, size: 14, color: AppTheme.nebulaPurple),
                                      const SizedBox(width: 6),
                                      Text(
                                        'SORT',
                                        style: const TextStyle(
                                          fontFamily: 'Courier New',
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),

                          // Botón Nueva Playlist
                          InkWell(
                            onTap: () => _showCreatePlaylistDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.nebulaPurple.withValues(alpha: 0.18),
                                border: Border.all(color: AppTheme.nebulaPurple),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.add, size: 14, color: AppTheme.nebulaPurple),
                                  SizedBox(width: 4),
                                  Text(
                                    'NEW',
                                    style: TextStyle(
                                      fontFamily: 'Courier New',
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white10, height: 1),

                // Lista de Playlists
                Expanded(
                  child: Consumer<PlaylistController>(
                    builder: (context, playlistCtrl, child) {
                      final playlists = playlistCtrl.playlists;

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 96.0),
                        child: CustomScrollView(
                          slivers: [
                          // 1. Tarjeta Especial LIKED SONGS (Fija arriba)
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCollectionCard(
                                  context,
                                  title: 'LIKED SONGS',
                                  subtitle: 'AUTO_PLAYLIST // <3',
                                  color: AppTheme.nebulaPurple,
                                  icon: Icons.favorite,
                                  isSpecial: true,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const FavoritesScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),

                                // Cabecera de Playlists Personalizadas
                                Row(
                                  children: [
                                    Text(
                                      'CUSTOM_PLAYLISTS // ${playlists.length}',
                                      style: const TextStyle(
                                        fontFamily: 'Courier New',
                                        color: Colors.white54,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (playlistCtrl.sortType == PlaylistSortType.custom)
                                      Text(
                                        'DRAG TO REORDER',
                                        style: TextStyle(
                                          fontFamily: 'Courier New',
                                          color: AppTheme.nebulaPurple.withValues(alpha: 0.8),
                                          fontSize: 9,
                                          letterSpacing: 1.0,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),

                          // 2. Playlists de Usuario (Reordenables)
                          if (playlists.isEmpty)
                            SliverToBoxAdapter(
                              child: Container(
                                padding: const EdgeInsets.all(28),
                                margin: const EdgeInsets.only(top: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.cmfDarkGrey.withValues(alpha: 0.4),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Column(
                                  children: const [
                                    Icon(Icons.queue_music, size: 36, color: Colors.white24),
                                    SizedBox(height: 12),
                                    Text(
                                      "NO_PLAYLISTS // TAP [NEW] TO CREATE",
                                      style: TextStyle(
                                        fontFamily: 'Courier New',
                                        color: Colors.white38,
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverReorderableList(
                              itemCount: playlists.length,
                              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                                return AnimatedBuilder(
                                  animation: animation,
                                  builder: (context, child) {
                                    final double animValue = Curves.easeInOut.transform(animation.value);
                                    return Material(
                                      color: AppTheme.cmfBlack.withValues(alpha: 0.95),
                                      elevation: 8.0 * animValue,
                                      shadowColor: AppTheme.nebulaPurple.withValues(alpha: 0.6),
                                      shape: const RoundedRectangleBorder(
                                        side: BorderSide(color: AppTheme.nebulaPurple, width: 1.5),
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: child,
                                    );
                                  },
                                  child: child,
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                HapticFeedback.selectionClick();
                                playlistCtrl.reorderPlaylists(oldIndex, newIndex);
                              },
                              itemBuilder: (context, index) {
                                final playlist = playlists[index];

                                return Padding(
                                  key: ValueKey('playlist_${playlist.id}'),
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: _buildCollectionCard(
                                    context,
                                    index: index,
                                    title: playlist.name.toUpperCase(),
                                    subtitle: 'CUSTOM_PLAYLIST // ${playlist.trackCount} TRACKS',
                                    color: Colors.blueAccent,
                                    icon: Icons.album,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Agarradera de arrastre
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.grab,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                              color: Colors.transparent,
                                              child: const Icon(
                                                Icons.drag_handle,
                                                color: Colors.white38,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Menú de opciones
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                                          color: AppTheme.cmfDarkGrey,
                                          shape: const RoundedRectangleBorder(
                                            side: BorderSide(color: Colors.white12),
                                            borderRadius: BorderRadius.zero,
                                          ),
                                          onSelected: (val) async {
                                            if (val == 'delete') {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  backgroundColor: AppTheme.cmfDarkGrey,
                                                  shape: const RoundedRectangleBorder(
                                                    side: BorderSide(color: Colors.white12),
                                                    borderRadius: BorderRadius.zero,
                                                  ),
                                                  title: const Text(
                                                    'DELETE PLAYLIST',
                                                    style: TextStyle(fontFamily: 'Courier New', color: Colors.white),
                                                  ),
                                                  content: Text(
                                                    'Are you sure you want to delete "${playlist.name}"?',
                                                    style: const TextStyle(fontFamily: 'Courier New', color: Colors.white70),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, false),
                                                      child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                playlistCtrl.deletePlaylist(playlist.id);
                                              }
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                'DELETE',
                                                style: TextStyle(
                                                  fontFamily: 'Courier New',
                                                  color: Colors.redAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      context.read<PlaylistController>().loadPlaylistDetails(playlist.id);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PlaylistDetailScreen(playlist: playlist),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                        ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _getSortLabel(PlaylistSortType type) {
    switch (type) {
      case PlaylistSortType.custom:
        return 'CUSTOM';
      case PlaylistSortType.nameAsc:
        return 'A - Z';
      case PlaylistSortType.nameDesc:
        return 'Z - A';
      case PlaylistSortType.tracksCount:
        return 'TRACKS';
      case PlaylistSortType.recent:
        return 'RECENT';
    }
  }

  void _showSortBottomSheet(BuildContext context) {
    final playlistCtrl = context.read<PlaylistController>();
    final current = playlistCtrl.sortType;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cmfBlack,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.zero,
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.sort, size: 16, color: AppTheme.nebulaPurple),
                      SizedBox(width: 8),
                      Text(
                        'ORGANIZATION // SORT_MODE',
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                _buildSortOptionTile(
                  context,
                  title: '[01] CUSTOM // DRAG & DROP',
                  subtitle: 'MANUAL REORDERING VIA HANDLES',
                  isSelected: current == PlaylistSortType.custom,
                  onTap: () {
                    playlistCtrl.setSortType(PlaylistSortType.custom);
                    Navigator.pop(context);
                  },
                ),
                _buildSortOptionTile(
                  context,
                  title: '[02] NAME (A -> Z)',
                  subtitle: 'ALPHABETICAL ASCENDING',
                  isSelected: current == PlaylistSortType.nameAsc,
                  onTap: () {
                    playlistCtrl.setSortType(PlaylistSortType.nameAsc);
                    Navigator.pop(context);
                  },
                ),
                _buildSortOptionTile(
                  context,
                  title: '[03] NAME (Z -> A)',
                  subtitle: 'ALPHABETICAL DESCENDING',
                  isSelected: current == PlaylistSortType.nameDesc,
                  onTap: () {
                    playlistCtrl.setSortType(PlaylistSortType.nameDesc);
                    Navigator.pop(context);
                  },
                ),
                _buildSortOptionTile(
                  context,
                  title: '[04] TRACKS COUNT',
                  subtitle: 'MOST TRACKS FIRST',
                  isSelected: current == PlaylistSortType.tracksCount,
                  onTap: () {
                    playlistCtrl.setSortType(PlaylistSortType.tracksCount);
                    Navigator.pop(context);
                  },
                ),
                _buildSortOptionTile(
                  context,
                  title: '[05] RECENTLY ADDED',
                  subtitle: 'CHRONOLOGICAL CREATION ORDER',
                  isSelected: current == PlaylistSortType.recent,
                  onTap: () {
                    playlistCtrl.setSortType(PlaylistSortType.recent);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSortOptionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.nebulaPurple.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(
          color: isSelected ? AppTheme.nebulaPurple : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: isSelected ? AppTheme.nebulaPurple : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.nebulaPurple,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cmfDarkGrey,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white12),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'NEW PLAYLIST',
          style: TextStyle(fontFamily: 'Courier New', color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontFamily: 'Courier New'),
          decoration: const InputDecoration(
            hintText: 'PLAYLIST NAME',
            hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Courier New'),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.nebulaPurple),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54, fontFamily: 'Courier New'),
            ),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<PlaylistController>().createPlaylist(
                      controller.text,
                    );
                Navigator.pop(context);
              }
            },
            child: const Text(
              'CREATE',
              style: TextStyle(color: AppTheme.nebulaPurple, fontFamily: 'Courier New', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    int? index,
    Widget? trailing,
    bool isSpecial = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cmfDarkGrey,
        border: Border.all(
          color: isSpecial ? AppTheme.nebulaPurple.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
          width: isSpecial ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (index != null) ...[
                  SizedBox(
                    width: 32,
                    child: Text(
                      '[${(index + 1).toString().padLeft(2, '0')}]',
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      icon == Icons.favorite ? '<3' : '[P]',
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -1.0,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Courier New',
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  trailing,
                ] else ...[
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withValues(alpha: 0.25),
                    size: 14,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
