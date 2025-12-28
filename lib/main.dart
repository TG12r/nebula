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
        ChangeNotifierProvider(
          create: (_) => PlayerController(PlayerRepositoryImpl(audioHandler)),
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
