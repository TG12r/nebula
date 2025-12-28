import 'package:flutter/material.dart';

class NebulaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? technicalLabel; // e.g. "ACT: AUTHENTICATE"

  const NebulaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.technicalLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (technicalLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              technicalLabel!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'Courier New',
                fontSize: 10,
                letterSpacing: 1.0,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        SizedBox(
          height: 56, // Tall button
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero, // Sharp corners
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.onPrimary,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 16,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
