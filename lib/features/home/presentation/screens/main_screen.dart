import 'package:flutter/material.dart';
import 'package:nebula/features/home/presentation/screens/home_feed_screen.dart';
import 'package:nebula/features/home/presentation/screens/search_screen.dart';
import 'package:nebula/features/library/presentation/screens/library_screen.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/settings/presentation/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/auth/data/auth_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeFeedScreen(),
    const SearchScreen(),
    const LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Global Background
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
          ),

          // Main Content with IndexedStack for persistence
          IndexedStack(index: _currentIndex, children: _screens),

          // MiniPlayer (Floating above content, persistent)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0, // Sits on top of bottom nav? No, usually above it.
            // But if we put BottomNav in Scaffold, MiniPlayer needs to be careful
            // For now, let's put MiniPlayer fixed at bottom of screen,
            // and add padding to body content so it doesn't get hidden.
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                child: Text(
                  'MENU',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    letterSpacing: 2.0,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'SETTINGS',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Colors.white,
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
                    Navigator.pop(context);
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
          labelTextStyle: MaterialStateProperty.all(
            const TextStyle(
              fontFamily: 'Courier New',
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
          indicatorColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.2),
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
