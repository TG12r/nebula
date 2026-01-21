import 'package:flutter/material.dart';

class NebulaMarquee extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // Pixels per second
  final Duration pauseDuration;

  const NebulaMarquee({
    super.key,
    required this.text,
    this.style,
    this.velocity = 30.0,
    this.pauseDuration = const Duration(seconds: 2),
  });

  @override
  State<NebulaMarquee> createState() => _NebulaMarqueeState();
}

class _NebulaMarqueeState extends State<NebulaMarquee> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Try to start after layout
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() async {
    if (!mounted) return;

    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        // Calculate duration based on velocity
        final durationSeconds = maxScroll / widget.velocity;
        final duration = Duration(
          milliseconds: (durationSeconds * 1000).toInt(),
        );

        try {
          // 1. Pause at start
          await Future.delayed(widget.pauseDuration);
          if (!mounted) return;

          // 2. Scroll to end
          await _scrollController.animateTo(
            maxScroll,
            duration: duration,
            curve: Curves.linear,
          );
          if (!mounted) return;

          // 3. Pause at end
          await Future.delayed(widget.pauseDuration);
          if (!mounted) return;

          // 4. Jump back to start
          _scrollController.jumpTo(0.0);

          // 5. Loop
          _startScrolling();
        } catch (_) {
          // Handle specific animation cancellations
        }
      }
    }
  }

  @override
  void didUpdateWidget(NebulaMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      // Reset if text changes
      _scrollController.jumpTo(0.0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(), // Only programmatic scroll
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}
