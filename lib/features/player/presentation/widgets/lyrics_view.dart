import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/player/data/datasources/lyrics_service.dart';
import 'package:nebula/features/player/domain/entities/lyrics.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

class LyricsView extends StatefulWidget {
  final Track track;
  final VoidCallback? onClose;

  const LyricsView({
    super.key,
    required this.track,
    this.onClose,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final LyricsService _lyricsService = LyricsService();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _activeLineNotifier = ValueNotifier<int>(-1);
  StreamSubscription<Duration>? _positionSubscription;
  List<GlobalKey> _lineKeys = [];

  Lyrics? _lyrics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToPosition();
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _activeLineNotifier.value = -1;
      _lineKeys = [];
      _loadLyrics();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _activeLineNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLine(int index) {
    if (!mounted || index < 0 || index >= _lineKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _lineKeys[index];
      final targetContext = key.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.45, // Centers the line perfectly in the visible viewport
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _subscribeToPosition() {
    _positionSubscription?.cancel();
    _positionSubscription = context.read<PlayerController>().positionStream.listen((currentPos) {
      if (!mounted || _lyrics == null || !_lyrics!.isSynced) return;

      final lines = _lyrics!.syncedLyrics;
      int activeIdx = -1;

      for (int i = 0; i < lines.length; i++) {
        if (currentPos >= lines[i].timestamp) {
          activeIdx = i;
        } else {
          break;
        }
      }

      if (activeIdx != _activeLineNotifier.value && activeIdx != -1) {
        _activeLineNotifier.value = activeIdx;
        _scrollToLine(activeIdx);
      }
    });
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _isLoading = true;
      _lyrics = null;
    });
    _activeLineNotifier.value = -1;

    final lyrics = await _lyricsService.getLyrics(
      trackId: widget.track.id,
      title: widget.track.title,
      artist: widget.track.artist,
      duration: widget.track.duration,
    );

    if (mounted) {
      setState(() {
        _lyrics = lyrics;
        _lineKeys = (lyrics != null && lyrics.isSynced)
            ? List.generate(lyrics.syncedLyrics.length, (_) => GlobalKey())
            : [];
        _isLoading = false;
      });

      // Once loaded, center current active line immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lyrics == null || !_lyrics!.isSynced) return;
        final currentPos = context.read<PlayerController>().position;
        final lines = _lyrics!.syncedLyrics;
        int activeIdx = -1;
        for (int i = 0; i < lines.length; i++) {
          if (currentPos >= lines[i].timestamp) {
            activeIdx = i;
          } else {
            break;
          }
        }
        if (activeIdx != -1) {
          _activeLineNotifier.value = activeIdx;
          _scrollToLine(activeIdx);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cmfBlack.withValues(alpha: 0.95),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lyrics, color: AppTheme.nebulaPurple, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _lyrics == null || !_lyrics!.hasContent
                          ? 'LYRICS'
                          : (_lyrics!.isSynced ? 'SYNCED_LYRICS' : 'PLAIN_LYRICS'),
                      style: const TextStyle(
                        fontFamily: 'Courier New',
                        color: AppTheme.nebulaPurple,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.nebulaPurple,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'SEARCHING_METRICS...',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : (_lyrics == null || !_lyrics!.hasContent)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic_off, size: 36, color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              '[NO_LYRICS_AVAILABLE // AUDIO_ONLY]',
                              style: TextStyle(
                                fontFamily: 'Courier New',
                                color: Colors.white.withValues(alpha: 0.4),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _lyrics!.isSynced
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final verticalPadding = constraints.maxHeight * 0.42;

                              return ValueListenableBuilder<int>(
                                valueListenable: _activeLineNotifier,
                                builder: (context, activeIndex, _) {
                                  return SingleChildScrollView(
                                    controller: _scrollController,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                      vertical: verticalPadding,
                                    ),
                                    child: Column(
                                      children: List.generate(_lyrics!.syncedLyrics.length, (index) {
                                        final line = _lyrics!.syncedLyrics[index];
                                        final isActive = index == activeIndex;

                                        return InkWell(
                                          key: index < _lineKeys.length ? _lineKeys[index] : null,
                                          onTap: () {
                                            context.read<JamController>().seek(line.timestamp);
                                            _activeLineNotifier.value = index;
                                            _scrollToLine(index);
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 250),
                                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10.0,
                                              horizontal: 12.0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? AppTheme.nebulaPurple.withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              line.text,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Courier New',
                                                fontSize: isActive ? 18 : 14,
                                                fontWeight: isActive
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isActive
                                                    ? AppTheme.nebulaPurple
                                                    : Colors.white.withValues(alpha: 0.4),
                                                letterSpacing: isActive ? 0.5 : 0.0,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                },
                              );
                            },
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              _lyrics!.plainLyrics ?? '',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Courier New',
                                fontSize: 14,
                                height: 1.8,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
