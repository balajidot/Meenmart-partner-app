import 'package:flutter/material.dart';
import '../../../core/models/order_status_pipeline.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/haptic_service.dart';

class OrderEmptyView extends StatelessWidget {
  final OrderStatusPipeline currentStage;
  final String searchQuery;
  final VoidCallback onRefresh;

  const OrderEmptyView({
    super.key,
    required this.currentStage,
    required this.searchQuery,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final stageColor = currentStage.color;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: stageColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: stageColor.withValues(alpha: 0.28), width: 1.5),
              ),
              child: Icon(
                currentStage.icon,
                size: 38,
                color: stageColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              searchQuery.isNotEmpty
                  ? 'No Orders Matching "$searchQuery"'
                  : 'No Orders in ${currentStage.labelEnglish}',
              style: AppTextStyles.h3.copyWith(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              searchQuery.isNotEmpty
                  ? 'Try searching with customer name, phone number, or reference.'
                  : 'Orders moved to this stage will automatically appear here in real-time.',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: stageColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: stageColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  AppHaptics.mediumImpact();
                  onRefresh();
                },
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(
                  'REFRESH ORDERS',
                  style: AppTextStyles.badge.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
