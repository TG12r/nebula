import 'dart:io';
import 'package:flutter/foundation.dart';

/// Returns true if running on a desktop operating system (Windows, Linux, macOS).
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
