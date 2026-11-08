import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/presentation/logic/player_controller.dart';

class DesktopVolumeControl extends StatelessWidget {
  final double sliderWidth;
  final bool showPercentage;

  const DesktopVolumeControl({
    super.key,
    this.sliderWidth = 100.0,
    this.showPercentage = true,
  });

  IconData _getVolumeIcon(double volume, bool isMuted) {
    if (isMuted || volume == 0.0) {
      return Icons.volume_off;
    } else if (volume < 0.5) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();

    return Selector<PlayerController, (double, bool)>(
      selector: (_, p) => (p.volume, p.isMuted),
      builder: (context, data, _) {
        final volume = data.$1;
        final isMuted = data.$2;
        final percentage = (volume * 100).round();

        return Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              if (pointerSignal.scrollDelta.dy < 0) {
                // Wheel up -> Volume up
                player.increaseVolume(0.05);
              } else if (pointerSignal.scrollDelta.dy > 0) {
                // Wheel down -> Volume down
                player.decreaseVolume(0.05);
              }
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mute / Unmute Button
              IconButton(
                tooltip: isMuted ? 'Unmute' : 'Mute',
                icon: Icon(
                  _getVolumeIcon(volume, isMuted),
                  color: isMuted ? AppTheme.nebulaPurple : Colors.white70,
                  size: 20,
                ),
                splashRadius: 18,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => player.toggleMute(),
              ),

              // Volume Slider
              SizedBox(
                width: sliderWidth,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    activeTrackColor: AppTheme.nebulaPurple,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5.0,
                      elevation: 1.0,
                    ),
                    overlayColor: AppTheme.nebulaPurple.withValues(alpha: 0.2),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12.0,
                    ),
                  ),
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) => player.setVolume(val),
                  ),
                ),
              ),

              // Percentage Text
              if (showPercentage) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$percentage%',
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white60,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
