import 'package:flutter/material.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cmfBlack,
      body: Stack(
        children: [
          // Background Grid
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(color: Colors.white.withOpacity(0.1)),
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
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'SETTINGS',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(letterSpacing: 2.0, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Settings List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    children: [
                      // --- PLAYBACK ---
                      _buildSectionHeader(context, 'PLAYBACK'),
                      _buildSwitchTile(
                        context,
                        'Stream Quality',
                        'High Audio Quality',
                        true,
                        (val) {},
                      ),
                      _buildSwitchTile(
                        context,
                        'Gapless Playback',
                        'Preload next track',
                        true,
                        (val) {},
                      ),

                      const SizedBox(height: 32),

                      // --- STORAGE & PRIVACY ---
                      _buildSectionHeader(context, 'DATA & PRIVACY'),
                      _buildActionTile(
                        context,
                        'Clear Cache',
                        'Free up space (24.5 MB)',
                        Icons.delete_outline,
                        () {},
                      ),
                      _buildSwitchTile(
                        context,
                        'Anonymous Metrics',
                        'Help improve Nebula',
                        false, // Default off for privacy-first apps
                        (val) {},
                      ),

                      const SizedBox(height: 32),

                      // --- ABOUT ---
                      _buildSectionHeader(context, 'ABOUT'),
                      _buildActionTile(
                        context,
                        'GitHub Repository',
                        'View Source Code',
                        Icons.code,
                        () {},
                      ),
                      _buildActionTile(
                        context,
                        'Licenses',
                        'Open Source Libraries',
                        Icons.description_outlined,
                        () {},
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'v0.1.0 (Alpha) • GPLv3 Licensed',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontFamily: 'Courier New',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],
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

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: SwitchListTile(
        activeColor: AppTheme.nebulaPurple,
        inactiveTrackColor: Colors.white10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontFamily: 'Courier New',
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontFamily: 'Courier New',
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white24,
          size: 16,
        ),
      ),
    );
  }
}
