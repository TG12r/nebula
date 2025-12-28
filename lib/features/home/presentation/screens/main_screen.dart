import 'package:flutter/material.dart';
import 'package:nebula/features/home/presentation/screens/home_feed_screen.dart';
import 'package:nebula/features/home/presentation/screens/search_screen.dart';
import 'package:nebula/features/library/presentation/screens/library_screen.dart';
import 'package:nebula/features/player/presentation/widgets/mini_player.dart';
import 'package:nebula/shared/widgets/widgets.dart';

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
