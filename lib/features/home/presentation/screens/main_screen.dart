import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/core/utils/platform_utils.dart';
import 'package:nebula/features/home/presentation/screens/home_feed_screen.dart';
import 'package:nebula/features/home/presentation/screens/search_screen.dart';
import 'package:nebula/features/library/presentation/screens/library_screen.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/settings/presentation/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/auth/data/auth_service.dart';
import 'package:nebula/core/services/update_service.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/features/jam/presentation/widgets/jam_bottom_sheet.dart';
import 'package:nebula/features/jam/presentation/screens/jam_screen.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_import_controller.dart';
import 'package:nebula/features/playlist/presentation/widgets/import_playlist_bottom_sheet.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final FocusNode _focusNode = FocusNode();
  bool _hudVisible = false;
  Timer? _hudTimer;

  void _showVolumeHud() {
    _hudTimer?.cancel();
    if (!_hudVisible) {
      setState(() => _hudVisible = true);
    }
    _hudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _hudVisible = false);
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isDesktop || event is! KeyDownEvent) return KeyEventResult.ignored;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final isInputFocused =
        primaryFocus != null && primaryFocus.context?.widget is EditableText;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final player = context.read<PlayerController>();

    // Dedicated Media Volume Keys
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      player.increaseVolume();
      _showVolumeHud();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      player.decreaseVolume();
      _showVolumeHud();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeMute) {
      player.toggleMute();
      _showVolumeHud();
      return KeyEventResult.handled;
    }

    // Ctrl + ArrowUp / Ctrl + ArrowDown
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      player.increaseVolume();
      _showVolumeHud();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      player.decreaseVolume();
      _showVolumeHud();
      return KeyEventResult.handled;
    }

    // Ctrl + M -> Toggle Mute
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyM) {
      player.toggleMute();
      _showVolumeHud();
      return KeyEventResult.handled;
    }

    // Unmodified ArrowUp / ArrowDown when not typing in any search or text field
    if (!isInputFocused && !isCtrl) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        player.increaseVolume();
        _showVolumeHud();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        player.decreaseVolume();
        _showVolumeHud();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  final List<Widget> _screens = [
    const HomeFeedScreen(),
    const SearchScreen(),
    const LibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Check for updates on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.instance.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _focusNode,
        autofocus: isDesktop,
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          children: [
            // Global Background (Cached into GPU layer with RepaintBoundary)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: GridPainter(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),

            // Main Content with IndexedStack for persistence
            IndexedStack(index: _currentIndex, children: _screens),

            // MiniPlayer (Floating above content, persistent)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(top: false, child: MiniPlayer()),
            ),

            // Desktop Volume HUD Overlay
            if (isDesktop)
              Positioned(
                top: 24,
                right: 24,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hudVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Consumer<PlayerController>(
                      builder: (context, player, _) {
                        final vol = player.volume;
                        final isMuted = player.isMuted;
                        final pct = (vol * 100).round();

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.cmfDarkGrey.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.nebulaPurple.withValues(alpha: 0.5),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMuted
                                    ? Icons.volume_off
                                    : (vol < 0.5
                                        ? Icons.volume_down
                                        : Icons.volume_up),
                                color: isMuted
                                    ? AppTheme.nebulaPurple
                                    : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: LinearProgressIndicator(
                                  value: vol,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    AppTheme.nebulaPurple,
                                  ),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$pct%',
                                style: const TextStyle(
                                  fontFamily: 'Courier New',
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      endDrawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                child: Consumer<AuthService>(
                  builder: (context, auth, _) {
                    final metadata = auth.currentUser?.userMetadata;

                    final username =
                        metadata?['full_name'] as String? ??
                        auth.currentUser?.email?.split('@')[0] ??
                        'Guest';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ACCOUNT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                letterSpacing: 2.0,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          username.toUpperCase(),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontFamily: 'Courier New',
                                fontWeight: FontWeight.bold,
                                fontSize: 18, // Slightly smaller to fit
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white10),
              Consumer<JamController>(
                builder: (context, jam, _) {
                  return ListTile(
                    leading: Icon(
                      jam.isInJam ? Icons.people : Icons.people_outline,
                      color: jam.isInJam
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Row(
                      children: [
                        Text(
                          'JAM SESSIONS',
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontWeight: FontWeight.bold,
                            color: jam.isInJam
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (jam.isInJam) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${jam.participants.length}',
                              style: const TextStyle(
                                fontFamily: 'Courier New',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      if (jam.isInJam) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const JamScreen()),
                        );
                      } else {
                        JamBottomSheet.show(context);
                      }
                    },
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.playlist_add,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'IMPORT PLAYLIST',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'SOURCE // SPOTIFY',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  context.read<PlaylistImportController>().reset();
                  ImportPlaylistBottomSheet.show(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'SETTINGS',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const Spacer(),
              const Divider(color: Colors.white10),

              // Logout Tile
              Consumer<AuthService>(
                builder: (context, auth, _) => ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text(
                    'LOGOUT',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    final jam = context.read<JamController>();
                    Navigator.pop(context);
                    if (jam.isInJam) {
                      await jam.leaveJam();
                    }
                    await auth.signOut();
                    // Navigation to login is handled by AuthService stream in Main/Router
                    // But if MainScreen is top level, we might need to rely on stream listener in main.dart
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
              fontFamily: 'Courier New',
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
          indicatorColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
        ),
        child: NavigationBar(
          height: 60,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'HOME',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'SEARCH',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'LIB',
            ),
          ],
        ),
      ),
    );
  }
}
