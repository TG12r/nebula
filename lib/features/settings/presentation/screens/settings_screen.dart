import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';
import 'package:nebula/core/services/update_service.dart';
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
                              onChanged: (_) => settings.toggleTheme(),
                              activeColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white10,
                            ),
                          ),
                          NebulaListTile(
                            title: 'Image Quality',
                            subtitle: 'Control memory usage',
                            trailing: DropdownButton<ImageQuality>(
                              value: settings.imageQuality,
                              underline: const SizedBox(),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppTheme.nebulaPurple,
                              ),
                              items: ImageQuality.values.map((quality) {
                                return DropdownMenuItem(
                                  value: quality,
                                  child: Text(
                                    quality.name.toUpperCase(),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 12,
                                      fontFamily: 'Courier New',
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) settings.setImageQuality(val);
                              },
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
                              onChanged: (_) => settings.toggleHighQuality(),
                              activeColor: AppTheme.nebulaPurple,
                              inactiveTrackColor: Colors.white10,
                            ),
                          ),
                          NebulaListTile(
                            title: 'Gapless Playback',
                            subtitle: 'Preload next track',
                            trailing: Switch(
                              value: settings.gapless,
                              onChanged: (_) => settings.toggleGapless(),
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
                            onTap: () async {
                              // 1. Clear Memory Cache (RAM)
                              PaintingBinding.instance.imageCache.clear();
                              PaintingBinding.instance.imageCache
                                  .clearLiveImages();

                              // 2. Clear Disk Cache (Temp Files)
                              try {
                                final tempDir = await getTemporaryDirectory();
                                if (await tempDir.exists()) {
                                  final dir = Directory(tempDir.path);
                                  dir.list(recursive: true).listen((
                                    file,
                                  ) async {
                                    if (file is File) {
                                      try {
                                        await file.delete();
                                      } catch (e) {
                                        // Ignore errors (e.g., file in use)
                                      }
                                    }
                                  });
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Memory and temporary files cleared',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint("Error clearing cache: $e");
                              }
                            },
                          ),
                          const SizedBox(height: 32),
                          // --- ABOUT ---
                          _buildSectionHeader(context, 'ABOUT'),
                          NebulaListTile(
                            title: 'Check for Updates',
                            subtitle: 'Get the latest version',
                            leading: Icon(
                              Icons.system_update_alt,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            onTap: () {
                              UpdateService.instance.checkForUpdates(context);
                            },
                          ),
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
