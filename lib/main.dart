import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/core/config/app_env.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';
import 'package:nebula/features/auth/presentation/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  runApp(const MainApp());
}

final supabase = Supabase.instance.client;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => PlayerController())],
      child: MaterialApp(
        title: 'Nebula',
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
  }
}
