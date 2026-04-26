import 'dart:async';
import 'package:flutter/material.dart';

/// A lightweight, resource-efficient Marquee (scrolling text) widget.
/// It only animates if the text exceeds the available width.
class NebulaMarquee extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pauseDuration;
  final double pixelsPerSecond;

  const NebulaMarquee({
    super.key,
    required this.text,
    this.style,
    this.pauseDuration = const Duration(seconds: 2),
    this.pixelsPerSecond = 30.0,
  });

  @override
  State<NebulaMarquee> createState() => _NebulaMarqueeState();
}

class _NebulaMarqueeState extends State<NebulaMarquee> {
  late ScrollController _scrollController;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAnimation());
  }

  @override
  void didUpdateWidget(NebulaMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _resetAndRestart();
    }
  }

  void _resetAndRestart() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
      _startAnimation();
    }
  }

  Future<void> _startAnimation() async {
    if (_isScrolling || !mounted || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    
    // If text fits in the container, no need to scroll
    if (maxScroll <= 0) return;

    _isScrolling = true;

    while (mounted && _scrollController.hasClients) {
      // Pause at start
      await Future.delayed(widget.pauseDuration);
      if (!mounted || !_scrollController.hasClients) break;

      final currentMaxScroll = _scrollController.position.maxScrollExtent;
      if (currentMaxScroll <= 0) {
        _isScrolling = false;
        return;
      }

      // Scroll to end
      final duration = Duration(
        milliseconds: (currentMaxScroll / widget.pixelsPerSecond * 1000).toInt(),
      );

      await _scrollController.animateTo(
        currentMaxScroll,
        duration: duration,
        curve: Curves.linear,
      );

      // Pause at end
      await Future.delayed(widget.pauseDuration);
      if (!mounted || !_scrollController.hasClients) break;

      // Reset to start (jump for minimum resource usage)
      _scrollController.jumpTo(0);
    }
    
    _isScrolling = false;
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
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
