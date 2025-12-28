import 'package:flutter/material.dart';

class NebulaInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final String? technicalSpec; // e.g. "MAX 128 CHARS / TEXT"

  const NebulaInput({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.technicalSpec,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFamily: 'Courier New',
                fontWeight: FontWeight.bold,
              ),
            ),
            if (technicalSpec != null)
              Text(
                technicalSpec!.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          keyboardType: keyboardType,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFamily: 'Courier New', // Monospace input for raw feel
          ),
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}
