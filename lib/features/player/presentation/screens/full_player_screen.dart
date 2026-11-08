import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/downloads/presentation/logic/download_controller.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/jam/presentation/widgets/jam_bottom_sheet.dart';
import 'package:nebula/features/jam/presentation/screens/jam_screen.dart';
import 'package:nebula/features/player/presentation/widgets/lyrics_view.dart';
import 'package:nebula/core/utils/platform_utils.dart';
import 'package:nebula/features/player/presentation/widgets/desktop_volume_control.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  double? _dragValue;
  bool _showLyrics = false;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _isSheetExpanded = false;
  int _desktopTab = 0; // 0: Queue, 1: Lyrics

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetChanged);
  }

  void _onSheetChanged() {
    if (!_sheetController.isAttached) return;
    final isExp = _sheetController.size > 0.25;
    if (isExp != _isSheetExpanded) {
      setState(() {
        _isSheetExpanded = isExp;
      });
    }
  }

  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    HapticFeedback.lightImpact();
    if (_sheetController.size > 0.2) {
      _sheetController.animateTo(
        0.08,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _sheetController.animateTo(
        0.86,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useDesktopLayout = (isDesktop || constraints.maxWidth > 850);

        return Scaffold(
          backgroundColor: AppTheme.cmfBlack,
          body: Stack(
            children: [
              // Background Grid (Static - Cached into GPU layer)
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

              if (useDesktopLayout)
                _buildDesktopLayout(context)
              else
                _buildMobileLayout(context),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // MOBILE / COMPACT LAYOUT (PUNTO MEDIO)
  // ==========================================
  Widget _buildMobileLayout(BuildContext context) {
    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              // Header Superior
              _buildTopHeader(context),

              const Spacer(),

              // Carátula / Letras
              Expanded(
                flex: 5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 340,
                        maxHeight: 340,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _showLyrics
                            ? Selector<PlayerController, Track?>(
                                selector: (_, p) => p.currentTrack,
                                builder: (context, track, _) {
                                  if (track == null) return const SizedBox();
                                  return LyricsView(
                                    key: ValueKey('lyrics_${track.id}'),
                                    track: track,
                                    onClose: () => setState(() => _showLyrics = false),
                                  );
                                },
                              )
                            : GestureDetector(
                                onTap: () => setState(() => _showLyrics = true),
                                child: Hero(
                                  tag: 'album_art',
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: AppTheme.cmfDarkGrey,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.15),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.nebulaPurple.withValues(alpha: 0.3),
                                            blurRadius: 30,
                                            offset: const Offset(0, 12),
                                          ),
                                        ],
                                      ),
                                      child: Selector<PlayerController, String?>(
                                        selector: (_, p) => p.currentThumbnail,
                                        builder: (_, thumbnail, _) {
                                          return thumbnail != null
                                              ? NebulaImage(
                                                  url: thumbnail,
                                                  fit: BoxFit.cover,
                                                  isThumbnail: false,
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
                ),
              ),

              const Spacer(),

              // Metadata: Título y Artista
              _buildMetadataHeader(context),

              const SizedBox(height: 24),

              // Barra de tiempo
              _buildSeekBar(context),

              const SizedBox(height: 24),

              // Controles maestros
              _buildMasterControls(context, showQueueButton: true),

              // Espacio de margen para el peek inferior
              const SizedBox(height: 60),
            ],
          ),
        ),

        // CMF Peek / Expanding Drawer (Punto Medio)
        _buildCmfBottomDrawer(context),
      ],
    );
  }

  // ==========================================
  // DESKTOP LAYOUT (SPLIT CYBER-DECK)
  // ==========================================
  Widget _buildDesktopLayout(BuildContext context) {
    return SafeArea(
      child: Row(
        children: [
          // PANEL IZQUIERDO: DECK DE REPRODUCCIÓN (46%)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.0,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildTopHeader(context, isDesktopView: true),
                  const Spacer(),

                  // Carátula con resplandor
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.cmfDarkGrey,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.nebulaPurple.withValues(alpha: 0.35),
                              blurRadius: 40,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Selector<PlayerController, String?>(
                          selector: (_, p) => p.currentThumbnail,
                          builder: (_, thumbnail, _) {
                            return thumbnail != null
                                ? NebulaImage(
                                    url: thumbnail,
                                    fit: BoxFit.cover,
                                    isThumbnail: false,
                                  )
                                : const Center(
                                    child: Icon(FontAwesomeIcons.music, color: Colors.white, size: 40),
                                  );
                          },
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  _buildMetadataHeader(context),
                  const SizedBox(height: 20),
                  _buildSeekBar(context),
                  const SizedBox(height: 20),
                  _buildMasterControls(context, showQueueButton: false),
                  const SizedBox(height: 16),

                  // Slider de volumen Desktop
                  const Center(
                    child: DesktopVolumeControl(sliderWidth: 180.0),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),

          // PANEL DERECHO: COLA INTERACTIVA / LETRAS (54%)
          Expanded(
            flex: 6,
            child: Column(
              children: [
                // Barra de Pestañas CMF
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      _buildDesktopTabButton(title: '[01. UP NEXT]', index: 0),
                      const SizedBox(width: 16),
                      _buildDesktopTabButton(title: '[02. LYRICS]', index: 1),
                      const Spacer(),
                      // Jam Badge si está activo
                      Consumer<JamController>(
                        builder: (context, jam, _) {
                          if (!jam.isInJam) return const SizedBox();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.nebulaPurple.withValues(alpha: 0.15),
                              border: Border.all(color: AppTheme.nebulaPurple),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_alt, size: 12, color: AppTheme.nebulaPurple),
                                const SizedBox(width: 6),
                                Text(
                                  'JAM (${jam.participants.length})',
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white12, height: 1),

                // Contenido de la pestaña derecha
                Expanded(
                  child: _desktopTab == 0
                      ? _buildQueueContent(context, isDesktopView: true)
                      : Selector<PlayerController, Track?>(
                          selector: (_, p) => p.currentTrack,
                          builder: (context, track, _) {
                            if (track == null) {
                              return const Center(
                                child: Text(
                                  'NO_TRACK // IDLE',
                                  style: TextStyle(
                                    fontFamily: 'Courier New',
                                    color: Colors.white24,
                                  ),
                                ),
                              );
                            }
                            return LyricsView(
                              key: ValueKey('desktop_lyrics_${track.id}'),
                              track: track,
                              onClose: () {},
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

  Widget _buildDesktopTabButton({required String title, required int index}) {
    final isSelected = _desktopTab == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _desktopTab = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.nebulaPurple.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppTheme.nebulaPurple : Colors.white24,
            width: 1.0,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.white54,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // CMF BOTTOM DRAWER (PEEK INTERACTIVO MÓVIL)
  // ==========================================
  Widget _buildCmfBottomDrawer(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.08,
      minChildSize: 0.075,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const [0.08, 0.86],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cmfDarkGrey.withValues(alpha: 0.98),
            border: Border(
              top: BorderSide(
                color: _isSheetExpanded
                    ? AppTheme.nebulaPurple
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // Barra de Peek en Reposo (Always visible, clean, CMF hardware feel)
              GestureDetector(
                onTap: _toggleSheet,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    children: [
                      // Tirador central
                      Container(
                        width: 36,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Selector<PlayerController, (List<Track>, String?)>(
                        selector: (_, p) => (p.queue, p.currentTrack?.id),
                        builder: (context, data, _) {
                          final queue = data.$1;
                          final curId = data.$2;
                          final curIdx = queue.indexWhere(
                            (t) => curId != null && TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(curId),
                          );
                          final nextTrack = (curIdx >= 0 && curIdx + 1 < queue.length)
                              ? queue[curIdx + 1]
                              : null;

                          return Row(
                            children: [
                              // Glowing LED dot
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.nebulaPurple,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'UP NEXT // ${queue.length}',
                                style: const TextStyle(
                                  fontFamily: 'Courier New',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (nextTrack != null && !_isSheetExpanded) ...[
                                Expanded(
                                  child: Text(
                                    'NEXT: ${nextTrack.title.toUpperCase()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Courier New',
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                const Spacer(),
                              ],
                              Icon(
                                _isSheetExpanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up,
                                color: Colors.white54,
                                size: 18,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // Contenido Expandido de la Cola
              Expanded(
                child: _buildQueueContent(
                  context,
                  scrollController: scrollController,
                  isDesktopView: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // CONTENIDO DE LA COLA (REORDENABLE Y CMF)
  // ==========================================
  Widget _buildQueueContent(
    BuildContext context, {
    ScrollController? scrollController,
    required bool isDesktopView,
  }) {
    final player = context.watch<PlayerController>();
    final jam = context.watch<JamController>();
    final queue = player.queue;
    final currentTrack = player.currentTrack;

    final currentIndex = queue.indexWhere(
      (t) => currentTrack != null && TrackSource.stripPrefix(t.id) == TrackSource.stripPrefix(currentTrack.id),
    );

    return Column(
      children: [
        // Acciones Rápidas Superiores (Shuffle & Clear)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Text(
                '${queue.length} TRACKS EN COLA',
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),

              // Botón Barajar
              InkWell(
                onTap: queue.isEmpty
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        jam.shuffleQueue();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.shuffle, size: 14, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'SHUFFLE',
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón Limpiar Cola
              InkWell(
                onTap: queue.isEmpty
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        jam.clearQueue();
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'CLEAR',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white10, height: 1),

        Expanded(
          child: queue.isEmpty
              ? const Center(
                  child: Text(
                    'QUEUE_EMPTY // NO TRACKS',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.white24,
                      letterSpacing: 2.0,
                      fontSize: 11,
                    ),
                  ),
                )
              : CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    // SECCIÓN 1: CANCIÓN EN REPRODUCCIÓN (CMF CARD)
                    if (currentTrack != null) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            '[01. NOW PLAYING]',
                            style: TextStyle(
                              fontFamily: 'Courier New',
                              color: AppTheme.nebulaPurple,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.nebulaPurple.withValues(alpha: 0.12),
                            border: Border.all(color: AppTheme.nebulaPurple, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: NebulaImage(
                                  url: currentTrack.thumbnailUrl,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  isThumbnail: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentTrack.title.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Courier New',
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentTrack.artist.toUpperCase(),
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontFamily: 'Courier New',
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const _CmfLedEqualizer(),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // SECCIÓN 2: A CONTINUACIÓN (REORDENABLE)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Text(
                          '[02. UP NEXT - DRAG TO REORDER]',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),

                    SliverReorderableList(
                      itemCount: queue.length,
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
                        jam.reorderQueue(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final isCurrent = index == currentIndex;

                        return Dismissible(
                          key: ValueKey('queue_track_${track.id}_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) {
                            HapticFeedback.lightImpact();
                            jam.removeFromQueue(index);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppTheme.nebulaPurple.withValues(alpha: 0.08)
                                  : AppTheme.cmfDarkGrey.withValues(alpha: 0.35),
                              border: Border.all(
                                color: isCurrent
                                    ? AppTheme.nebulaPurple.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.07),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => jam.skipToQueueItem(index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      // Índice técnico [02]
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '[${(index + 1).toString().padLeft(2, '0')}]',
                                          style: TextStyle(
                                            fontFamily: 'Courier New',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isCurrent ? AppTheme.nebulaPurple : Colors.white30,
                                          ),
                                        ),
                                      ),
                                      ClipRRect(
                                        borderRadius: BorderRadius.zero,
                                        child: NebulaImage(
                                          url: track.thumbnailUrl,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          isThumbnail: true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              track.title.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                color: isCurrent ? AppTheme.nebulaPurple : Colors.white,
                                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.artist.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                color: Colors.white.withValues(alpha: 0.45),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatTrackDuration(track.duration),
                                        style: const TextStyle(
                                          fontFamily: 'Courier New',
                                          color: Colors.white24,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.grab,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            color: Colors.transparent,
                                            child: const Icon(
                                              Icons.drag_handle,
                                              color: Colors.white38,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 50)),
                  ],
                ),
        ),
      ],
    );
  }

  // ==========================================
  // COMPONENTES AUXILIARES
  // ==========================================
  Widget _buildTopHeader(BuildContext context, {bool isDesktopView = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktopView ? 8.0 : 20.0,
        vertical: isDesktopView ? 8.0 : 16.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              isDesktopView ? Icons.arrow_back_ios_new : Icons.keyboard_arrow_down,
              color: Colors.white,
              size: isDesktopView ? 20 : 30,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            isDesktopView ? 'NEBULA // DECK 01' : 'NOW PLAYING',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.nebulaPurple,
              fontFamily: 'Courier New',
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          Consumer<JamController>(
            builder: (context, jam, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.people_outline,
                      color: jam.isInJam ? AppTheme.nebulaPurple : Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      if (jam.isInJam) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const JamScreen(),
                          ),
                        );
                      } else {
                        JamBottomSheet.show(context);
                      }
                    },
                  ),
                  if (jam.isInJam && jam.participants.isNotEmpty)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.nebulaPurple,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${jam.participants.length}',
                          style: const TextStyle(
                            fontFamily: 'Courier New',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Selector<PlayerController, String?>(
            selector: (_, p) => p.currentTitle,
            builder: (_, title, _) => NebulaMarquee(
              text: title?.toUpperCase() ?? 'UNKNOWN TRACK',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontSize: 22,
                fontFamily: 'Courier New',
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Selector<PlayerController, String?>(
            selector: (_, p) => p.currentArtist,
            builder: (_, artist, _) => Text(
              artist?.toUpperCase() ?? 'UNKNOWN ARTIST',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontFamily: 'Courier New',
                letterSpacing: 1.0,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Selector<PlayerController, (Duration, Duration)>(
        selector: (_, p) => (p.position, p.duration),
        builder: (_, data, _) {
          final position = data.$1;
          final duration = data.$2;
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.nebulaPurple,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  thumbColor: Colors.white,
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12.0,
                  ),
                ),
                child: Slider(
                  value: (_dragValue ?? position.inSeconds.toDouble()).clamp(
                    0.0,
                    duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                  ),
                  max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                  onChanged: (value) {
                    setState(() {
                      _dragValue = value;
                    });
                  },
                  onChangeEnd: (value) {
                    context.read<JamController>().seek(
                      Duration(seconds: value.toInt()),
                    );
                    setState(() {
                      _dragValue = null;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(
                        _dragValue != null ? Duration(seconds: _dragValue!.toInt()) : position,
                      ),
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
    );
  }

  Widget _buildMasterControls(BuildContext context, {required bool showQueueButton}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Botón Descargar
        Consumer<DownloadController>(
          builder: (context, downloader, _) {
            final track = context.read<PlayerController>().currentTrack;
            if (track == null) return const SizedBox(width: 44);

            final isDownloaded = downloader.isDownloaded(track.id);
            final isDownloading = downloader.isDownloading(track.id);
            final progress = downloader.getProgress(track.id);

            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    isDownloaded ? Icons.offline_pin : Icons.download,
                    color: isDownloaded ? AppTheme.nebulaPurple : (isDownloading ? Colors.white38 : Colors.white),
                    size: 22,
                  ),
                  onPressed: isDownloaded
                      ? () => downloader.deleteTrack(track.id)
                      : (isDownloading ? null : () => downloader.downloadTrack(track)),
                ),
                if (isDownloading)
                  SizedBox(
                    width: 28,
                    height: 28,
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

        // Botón Like <3
        Selector<PlayerController, Track?>(
          selector: (_, p) => p.currentTrack,
          builder: (context, track, _) {
            return Consumer<FavoritesController>(
              builder: (context, favorites, _) {
                final isLiked = track != null && favorites.isFavorite(track.id);
                return IconButton(
                  icon: Text(
                    '<3',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      fontSize: 20,
                      color: isLiked ? AppTheme.nebulaPurple : Colors.white,
                    ),
                  ),
                  onPressed: () {
                    if (track != null) {
                      if (!isLiked) {
                        favorites.toggleFavorite(track);
                        _showAddToPlaylistModal(context, track);
                      } else {
                        favorites.toggleFavorite(track);
                      }
                    }
                  },
                );
              },
            );
          },
        ),

        // Canción Anterior
        IconButton(
          icon: const Icon(Icons.skip_previous, color: Colors.white, size: 34),
          onPressed: () => context.read<JamController>().skipToPrevious(),
        ),

        // Play / Pause Master Button
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.nebulaPurple.withValues(alpha: 0.18),
            border: Border.all(color: AppTheme.nebulaPurple, width: 1.5),
          ),
          child: Selector<PlayerController, bool>(
            selector: (_, p) => p.isPlaying,
            builder: (_, isPlaying, _) {
              return IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppTheme.nebulaPurple,
                  size: 38,
                ),
                onPressed: () => context.read<JamController>().togglePlay(),
              );
            },
          ),
        ),

        // Canción Siguiente
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white, size: 34),
          onPressed: () => context.read<JamController>().skipToNext(),
        ),

        // Botón de Cola [=] en Móvil (Punto Medio) o Letras
        if (showQueueButton) ...[
          IconButton(
            icon: Icon(
              _isSheetExpanded ? Icons.queue_music : Icons.format_list_bulleted,
              color: _isSheetExpanded ? AppTheme.nebulaPurple : Colors.white70,
              size: 22,
            ),
            tooltip: 'Ver cola',
            onPressed: _toggleSheet,
          ),
        ] else ...[
          IconButton(
            icon: Icon(
              _showLyrics ? Icons.music_note : Icons.lyrics_outlined,
              color: _showLyrics ? AppTheme.nebulaPurple : Colors.white70,
              size: 22,
            ),
            tooltip: _showLyrics ? 'Ver Carátula' : 'Ver Letras',
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  static String _formatTrackDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showAddToPlaylistModal(BuildContext context, dynamic track) {
    final playlistCtrl = context.read<PlaylistController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cmfBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
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
                border: Border(
                  top: BorderSide(
                    color: AppTheme.nebulaPurple.withValues(alpha: 0.5),
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
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontFamily: 'Courier New',
                          letterSpacing: -1,
                        ),
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
                    leading: const Icon(Icons.favorite, color: AppTheme.nebulaPurple),
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
                          activeThumbColor: AppTheme.nebulaPurple,
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
                      future: playlistCtrl.getPlaylistsContainingTrack(track.id),
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
                                  await playlistCtrl.addTrackToPlaylist(playlist.id, track);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("Added to ${playlist.name}"),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } else {
                                  await playlistCtrl.removeTrackFromPlaylist(playlist.id, track.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("Removed from ${playlist.name}"),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                }
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

/// Mini indicador ecualizador LED animado de 3 barras estilo CMF Nothing
class _CmfLedEqualizer extends StatefulWidget {
  const _CmfLedEqualizer();

  @override
  State<_CmfLedEqualizer> createState() => _CmfLedEqualizerState();
}

class _CmfLedEqualizerState extends State<_CmfLedEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ledBar(8 + t * 12),
            const SizedBox(width: 2.5),
            _ledBar(18 - t * 10),
            const SizedBox(width: 2.5),
            _ledBar(10 + t * 8),
          ],
        );
      },
    );
  }

  Widget _ledBar(double h) {
    return Container(
      width: 3,
      height: h,
      color: AppTheme.nebulaPurple,
    );
  }
}
