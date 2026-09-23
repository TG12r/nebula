import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/shared/widgets/nebula_image.dart';

class NebulaTrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrentTrack;
  final bool isPlaying;
  final bool isLoading;
  final String? indexNumber;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final Widget? trailing;

  // Swipe options
  final bool enableSwipeToQueue;
  final Future<void> Function()? onSwipeQueue;
  final bool enableSwipeToRemove;
  final Future<bool> Function()? onSwipeRemove;

  const NebulaTrackTile({
    super.key,
    required this.track,
    this.isCurrentTrack = false,
    this.isPlaying = false,
    this.isLoading = false,
    this.indexNumber,
    this.onTap,
    this.onPlay,
    this.trailing,
    this.enableSwipeToQueue = false,
    this.onSwipeQueue,
    this.enableSwipeToRemove = false,
    this.onSwipeRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget tileContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: isCurrentTrack
            ? AppTheme.nebulaPurple.withValues(alpha: 0.15)
            : AppTheme.cmfDarkGrey.withValues(alpha: 0.6),
        border: Border.all(
          color: isCurrentTrack
              ? AppTheme.nebulaPurple
              : Colors.white.withValues(alpha: 0.08),
          width: isCurrentTrack ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (indexNumber != null) ...[
              SizedBox(
                width: 24,
                child: Text(
                  indexNumber!,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCurrentTrack
                        ? AppTheme.nebulaPurple
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.cmfBlack,
                    border: Border.all(
                      color: isCurrentTrack
                          ? AppTheme.nebulaPurple
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: track.thumbnailUrl.isNotEmpty
                      ? NebulaImage(
                          url: track.thumbnailUrl,
                          fit: BoxFit.cover,
                          isThumbnail: true,
                        )
                      : const Center(
                          child: Icon(
                            FontAwesomeIcons.music,
                            color: Colors.white38,
                            size: 16,
                          ),
                        ),
                ),
                if (isLoading)
                  Container(
                    width: 46,
                    height: 46,
                    color: Colors.black54,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.nebulaPurple,
                        ),
                      ),
                    ),
                  )
                else if (isCurrentTrack && isPlaying)
                  Container(
                    width: 46,
                    height: 46,
                    color: Colors.black45,
                    child: const Center(
                      child: Icon(
                        Icons.equalizer,
                        color: AppTheme.nebulaPurple,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        title: Text(
          track.title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isCurrentTrack ? AppTheme.nebulaPurple : Colors.white,
          ),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                track.artist.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ),
            if (track.source != null)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  track.source!.name.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: trailing,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
      ),
    );

    // If swipe actions are not configured, return the tile directly
    if (!enableSwipeToQueue && !enableSwipeToRemove) {
      return tileContent;
    }

    DismissDirection direction;
    if (enableSwipeToQueue && enableSwipeToRemove) {
      direction = DismissDirection.horizontal;
    } else if (enableSwipeToQueue) {
      direction = DismissDirection.startToEnd;
    } else {
      direction = DismissDirection.endToStart;
    }

    return Dismissible(
      key: ValueKey('track_${track.id}_${indexNumber ?? ""}'),
      direction: direction,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20.0),
        color: AppTheme.nebulaPurple,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.queue_music, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'ADD TO QUEUE',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: enableSwipeToRemove
          ? Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              color: Colors.red.shade900,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'REMOVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Courier New',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.delete_outline, color: Colors.white),
                ],
              ),
            )
          : null,
      confirmDismiss: (dismissDirection) async {
        HapticFeedback.mediumImpact();
        if (dismissDirection == DismissDirection.startToEnd && onSwipeQueue != null) {
          await onSwipeQueue!();
          return false; // Don't dismiss from list
        } else if (dismissDirection == DismissDirection.endToStart && onSwipeRemove != null) {
          return await onSwipeRemove!();
        }
        return false;
      },
      child: tileContent,
    );
  }
}
