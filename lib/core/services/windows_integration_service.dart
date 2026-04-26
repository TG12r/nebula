import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsIntegrationService {
  static final WindowsIntegrationService instance = WindowsIntegrationService._();
  WindowsIntegrationService._();

  static const String _shortcutFlagKey = 'windows_shortcut_created_v1';

  /// Automatically create the shortcut on first run on Windows
  Future<void> ensureShortcutCreated() async {
    if (!Platform.isWindows || kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyCreated = prefs.getBool(_shortcutFlagKey) ?? false;

    if (!alreadyCreated) {
      final success = await createShortcut();
      if (success) {
        await prefs.setBool(_shortcutFlagKey, true);
        debugPrint('Windows Start Menu shortcut created automatically.');
      }
    }
  }

  /// Create or update the Start Menu shortcut
  Future<bool> createShortcut() async {
    if (!Platform.isWindows || kIsWeb) return false;

    try {
      final exePath = Platform.resolvedExecutable;
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;

      final startMenuPath = '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Nebula.lnk';
      
      // Use PowerShell to create the shortcut
      // Escape paths for PowerShell
      final escapedExe = exePath.replaceAll("'", "''");
      final escapedLnk = startMenuPath.replaceAll("'", "''");

      final shellCommand = 
          "\$s = (New-Object -ComObject WScript.Shell).CreateShortcut('$escapedLnk'); "
          "\$s.TargetPath = '$escapedExe'; "
          "\$s.WorkingDirectory = '${File(exePath).parent.path}'; "
          "\$s.Save();";

      final result = await Process.run('powershell', ['-Command', shellCommand]);

      if (result.exitCode == 0) {
        return true;
      } else {
        debugPrint('PowerShell Error creating shortcut: ${result.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('Error creating Windows shortcut: $e');
      return false;
    }
  }

  /// Check if the shortcut file exists
  Future<bool> shortcutExists() async {
    if (!Platform.isWindows || kIsWeb) return false;

    final appData = Platform.environment['APPDATA'];
    if (appData == null) return false;

    final startMenuPath = '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Nebula.lnk';
    return File(startMenuPath).exists();
  }
}
