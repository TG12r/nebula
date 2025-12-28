import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/core/config/app_env.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/auth/presentation/screens/login_screen.dart';
import 'package:audio_service/audio_service.dart';
import 'package:nebula/features/player/data/datasources/nebula_audio_handler.dart';
import 'package:nebula/features/player/data/repositories/player_repository_impl.dart';
import 'package:nebula/features/player/domain/repositories/player_repository.dart'; // Added
import 'package:nebula/features/favorites/data/repositories/favorites_repository_impl.dart';
import 'package:nebula/features/favorites/domain/repositories/favorites_repository.dart'; // Added
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/playlist/data/repositories/playlist_repository_impl.dart'; // Added
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart'; // Added
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart'; // Added

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  // Initialize Audio Handler Singleton
  final audioHandler = await AudioService.init(
    builder: () => NebulaAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nebula.channel.audio',
      androidNotificationChannelName: 'Nebula Music Playback',
      androidNotificationOngoing: true,
    ),
  );

  runApp(MainApp(audioHandler: audioHandler));
}

final supabase = Supabase.instance.client;

class MainApp extends StatelessWidget {
  final NebulaAudioHandler audioHandler;

  const MainApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Repositories
        Provider<PlayerRepository>(
          create: (_) => PlayerRepositoryImpl(audioHandler),
        ),
        Provider<FavoritesRepository>(
          create: (_) => FavoritesRepositoryImpl(Supabase.instance.client),
        ),
        Provider<PlaylistRepository>(
          create: (_) => PlaylistRepositoryImpl(Supabase.instance.client),
        ),

        // Controllers
        ChangeNotifierProvider<PlayerController>(
          create: (context) =>
              PlayerController(context.read<PlayerRepository>()),
        ),
        ChangeNotifierProvider<FavoritesController>(
          create: (context) =>
              FavoritesController(context.read<FavoritesRepository>()),
        ),
        ChangeNotifierProvider<PlaylistController>(
          create: (context) =>
              PlaylistController(context.read<PlaylistRepository>()),
        ),
      ],
      child: MaterialApp(
        title: 'Nebula',
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
  }
}
