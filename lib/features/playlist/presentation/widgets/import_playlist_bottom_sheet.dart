import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_controller.dart';
import 'package:nebula/features/playlist/presentation/logic/playlist_import_controller.dart';
import 'package:nebula/features/playlist/presentation/screens/playlist_detail_screen.dart';
import 'package:nebula/shared/widgets/widgets.dart';

class ImportPlaylistBottomSheet extends StatefulWidget {
  const ImportPlaylistBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ImportPlaylistBottomSheet(),
    );
  }

  @override
  State<ImportPlaylistBottomSheet> createState() =>
      _ImportPlaylistBottomSheetState();
}

class _ImportPlaylistBottomSheetState extends State<ImportPlaylistBottomSheet> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      _urlController.text = data!.text!.trim();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Theme(
      data: AppTheme.darkTheme,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
        decoration: BoxDecoration(
          color: AppTheme.cmfDarkGrey,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        child: Consumer<PlaylistImportController>(
          builder: (context, importCtrl, _) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, importCtrl),
                  const SizedBox(height: 20),
                  _buildBody(context, importCtrl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PlaylistImportController ctrl) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IMPORT PLAYLIST',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Courier New',
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'SOURCE // SPOTIFY (PUBLIC)',
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 10,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () {
            if (ctrl.status == ImportStatus.importing) {
              ctrl.cancel();
            }
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, PlaylistImportController ctrl) {
    switch (ctrl.status) {
      case ImportStatus.idle:
      case ImportStatus.error:
        return _buildInputView(context, ctrl);
      case ImportStatus.fetchingPreview:
        return _buildLoadingView(
          context,
          title: 'FETCHING METADATA...',
          subtitle: 'Connecting to public Spotify web embed...',
        );
      case ImportStatus.previewReady:
        return _buildPreviewView(context, ctrl);
      case ImportStatus.importing:
        return _buildImportingView(context, ctrl);
      case ImportStatus.completed:
        return _buildCompletedView(context, ctrl);
    }
  }

  Widget _buildInputView(BuildContext context, PlaylistImportController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctrl.errorMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ctrl.errorMessage!,
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        NebulaInput(
          label: 'SPOTIFY LINK',
          controller: _urlController,
          hintText: '> https://open.spotify.com/playlist/...',
          technicalSpec: 'PUBLIC_PLAYLIST // NO_LOGIN_REQ',
          suffixIcon: IconButton(
            icon: const Icon(Icons.content_paste, size: 20),
            tooltip: 'Paste from clipboard',
            onPressed: _pasteFromClipboard,
          ),
          onSubmitted: (url) {
            ctrl.fetchPreview(url);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The playlist must be public on Spotify. Nebula parses the metadata and matches each track with high-fidelity streams.',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        NebulaButton(
          label: 'FETCH PLAYLIST',
          technicalLabel: 'STEP 01 // PARSE_METADATA',
          onPressed: () {
            ctrl.fetchPreview(_urlController.text);
          },
        ),
      ],
    );
  }

  Widget _buildLoadingView(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Courier New',
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewView(
    BuildContext context,
    PlaylistImportController ctrl,
  ) {
    final preview = ctrl.previewPlaylist;
    if (preview == null) return const SizedBox.shrink();

    if (_nameController.text.isEmpty) {
      _nameController.text = preview.title;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playlist preview card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cmfBlack,
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.coverUrl != null)
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    image: DecorationImage(
                      image: NetworkImage(preview.coverUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 72,
                  height: 72,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  child: Center(
                    child: Text(
                      '[P]',
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Courier New',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'FOUND: ${preview.trackCount} TRACKS',
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (preview.description != null &&
                        preview.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        NebulaInput(
          label: 'SAVE PLAYLIST AS',
          controller: _nameController,
          hintText: 'Enter playlist name...',
          technicalSpec: 'DESTINATION_DB',
        ),
        const SizedBox(height: 24),

        NebulaButton(
          label: 'IMPORT ${preview.trackCount} TRACKS',
          technicalLabel: 'STEP 02 // MATCH_AND_ADD',
          onPressed: () {
            final playlistCtrl = context.read<PlaylistController>();
            ctrl.startImport(playlistCtrl, customName: _nameController.text);
          },
        ),
        const SizedBox(height: 10),
        NebulaButton(
          label: 'CHANGE LINK',
          isSecondary: true,
          onPressed: () {
            ctrl.reset();
          },
        ),
      ],
    );
  }

  Widget _buildImportingView(
    BuildContext context,
    PlaylistImportController ctrl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'IMPORTING TRACKS...',
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              '${ctrl.currentIndex} / ${ctrl.totalTracks}',
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Sharp linear progress bar
        ClipRRect(
          borderRadius: BorderRadius.zero,
          child: LinearProgressIndicator(
            value: ctrl.progress,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Current track box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cmfBlack,
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RESOLVING AUDIO STREAM:',
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ctrl.currentTrackTitle.isNotEmpty
                    ? ctrl.currentTrackTitle
                    : 'Searching stream candidate...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MATCHED: ${ctrl.successfulCount}',
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontSize: 11,
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (ctrl.failedCount > 0)
              Text(
                'SKIPPED: ${ctrl.failedCount}',
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 11,
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        NebulaButton(
          label: 'CANCEL IMPORT',
          isSecondary: true,
          onPressed: () {
            ctrl.cancel();
          },
        ),
      ],
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    PlaylistImportController ctrl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.08),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'IMPORT COMPLETE',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${ctrl.successfulCount} tracks added to playlist "${ctrl.createdPlaylist?.name ?? 'Imported Playlist'}".',
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              if (ctrl.failedCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${ctrl.failedCount} tracks could not be matched.',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (ctrl.createdPlaylist != null)
          NebulaButton(
            label: 'OPEN PLAYLIST',
            technicalLabel: 'VIEW IN LIBRARY',
            onPressed: () {
              final playlist = ctrl.createdPlaylist!;
              ctrl.reset();
              Navigator.pop(context);
              context.read<PlaylistController>().loadPlaylistDetails(playlist.id);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlist: playlist),
                ),
              );
            },
          ),
        const SizedBox(height: 10),
        NebulaButton(
          label: 'DONE',
          isSecondary: true,
          onPressed: () {
            ctrl.reset();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
