import 'package:flutter/material.dart';

class NebulaButton extends StatelessWidget {
  final String label;
  final String? technicalLabel;
  final VoidCallback onPressed;
  final bool isSecondary;

  const NebulaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.technicalLabel,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (technicalLabel != null) ...[
          Text(
            technicalLabel!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 4),
        ],
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isSecondary
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: isSecondary
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onPrimary,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero, // Sharp corners
              ),
              side: isSecondary
                  ? BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.2),
                    )
                  : BorderSide.none,
            ),
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSecondary
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
