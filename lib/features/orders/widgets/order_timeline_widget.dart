import 'package:flutter/material.dart';
import '../../../core/models/order_status_pipeline.dart';
import '../../../core/theme/app_theme.dart';

class OrderTimelineWidget extends StatelessWidget {
  final OrderStatusPipeline currentStage;
  final bool isCleaningRequired;

  const OrderTimelineWidget({
    super.key,
    required this.currentStage,
    this.isCleaningRequired = true,
  });

  List<OrderStatusPipeline> get orderStages => isCleaningRequired
      ? const [
          OrderStatusPipeline.newOrder,
          OrderStatusPipeline.weightConfirmed,
          OrderStatusPipeline.cleaning,
          OrderStatusPipeline.packed,
          OrderStatusPipeline.handedOver,
          OrderStatusPipeline.completed,
        ]
      : const [
          OrderStatusPipeline.newOrder,
          OrderStatusPipeline.weightConfirmed,
          OrderStatusPipeline.packed,
          OrderStatusPipeline.handedOver,
          OrderStatusPipeline.completed,
        ];

  @override
  Widget build(BuildContext context) {
    final stages = orderStages;
    final currentIdx = stages.indexOf(currentStage);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: List.generate(stages.length, (i) {
          final stage = stages[i];
          final isPast = currentIdx != -1 && i < currentIdx;
          final isActive = currentIdx != -1 && i == currentIdx;
          final isLast = i == stages.length - 1;

          String shortName;
          if (isCleaningRequired) {
            switch (stage) {
              case OrderStatusPipeline.newOrder:
                shortName = '1. New';
                break;
              case OrderStatusPipeline.weightConfirmed:
                shortName = '2. Weight';
                break;
              case OrderStatusPipeline.cleaning:
                shortName = '3. Clean';
                break;
              case OrderStatusPipeline.packed:
                shortName = '4. Pack';
                break;
              case OrderStatusPipeline.handedOver:
                shortName = '5. Dispatch';
                break;
              case OrderStatusPipeline.completed:
                shortName = '6. Done';
                break;
              default:
                shortName = '${i + 1}. ${stage.labelEnglish}';
            }
          } else {
            switch (stage) {
              case OrderStatusPipeline.newOrder:
                shortName = '1. New';
                break;
              case OrderStatusPipeline.weightConfirmed:
                shortName = '2. Weight';
                break;
              case OrderStatusPipeline.packed:
                shortName = '3. Pack';
                break;
              case OrderStatusPipeline.handedOver:
                shortName = '4. Dispatch';
                break;
              case OrderStatusPipeline.completed:
                shortName = '5. Done';
                break;
              default:
                shortName = '${i + 1}. ${stage.labelEnglish}';
            }
          }

          final stageColor = stage == OrderStatusPipeline.completed
              ? const Color(0xFF059669)
              : (stage == OrderStatusPipeline.newOrder ? const Color(0xFF2563EB) : stage.color);

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 19,
                        height: 19,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? stageColor
                              : (isPast ? const Color(0xFF059669) : const Color(0xFFF1F5F9)),
                          border: isPast || isActive ? null : Border.all(color: const Color(0xFFCBD5E1)),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: stageColor.withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: isPast
                              ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: isActive ? Colors.white : const Color(0xFF94A3B8),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        shortName,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 8.5,
                          fontWeight: isActive ? FontWeight.w900 : (isPast ? FontWeight.w700 : FontWeight.w500),
                          color: isActive
                              ? stageColor
                              : (isPast ? const Color(0xFF065F46) : const Color(0xFF94A3B8)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 6,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: isPast
                          ? const Color(0xFF059669)
                          : (isActive ? stageColor.withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
