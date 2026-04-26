import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopIntegrationService {
  static final DesktopIntegrationService instance = DesktopIntegrationService._();
  DesktopIntegrationService._();

  static const String _shortcutFlagKey = 'desktop_shortcut_created_v1';

  /// Automatically create the shortcut on first run on Windows/Linux
  Future<void> ensureShortcutCreated() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyCreated = prefs.getBool(_shortcutFlagKey) ?? false;

    if (!alreadyCreated) {
      final success = await createShortcut();
      if (success) {
        await prefs.setBool(_shortcutFlagKey, true);
        debugPrint('Desktop integration created automatically.');
      }
    }
  }

  /// Create or update the shortcut (Windows .lnk or Linux .desktop)
  Future<bool> createShortcut() async {
    if (kIsWeb) return false;

    if (Platform.isWindows) {
      return _createWindowsShortcut();
    } else if (Platform.isLinux) {
      return _createLinuxShortcut();
    }
    
    return false;
  }

  Future<bool> _createWindowsShortcut() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;

      final startMenuPath = '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Nebula.lnk';
      
      final escapedExe = exePath.replaceAll("'", "''");
      final escapedLnk = startMenuPath.replaceAll("'", "''");

      final shellCommand = 
          "\$s = (New-Object -ComObject WScript.Shell).CreateShortcut('$escapedLnk'); "
          "\$s.TargetPath = '$escapedExe'; "
          "\$s.WorkingDirectory = '${File(exePath).parent.path}'; "
          "\$s.Save();";

      final result = await Process.run('powershell', ['-Command', shellCommand]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error creating Windows shortcut: $e');
      return false;
    }
  }

  Future<bool> _createLinuxShortcut() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final home = Platform.environment['HOME'];
      if (home == null) return false;

      final desktopFilePath = '$home/.local/share/applications/nebula.desktop';
      final desktopFile = File(desktopFilePath);

      // Ensure directory exists
      if (!await desktopFile.parent.exists()) {
        await desktopFile.parent.create(recursive: true);
      }

      final content = '''
[Desktop Entry]
Name=Nebula
Comment=A privacy-first music streaming app
Exec=$exePath
Icon=nebula
Type=Application
Terminal=false
Categories=Audio;Music;Player;
Keywords=music;streaming;nebula;
''';

      await desktopFile.writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('Error creating Linux shortcut: $e');
      return false;
    }
  }

  /// Check if the shortcut file exists
  Future<bool> shortcutExists() async {
    if (kIsWeb) return false;

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      return File('$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Nebula.lnk').exists();
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      return File('$home/.local/share/applications/nebula.desktop').exists();
    }
    
    return false;
  }
}
