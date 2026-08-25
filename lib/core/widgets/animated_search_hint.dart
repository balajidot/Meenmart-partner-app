import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ultra-smooth, hardware-accelerated vertical ticker search placeholder hint widget.
/// Inspired by high-end delivery apps (Swiggy / Blinkit / Google Search).
class AnimatedSearchHint extends StatefulWidget {
  final List<String> hints;
  final TextStyle? style;
  final Duration interval;
  final Duration animationDuration;

  const AnimatedSearchHint({
    super.key,
    required this.hints,
    this.style,
    this.interval = const Duration(milliseconds: 3200),
    this.animationDuration = const Duration(milliseconds: 550),
  });

  @override
  State<AnimatedSearchHint> createState() => _AnimatedSearchHintState();
}

class _AnimatedSearchHintState extends State<AnimatedSearchHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  int _currentIndex = 0;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubicEmphasized,
    );

    _startRotationTimer();
  }

  void _startRotationTimer() {
    if (widget.hints.length <= 1) return;

    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;

      _controller.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.hints.length;
            _controller.reset();
          });
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedSearchHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hints != widget.hints || oldWidget.interval != widget.interval) {
      _startRotationTimer();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hints.isEmpty) return const SizedBox.shrink();
    if (widget.hints.length == 1) {
      return _buildText(widget.hints.first);
    }

    final currentHint = widget.hints[_currentIndex];
    final nextIndex = (_currentIndex + 1) % widget.hints.length;
    final nextHint = widget.hints[nextIndex];

    return ClipRect(
      child: SizedBox(
        height: 22,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final t = _animation.value;

            // Outgoing text: rolls up and fades out
            final outgoingOffset = Offset(0.0, -1.0 * t);
            final outgoingOpacity = (1.0 - (t * 1.3)).clamp(0.0, 1.0);

            // Incoming text: rolls up from bottom and fades in
            final incomingOffset = Offset(0.0, 1.0 - t);
            final incomingOpacity = ((t - 0.1) * 1.25).clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.hardEdge,
              children: [
                // Outgoing child
                if (t < 0.95)
                  FractionalTranslation(
                    translation: outgoingOffset,
                    child: Opacity(
                      opacity: outgoingOpacity,
                      child: _buildText(currentHint),
                    ),
                  ),

                // Incoming child
                if (t > 0.05)
                  FractionalTranslation(
                    translation: incomingOffset,
                    child: Opacity(
                      opacity: incomingOpacity,
                      child: _buildText(nextHint),
                    ),
                  )
                else if (t == 0.0)
                  _buildText(currentHint),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildText(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: widget.style ??
            GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
