import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/auth/data/auth_service.dart';
import 'package:nebula/features/auth/presentation/screens/register_screen.dart';
import 'package:nebula/features/home/presentation/screens/home_screen.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Grid Pattern
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Section
                  const SizedBox(height: 40),
                  Text(
                    'NEBULA'.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      letterSpacing: -2.0,
                    ),
                  ),
                  Text(
                    'MOBILE INTERFACE',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      letterSpacing: -2.0,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Title
                  Text(
                    'LOGIN',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 48,
                      // Simulating dot matrix with shadow offset if needed,
                      // or just relying on the theme's Courier font
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Form Section
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        NebulaInput(
                          label: 'Email ID:',
                          controller: _emailController,
                          hintText: 'user@example.com',
                          keyboardType: TextInputType.emailAddress,
                          technicalSpec: 'INPUT TYPE: TEXT / MAX 128 CHARS',
                        ),
                        const SizedBox(height: 24),
                        NebulaInput(
                          label: 'Password:',
                          controller: _passwordController,
                          obscureText: true,
                          technicalSpec: 'INPUT TYPE: SECURE / 8-32 CHARS',
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Actions
                  NebulaButton(
                    label: 'LOGIN',
                    technicalLabel: 'BTN: MAIN_LOGIN / ACT: AUTHENTICATE',
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        try {
                          final authService = AuthService(
                            Supabase.instance.client,
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Authenticating...')),
                          );

                          await authService.signIn(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                          );

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HomeScreen(),
                              ),
                            );
                          }
                        } on AuthException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.message),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Unexpected error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'CREATE ACCOUNT ->',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontFamily: 'Courier New',
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
