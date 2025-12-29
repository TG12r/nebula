import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nebula/features/auth/data/auth_service.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Section
                    const SizedBox(height: 40),
                    Text(
                      'NEBULA'.toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 24, letterSpacing: -2.0),
                    ),
                    Text(
                      'MOBILE INTERFACE',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 24, letterSpacing: -2.0),
                    ),
                    const SizedBox(height: 60),

                    // Title
                    Text(
                      'REGISTER',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(fontSize: 48),
                    ),
                    const SizedBox(height: 40),

                    // Form Section
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          NebulaInput(
                            label: 'Username:',
                            controller: _nameController,
                            hintText: 'John Doe',
                            technicalSpec: 'INPUT TYPE: TEXT / MAX 64 CHARS',
                          ),
                          const SizedBox(height: 24),
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
                          const SizedBox(height: 24),
                          NebulaInput(
                            label: 'Confirm Password:',
                            controller: _confirmPasswordController,
                            obscureText: true,
                            technicalSpec: 'INPUT TYPE: SECURE / MATCH PREV',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Actions
                    NebulaButton(
                      label: 'CREATE ACCOUNT',
                      technicalLabel: 'BTN: REG_USER / ACT: DB_WRITE',
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          if (_passwordController.text !=
                              _confirmPasswordController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passwords do not match'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          // Registration Logic
                          try {
                            final authService = AuthService(
                              Supabase.instance.client,
                            );

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Creating Account...'),
                              ),
                            );

                            await authService.signUp(
                              email: _emailController.text.trim(),
                              password: _passwordController.text,
                              data: {'full_name': _nameController.text.trim()},
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Account created! Please check your email.',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.pop(context); // Go back to Login
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
                          Navigator.pop(context);
                        },
                        child: Text(
                          'BACK TO LOGIN ->',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
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
          ),
        ],
      ),
    );
  }
}
