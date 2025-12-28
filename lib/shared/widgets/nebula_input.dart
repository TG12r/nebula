import 'package:flutter/material.dart';

class NebulaInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? technicalSpec;
  final Widget? suffixIcon;

  const NebulaInput({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.technicalSpec,
    this.suffixIcon,
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
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (technicalSpec != null)
              Text(
                technicalSpec!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
          keyboardType: keyboardType,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
