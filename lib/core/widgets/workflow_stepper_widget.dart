import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/order_status_pipeline.dart';
import '../services/haptic_service.dart';

class ZomatoTabPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  ZomatoTabPainter({
    required this.fillColor,
    required this.borderColor,
    this.borderWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const flare = 6.0;
    const topRadius = 11.0;

    // Fill Path (enclosed to fill white background and seamlessly connect with body surface)
    final fillPath = Path();
    fillPath.moveTo(0, h + 3);
    fillPath.lineTo(0, h);
    fillPath.cubicTo(flare * 0.4, h, flare * 0.8, h - flare * 0.8, flare, h - flare * 1.2);
    fillPath.lineTo(flare + 2, topRadius);
    fillPath.quadraticBezierTo(flare + 2, 0, flare + 2 + topRadius, 0);
    fillPath.lineTo(w - flare - 2 - topRadius, 0);
    fillPath.quadraticBezierTo(w - flare - 2, 0, w - flare - 2, topRadius);
    fillPath.lineTo(w - flare, h - flare * 1.2);
    fillPath.cubicTo(w - flare * 0.8, h - flare * 0.8, w - flare * 0.4, h, w, h);
    fillPath.lineTo(w, h + 3);
    fillPath.close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    if (borderColor != Colors.transparent && borderWidth > 0) {
      final strokePath = Path();
      strokePath.moveTo(0, h);
      strokePath.cubicTo(flare * 0.4, h, flare * 0.8, h - flare * 0.8, flare, h - flare * 1.2);
      strokePath.lineTo(flare + 2, topRadius);
      strokePath.quadraticBezierTo(flare + 2, 0, flare + 2 + topRadius, 0);
      strokePath.lineTo(w - flare - 2 - topRadius, 0);
      strokePath.quadraticBezierTo(w - flare - 2, 0, w - flare - 2, topRadius);
      strokePath.lineTo(w - flare, h - flare * 1.2);
      strokePath.cubicTo(w - flare * 0.8, h - flare * 0.8, w - flare * 0.4, h, w, h);

      final strokePaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(strokePath, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ZomatoTabPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class OrderWorkflowStepperWidget extends StatefulWidget {
  final OrderStatusPipeline currentStage;
  final ValueChanged<OrderStatusPipeline>? onStageSelected;
  final bool isInteractive;
  final Map<OrderStatusPipeline, int>? orderCounts;

  const OrderWorkflowStepperWidget({
    super.key,
    required this.currentStage,
    this.onStageSelected,
    this.isInteractive = false,
    this.orderCounts,
  });

  static const List<OrderStatusPipeline> workflowStages = [
    OrderStatusPipeline.inventoryUpdate,
    OrderStatusPipeline.marketUpdated,
    OrderStatusPipeline.newOrder,
    OrderStatusPipeline.weightConfirmed,
    OrderStatusPipeline.cleaning,
    OrderStatusPipeline.packed,
    OrderStatusPipeline.handedOver,
    OrderStatusPipeline.completed,
    OrderStatusPipeline.cancelled,
  ];

  @override
  State<OrderWorkflowStepperWidget> createState() => _OrderWorkflowStepperWidgetState();
}

class _OrderWorkflowStepperWidgetState extends State<OrderWorkflowStepperWidget> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = List.generate(
    OrderWorkflowStepperWidget.workflowStages.length,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    _scrollToActiveStage();
  }

  @override
  void didUpdateWidget(covariant OrderWorkflowStepperWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStage != widget.currentStage) {
      _scrollToActiveStage();
    }
  }

  void _scrollToActiveStage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = OrderWorkflowStepperWidget.workflowStages.indexOf(widget.currentStage);
      if (index >= 0 && index < _itemKeys.length) {
        final keyContext = _itemKeys[index].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _getStageLiveColor(OrderStatusPipeline stage) {
    switch (stage) {
      case OrderStatusPipeline.inventoryUpdate:
        return const Color(0xFF8B5CF6); // Soft Lavender Violet
      case OrderStatusPipeline.marketUpdated:
        return const Color(0xFF10B981); // Fresh Mint Emerald
      case OrderStatusPipeline.newOrder:
        return const Color(0xFF3B82F6); // Soft Sky Blue
      case OrderStatusPipeline.weightConfirmed:
        return const Color(0xFF14B8A6); // Fresh Mint Teal
      case OrderStatusPipeline.cleaning:
        return const Color(0xFFF59E0B); // Warm Golden Amber
      case OrderStatusPipeline.packed:
        return const Color(0xFF0EA5E9); // Light Ocean Cyan
      case OrderStatusPipeline.handedOver:
        return const Color(0xFFEC4899); // Soft Rose Pink
      case OrderStatusPipeline.completed:
        return const Color(0xFF10B981); // Fresh Mint Emerald
      case OrderStatusPipeline.cancelled:
        return const Color(0xFFEF4444); // Soft Coral Red
    }
  }

  String _getStageShortLabel(OrderStatusPipeline stage) {
    switch (stage) {
      case OrderStatusPipeline.inventoryUpdate:
        return '1. Inventory';
      case OrderStatusPipeline.marketUpdated:
        return '2. Market';
      case OrderStatusPipeline.newOrder:
        return '3. New';
      case OrderStatusPipeline.weightConfirmed:
        return '4. Weight';
      case OrderStatusPipeline.cleaning:
        return '5. Clean';
      case OrderStatusPipeline.packed:
        return '6. Packed';
      case OrderStatusPipeline.handedOver:
        return '7. Dispatch';
      case OrderStatusPipeline.completed:
        return '8. Delivered';
      case OrderStatusPipeline.cancelled:
        return '9. Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stages = OrderWorkflowStepperWidget.workflowStages;
    final currentIndex = stages.indexOf(widget.currentStage);
    final activeStageColor = _getStageLiveColor(widget.currentStage);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 62,
      color: activeStageColor,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: stages.length,
        separatorBuilder: (context, index) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          margin: const EdgeInsets.only(bottom: 4),
          child: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 11,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        itemBuilder: (context, idx) {
          final stage = stages[idx];
          final isActive = idx == currentIndex;
          final count = widget.orderCounts?[stage] ?? 0;

          return Material(
            key: _itemKeys[idx],
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isInteractive
                  ? () {
                      AppHaptics.selectionClick();
                      widget.onStageSelected?.call(stage);
                      _scrollToActiveStage();
                    }
                  : null,
              borderRadius: BorderRadius.circular(14),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: isActive
                    ? CustomPaint(
                        painter: ZomatoTabPainter(
                          fillColor: const Color(0xFFF4F6F9),
                          borderColor: const Color(0xFFF4F6F9),
                          borderWidth: 1.0,
                        ),
                        child: Container(
                          width: 100,
                          height: 62,
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Active Icon with Notification Badge
                              Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4.5),
                                    decoration: BoxDecoration(
                                      color: activeStageColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      stage.icon,
                                      size: 17,
                                      color: activeStageColor,
                                    ),
                                  ),
                                  if (count > 0)
                                    Positioned(
                                      top: -3,
                                      right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: activeStageColor,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: activeStageColor.withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          '$count',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              // Active Stage Name in Stage Color
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _getStageShortLabel(stage),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: activeStageColor == const Color(0xFF059669)
                                        ? const Color(0xFF065F46)
                                        : activeStageColor,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        width: 82,
                        height: 50,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Inactive Icon with Badge
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  stage.icon,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                if (count > 0)
                                  Positioned(
                                    top: -3,
                                    right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        '$count',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          color: activeStageColor,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            // Inactive Stage Name in White
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _getStageShortLabel(stage),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
