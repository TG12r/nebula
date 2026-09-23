import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nebula/features/jam/presentation/logic/jam_controller.dart';
import 'package:nebula/core/theme/app_theme.dart';
import 'package:nebula/shared/widgets/widgets.dart';
import 'package:nebula/features/jam/presentation/screens/jam_screen.dart';

/// Modal bottom sheet for creating or joining a Jam session.
/// Follows the Nebula CMF design language: monochrome, Courier New,
/// sharp corners, technical labels.
class JamBottomSheet extends StatefulWidget {
  const JamBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const JamBottomSheet(),
    );
  }

  @override
  State<JamBottomSheet> createState() => _JamBottomSheetState();
}

class _JamBottomSheetState extends State<JamBottomSheet> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _createdCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createJam() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jamCtrl = context.read<JamController>();
      final code = await jamCtrl.createJam();
      setState(() {
        _createdCode = code;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'FAILED TO CREATE JAM: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinJam() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'ERR: CODE MUST BE 6 CHARACTERS');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jamCtrl = context.read<JamController>();
      await jamCtrl.joinJam(code);
      if (mounted) {
        Navigator.pop(context); // Close bottom sheet
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const JamScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'FAILED TO JOIN: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.cmfDarkGrey,
          border: Border(
            top: BorderSide(
              color: AppTheme.nebulaPurple.withOpacity(0.4),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: _createdCode != null
              ? _buildCreatedView()
              : _buildCreateOrJoinView(),
        ),
      ),
    );
  }

  Widget _buildCreateOrJoinView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'JAM SESSION',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'SYS: REALTIME_SYNC_MODULE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
                letterSpacing: 1.0,
              ),
        ),

        const SizedBox(height: 24),

        // Create Jam Button
        NebulaButton(
          label: 'CREATE JAM',
          technicalLabel: 'BTN: JAM_CREATE',
          onPressed: _isLoading ? () {} : _createJam,
        ),

        const SizedBox(height: 16),

        // Divider
        Row(
          children: [
            Expanded(
              child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  fontFamily: 'Courier New',
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Join Jam
        NebulaInput(
          label: 'JOIN CODE',
          controller: _codeController,
          hintText: 'ENTER 6-CHAR CODE',
          technicalSpec: 'FLD: JAM_CODE',
          onSubmitted: (_) => _joinJam(),
        ),

        const SizedBox(height: 16),

        NebulaButton(
          label: 'JOIN JAM',
          technicalLabel: 'BTN: JAM_JOIN',
          isSecondary: true,
          onPressed: _isLoading ? () {} : _joinJam,
        ),

        // Error Display
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: 'Courier New',
              color: Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],

        // Loading Indicator
        if (_isLoading) ...[
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.nebulaPurple,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCreatedView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'JAM CREATED',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                letterSpacing: -1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'SYS: CHANNEL_ACTIVE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.nebulaPurple.withOpacity(0.6),
                fontSize: 10,
                letterSpacing: 1.0,
              ),
        ),

        const SizedBox(height: 24),

        // Code Display
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppTheme.nebulaPurple.withOpacity(0.4),
                width: 1,
              ),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(
              _createdCode!,
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 8,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Copy Button
        Center(
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _createdCode!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'CODE COPIED',
                    style: TextStyle(fontFamily: 'Courier New'),
                  ),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(
              Icons.copy,
              color: AppTheme.nebulaPurple,
              size: 16,
            ),
            label: const Text(
              'COPY CODE',
              style: TextStyle(
                fontFamily: 'Courier New',
                color: AppTheme.nebulaPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Center(
          child: Text(
            'SHARE THIS CODE WITH FRIENDS TO JAM TOGETHER',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Courier New',
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Enter Jam Button
        NebulaButton(
          label: 'ENTER JAM',
          technicalLabel: 'BTN: JAM_ENTER',
          onPressed: () {
            Navigator.pop(context); // Close bottom sheet
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JamScreen()),
            );
          },
        ),
      ],
    );
  }
}
