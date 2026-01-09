import 'package:flutter/material.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/settings/presentation/logic/settings_controller.dart';
import 'package:nebula/features/settings/domain/entities/image_quality.dart';

class NebulaImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool isThumbnail;
  final Widget? errorBuilder;

  const NebulaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.isThumbnail = true,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Watch settings for changes
    final quality = context.select<SettingsController, ImageQuality>(
      (s) => s.imageQuality,
    );

    final cacheWidth = _calculateCacheWidth(quality, isThumbnail);

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) {
        if (errorBuilder != null) return errorBuilder!;
        return Container(
          width: width,
          height: height,
          color: AppTheme.cmfDarkGrey,
          child: const Center(
            child: Icon(Icons.music_note, color: Colors.white24),
          ),
        );
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  int? _calculateCacheWidth(ImageQuality quality, bool isThumbnail) {
    switch (quality) {
      case ImageQuality.low:
        // Aggressive savings
        return isThumbnail ? 50 : 200;
      case ImageQuality.medium:
        // Balanced
        return isThumbnail ? 150 : 500;
      case ImageQuality.high:
        // Full quality (null means native resolution)
        return null;
    }
  }
}
