import 'package:flutter/material.dart';

class NebulaListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const NebulaListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
        color: backgroundColor ?? theme.colorScheme.onSurface.withOpacity(0.05),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: leading,
        title: Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontFamily: 'Courier New',
                  fontSize: 12,
                ),
              )
            : null,
        trailing:
            trailing ??
            (onTap != null
                ? Icon(
                    Icons.arrow_forward_ios,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                    size: 16,
                  )
                : null),
      ),
    );
  }
}
