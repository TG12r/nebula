import 'package:flutter/material.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Grid
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Information / Header
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'SETTINGS',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              letterSpacing: 2.0,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ],
                  ),
                ),

                // Settings List
                Expanded(
                  child: Consumer<SettingsController>(
                    builder: (context, settings, child) {
                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        children: [
                          // --- GENERAL ---
                          _buildSectionHeader(context, 'GENERAL'),
                          NebulaListTile(
                            title: 'App Theme',
                            subtitle: settings.isDarkMode
                                ? 'Dark Mode (Nebula)'
                                : 'Light Mode',
                            trailing: Switch(
                              value: settings.isDarkMode,
                              onChanged: (val) => settings.toggleTheme(val),
                              activeColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // --- PLAYBACK ---
                          _buildSectionHeader(context, 'PLAYBACK'),
                          NebulaListTile(
                            title: 'Stream Quality',
                            subtitle: settings.highQuality
                                ? 'High Audio Quality'
                                : 'Standard Quality',
                            trailing: Switch(
                              value: settings.highQuality,
                              onChanged: (val) =>
                                  settings.toggleHighQuality(val),
                              activeColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white10,
                            ),
                          ),
                          NebulaListTile(
                            title: 'Gapless Playback',
                            subtitle: 'Preload next track',
                            trailing: Switch(
                              value: settings.gapless,
                              onChanged: (val) => settings.toggleGapless(val),
                              activeColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white10,
                            ),
                          ),

                          const SizedBox(height: 32),

                          // --- STORAGE & PRIVACY ---
                          _buildSectionHeader(context, 'DATA & PRIVACY'),
                          NebulaListTile(
                            title: 'Clear Cache',
                            subtitle: 'Free up space',
                            leading: Icon(
                              Icons.delete_outline,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            onTap: () {
                              // Implement cache clearing logic here later
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cache cleared! (Simulated)'),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 32),
                          // --- ABOUT ---
                          _buildSectionHeader(context, 'ABOUT'),
                          NebulaListTile(
                            title: 'GitHub Repository',
                            subtitle: 'View Source Code',
                            leading: Icon(
                              Icons.code,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            onTap: () async {
                              final Uri url = Uri.parse(
                                'https://github.com/TG12r/nebula',
                              );
                              if (!await launchUrl(url)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not launch GitHub URL',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          NebulaListTile(
                            title: 'Licenses',
                            subtitle: 'Open Source Libraries',
                            leading: Icon(
                              Icons.description_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            onTap: () async {
                              final Uri url = Uri.parse(
                                'https://github.com/TG12r/nebula/blob/master/LICENSE',
                              );
                              if (!await launchUrl(url)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not launch GitHub URL',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: FutureBuilder<PackageInfo>(
                              future: PackageInfo.fromPlatform(),
                              builder: (context, snapshot) {
                                final version = snapshot.data?.version ?? '...';
                                return Text(
                                  'v$version • GPLv3 Licensed',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.3),
                                    fontFamily: 'Courier New',
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 48),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.nebulaPurple,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
