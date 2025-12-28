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
import 'package:nebula/features/player/domain/repositories/player_repository.dart';
import 'package:nebula/features/favorites/data/repositories/favorites_repository_impl.dart';
import 'package:nebula/features/favorites/domain/repositories/favorites_repository.dart';
import 'package:nebula/features/favorites/presentation/logic/favorites_controller.dart';
import 'package:nebula/features/playlist/data/repositories/playlist_repository_impl.dart';
import 'package:nebula/features/playlist/domain/repositories/playlist_repository.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/home/presentation/screens/main_screen.dart';
import 'package:nebula/features/auth/data/auth_service.dart';
import 'package:nebula/features/settings/data/repositories/settings_repository_impl.dart'; // Added
import 'package:nebula/features/settings/domain/repositories/settings_repository.dart'; // Added
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart'; // Added

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

  // Initialize Settings Repository (Persistence)
  final settingsRepo = SettingsRepositoryImpl();
  await settingsRepo.init();

  runApp(MainApp(audioHandler: audioHandler, settingsRepository: settingsRepo));
}

final supabase = Supabase.instance.client;

class MainApp extends StatelessWidget {
  final NebulaAudioHandler audioHandler;
  final SettingsRepository settingsRepository;

  const MainApp({
    super.key,
    required this.audioHandler,
    required this.settingsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Repositories
        Provider<PlayerRepository>(
          create: (_) => PlayerRepositoryImpl(audioHandler),
        ),
        Provider<SettingsRepository>.value(
          value: settingsRepository,
        ), // Injected value

        Provider<FavoritesRepository>(
          create: (_) => FavoritesRepositoryImpl(Supabase.instance.client),
        ),
        Provider<PlaylistRepository>(
          create: (_) => PlaylistRepositoryImpl(Supabase.instance.client),
        ),

        Provider<AuthService>(
          create: (_) => AuthService(Supabase.instance.client),
        ),

        // Controllers
        ChangeNotifierProvider<SettingsController>(
          create: (context) {
            final controller = SettingsController(
              context.read<SettingsRepository>(),
            );
            controller.loadSettings(); // Load initial state
            return controller;
          },
        ),

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
      child: Consumer<SettingsController>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'Nebula',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<AuthState>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // If we are waiting for the stream to connect, check the current user synchronously
        // to provide an immediate UI if possible, avoiding a flicking loading screen.
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (authService.currentUser != null) {
            return const MainScreen();
          }
        }

        // For any other state (data or error), we check if we have a valid session user.
        final sessionExists = authService.currentUser != null;

        if (sessionExists) {
          return const MainScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
