import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Deeply optimized, animated notification bell with dynamic badge count and pulse effect.
class AnimatedNotificationBell extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const AnimatedNotificationBell({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  State<AnimatedNotificationBell> createState() => _AnimatedNotificationBellState();
}

class _AnimatedNotificationBellState extends State<AnimatedNotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _wiggleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    // Subtle bell wiggle/ringing animation
    _wiggleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -0.12), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -0.12, end: 0.12), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 0.12, end: -0.08), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -0.08, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 0.08, end: 0.0), weight: 1),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 10),
    ]).animate(_pulseController);

    if (widget.unreadCount > 0) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedNotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unreadCount > 0 && oldWidget.unreadCount == 0) {
      _pulseController.repeat(reverse: true);
    } else if (widget.unreadCount == 0 && oldWidget.unreadCount > 0) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;
    final countLabel = widget.unreadCount > 99
        ? '99+'
        : (widget.unreadCount > 9 ? '${widget.unreadCount}' : '${widget.unreadCount}');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hasUnread ? 0.28 : 0.20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: hasUnread ? 0.45 : 0.32),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Bell Icon with gentle animated rotation when active
              AnimatedBuilder(
                animation: _wiggleAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: hasUnread ? _wiggleAnimation.value : 0.0,
                    child: child,
                  );
                },
                child: Icon(
                  hasUnread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),

              // Animated Badge Pill
              Positioned(
                top: -3,
                right: -3,
                child: AnimatedScale(
                  scale: hasUnread ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.elasticOut,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: hasUnread ? _pulseAnimation.value : 1.0,
                        child: child,
                      );
                    },
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3B30), Color(0xFFDC2626)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.60),
                            blurRadius: 7,
                            spreadRadius: 0.8,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          countLabel,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
