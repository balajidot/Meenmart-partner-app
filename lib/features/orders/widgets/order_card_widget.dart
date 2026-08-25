import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/order_status_pipeline.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/optimized_image.dart';
import 'order_timeline_widget.dart';

class OrderCardWidget extends StatelessWidget {
  final Map<String, dynamic> order;
  final OrderStatusPipeline selectedFilter;
  final Function(Map<String, dynamic> order) onAdvanceStage;
  final Function(Map<String, dynamic> order) onCancel;
  final Function(String phone) onCall;
  final Function(String phone, String orderRef) onWhatsApp;

  const OrderCardWidget({
    super.key,
    required this.order,
    required this.selectedFilter,
    required this.onAdvanceStage,
    required this.onCancel,
    required this.onCall,
    required this.onWhatsApp,
  });

  static Color getStageLiveColor(OrderStatusPipeline stage) {
    switch (stage) {
      case OrderStatusPipeline.inventoryUpdate:
        return const Color(0xFF8B5CF6);
      case OrderStatusPipeline.marketUpdated:
        return const Color(0xFF10B981);
      case OrderStatusPipeline.newOrder:
        return const Color(0xFF3B82F6);
      case OrderStatusPipeline.weightConfirmed:
        return const Color(0xFF14B8A6);
      case OrderStatusPipeline.cleaning:
        return const Color(0xFFF59E0B);
      case OrderStatusPipeline.packed:
        return const Color(0xFF0EA5E9);
      case OrderStatusPipeline.handedOver:
        return const Color(0xFFEC4899);
      case OrderStatusPipeline.completed:
        return const Color(0xFF10B981);
      case OrderStatusPipeline.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  static String formatDisplayOrderNumber(dynamic rawRef, [dynamic id]) {
    if (rawRef != null) {
      final str = rawRef.toString().trim();
      final allMatches = RegExp(r'\d+').allMatches(str).toList();
      if (allMatches.isNotEmpty) {
        final lastMatch = allMatches.last.group(0)!;
        final numVal = int.tryParse(lastMatch) ?? 0;
        final formattedNum = numVal < 10 ? '0$numVal' : '$numVal';
        return '#$formattedNum';
      }
      return str.startsWith('#') ? str : '#$str';
    }
    if (id != null) {
      final numVal = int.tryParse(id.toString()) ?? 0;
      final formattedNum = numVal < 10 ? '0$numVal' : '$numVal';
      return '#$formattedNum';
    }
    return '#01';
  }

  String _formatElapsedTime(String? createdAtIso) {
    if (createdAtIso == null) return '';
    try {
      final dt = DateTime.parse(createdAtIso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes == 1) return '1 min ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
      if (diff.inHours == 1) return '1 hr ago';
      if (diff.inHours < 24) return '${diff.inHours} hrs ago';
      if (diff.inDays == 1) return '1 day ago';
      return '${diff.inDays} days ago';
    } catch (_) {
      return '';
    }
  }

  static bool isCleaningRequiredForOrder(Map<String, dynamic> o) {
    final items = o['order_items'] as List? ?? [];
    if (items.isEmpty) return false;
    for (final it in items) {
      if (it['with_cleaning'] == true) return true;
      final raw = (it['cutting_type'] as String? ?? '').toLowerCase().trim();
      if (raw.isNotEmpty &&
          raw != 'none' &&
          raw != 'no_cleaning' &&
          raw != 'whole' &&
          raw != 'whole_fish' &&
          raw != 'raw' &&
          raw != 'uncleaned') {
        return true;
      }
    }
    return false;
  }

  static String formatCuttingTypeDisplay(String? rawCutting) {
    if (rawCutting == null || rawCutting.trim().isEmpty) {
      return '🐟 Whole Fish (No Cleaning)';
    }
    final lower = rawCutting.toLowerCase().trim();
    if (lower == 'whole' || lower == 'whole_fish' || lower == 'no_cleaning' || lower == 'raw' || lower == 'none' || lower == 'uncleaned') {
      return '🐟 Whole Fish';
    } else if (lower == 'curry_cut' || lower == 'curry cut' || lower == 'curry') {
      return '✂️ Curry Cut';
    } else if (lower == 'slices' || lower == 'fry_cut' || lower == 'fry cut' || lower == 'slice') {
      return '✂️ Fry Cut / Slices';
    } else if (lower == 'cleaned' || lower == 'whole_cleaned' || lower == 'whole cleaned') {
      return '✂️ Whole Cleaned';
    } else if (lower == 'biryani_cut' || lower == 'biryani cut') {
      return '✂️ Biryani Cut';
    } else if (lower == 'headless') {
      return '✂️ Headless';
    } else if (lower == 'peeled & deveined' || lower == 'peeled_and_deveined' || lower == 'peeled') {
      return '✂️ Peeled & Deveined';
    }
    return '✂️ ${rawCutting.replaceAll('_', ' ').trim()}';
  }

  String _getShortShiftLabel(OrderStatusPipeline stage) {
    switch (stage) {
      case OrderStatusPipeline.weightConfirmed:
        return 'CONFIRM WEIGHT';
      case OrderStatusPipeline.cleaning:
        return 'TO CLEANING';
      case OrderStatusPipeline.packed:
        return 'PACK ORDER';
      case OrderStatusPipeline.handedOver:
        return 'DISPATCH';
      case OrderStatusPipeline.completed:
        return 'COMPLETE';
      default:
        return stage.labelEnglish;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: selectedFilter == OrderStatusPipeline.cancelled
          ? _buildCancelledOrderCard(order)
          : _buildActiveOrderCard(order),
    );
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> o) {
    final currentStatusCode = o['status'] as String? ?? 'new_order';
    final currentStage = OrderStatusPipelineExt.fromCode(currentStatusCode);
    final isCleaningRequired = isCleaningRequiredForOrder(o);
    final nextStage = currentStage == OrderStatusPipeline.weightConfirmed
        ? (isCleaningRequired ? OrderStatusPipeline.cleaning : OrderStatusPipeline.packed)
        : currentStage.nextStage;
    final totalPrice = (o['total_price'] as num? ?? 0).toDouble();

    final orderItems = o['order_items'] as List? ?? [];
    final totalOrderWeight = orderItems.fold<double>(
      0.0,
      (sum, it) => sum + ((it['quantity_kg'] as num?)?.toDouble() ?? 1.0),
    );
    final phone = (o['phone'] ?? o['customer_phone'] ?? '').toString();
    final partnerName = o['delivery_partner_name'] ?? (o['delivery_partners'] != null ? o['delivery_partners']['name'] : null);
    final deliverySlot = (o['delivery_slot'] ?? 'Morning (07:00 AM - 10:00 AM)').toString();
    final packedPhotoUrl = o['packed_photo_url'] as String?;
    final timeAgo = _formatElapsedTime(o['created_at']?.toString());
    final isWeightAdjusted = o['is_weight_adjusted'] == true;
    final weightStatus = (o['weight_update_status'] as String? ?? '').toLowerCase().trim();
    final isWaitingCustomerApproval = isWeightAdjusted && (weightStatus == 'pending_approval' || weightStatus == 'pending');
    final isWeightRejected = isWeightAdjusted && (weightStatus == 'rejected' || weightStatus == 'declined');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Order Ref + Time Ago + Price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        formatDisplayOrderNumber(o['order_ref'], o['id']),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (timeAgo.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 3),
                          Text(
                            timeAgo,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                Text(
                  '₹${totalPrice.toStringAsFixed(0)}',
                  style: AppTextStyles.h2.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF047857),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Customer Name & Quick Contact Actions (Call & WhatsApp)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, size: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    o['customer_name'] ?? 'Customer',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  InkWell(
                    onTap: () => onCall(phone),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF059669)),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: AppTextStyles.badge.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onWhatsApp(phone, o['order_ref'] ?? 'PF-2'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Icon(Icons.chat_bubble_rounded, size: 14, color: Color(0xFF16A34A)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Location & Delivery Slot
            Row(
              children: [
                if (o['delivery_address'] != null && o['delivery_address'].toString().isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      o['delivery_address'].toString(),
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 11, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        deliverySlot,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // CUSTOMER SPECIAL INSTRUCTIONS
            if (o['special_instructions'] != null && o['special_instructions'].toString().trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📝', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Special Note: ${o['special_instructions']}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // PACKED PHOTO PROOF BADGE
            if (packedPhotoUrl != null && packedPhotoUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: OptimizedImage(
                        imageUrl: packedPhotoUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📷 Packed Parcel Photo Proof',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF059669),
                            ),
                          ),
                          Text(
                            'Verified via Live Camera',
                            style: AppTextStyles.caption.copyWith(fontSize: 9.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ASSIGNED DELIVERY PARTNER BADGE
            if (partnerName != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delivery_dining_rounded, size: 16, color: Color(0xFF059669)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Delivery Partner: $partnerName ${o["delivery_partner_phone"] != null ? "(${o['delivery_partner_phone']})" : ""}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF059669),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // WEIGHT ADJUSTMENT APPROVAL BADGE (Only show when weight was actually adjusted)
            if (isWeightAdjusted && (o['weight_update_status'] == 'approved' || o['weight_update_status'] == 'pending_approval')) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: o['weight_update_status'] == 'approved'
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: o['weight_update_status'] == 'approved'
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      o['weight_update_status'] == 'approved'
                          ? Icons.check_circle_rounded
                          : Icons.pending_actions_rounded,
                      size: 15,
                      color: o['weight_update_status'] == 'approved'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        o['weight_update_status'] == 'approved'
                            ? '✅ Customer approved weight (${o['confirmed_weight_kg'] ?? totalOrderWeight} kg • ₹${(o['total_price'] ?? 0).toStringAsFixed(0)})'
                            : '⏳ Waiting for customer weight approval (${o['confirmed_weight_kg'] ?? totalOrderWeight} kg • ₹${(o['total_price'] ?? 0).toStringAsFixed(0)})',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: o['weight_update_status'] == 'approved'
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB45309),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Multi-Item Order Details (Renders all items with images, weights, rates & cutting styles)
            _buildOrderItemsList(orderItems, o),
            const SizedBox(height: 10),

            // Visual Pipeline Stage Timeline Stepper
            OrderTimelineWidget(
              currentStage: currentStage,
              isCleaningRequired: isCleaningRequired,
            ),
            const SizedBox(height: 10),

            if (nextStage != null) ...[
              Row(
                children: [
                  // CANCEL BUTTON
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onCancel(o),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.close_rounded, color: Color(0xFFDC2626), size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Cancel',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // PRIMARY ADVANCE BUTTON
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: isWaitingCustomerApproval
                              ? [const Color(0xFFF97316), const Color(0xFFEA580C)]
                              : (isWeightRejected
                                  ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                  : [
                                      getStageLiveColor(nextStage),
                                      getStageLiveColor(nextStage).withValues(alpha: 0.85),
                                    ]),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isWaitingCustomerApproval
                                    ? const Color(0xFFF97316)
                                    : (isWeightRejected ? const Color(0xFFEF4444) : getStageLiveColor(nextStage)))
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onAdvanceStage(o),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isWaitingCustomerApproval
                                      ? Icons.hourglass_top_rounded
                                      : (isWeightRejected ? Icons.error_outline_rounded : nextStage.icon),
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      isWaitingCustomerApproval
                                          ? 'WAITING FOR CUSTOMER APPROVAL'
                                          : (isWeightRejected ? 'REJECTED • RE-WEIGH FISH' : _getShortShiftLabel(nextStage)),
                                      style: AppTextStyles.badge.copyWith(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.4,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  isWaitingCustomerApproval
                                      ? Icons.access_time_rounded
                                      : (isWeightRejected ? Icons.refresh_rounded : Icons.arrow_forward_rounded),
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: currentStage == OrderStatusPipeline.handedOver
                        ? [const Color(0xFFE11D48), const Color(0xFFBE185D)]
                        : [const Color(0xFF10B981), const Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (currentStage == OrderStatusPipeline.handedOver
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF10B981))
                          .withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        currentStage == OrderStatusPipeline.handedOver
                            ? Icons.delivery_dining_rounded
                            : Icons.task_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            currentStage == OrderStatusPipeline.handedOver
                                ? 'OUT FOR DELIVERY (DISPATCHED)'
                                : 'ORDER COMPLETED (DELIVERED)',
                            style: AppTextStyles.badge.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCancelledOrderCard(Map<String, dynamic> o) {
    final orderRef = formatDisplayOrderNumber(o['order_ref'], o['id']);
    final customerName = o['customer_name'] ?? 'Customer';
    final phone = o['phone'] ?? o['customer_phone'] ?? '';
    final address = o['delivery_address'] ?? 'Pulicat Delivery Area';
    final deliverySlot = o['delivery_slot'] ?? 'Standard Delivery';
    final totalPrice = (o['total_price'] as num? ?? 0).toDouble();
    final createdAt = o['created_at'] as String?;
    final reason = o['status_message'] ?? o['cancellation_reason'] ?? 'Order cancelled by customer / store';
    final orderItems = o['order_items'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: CANCELLED Badge + Order Ref + Strikethrough Amount
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cancel_rounded, size: 13, color: Color(0xFFDC2626)),
                      const SizedBox(width: 4),
                      Text(
                        'CANCELLED',
                        style: AppTextStyles.badge.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  orderRef,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                Text(
                  '₹${totalPrice.toStringAsFixed(0)}',
                  style: AppTextStyles.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Cancellation Reason Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFE11D48)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Notice: $reason',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Customer Contact & Actions
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customerName,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              deliverySlot,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (phone.isNotEmpty) ...[
                        Text(
                          phone,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  InkWell(
                    onTap: () => onCall(phone),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Icon(Icons.phone_rounded, color: Color(0xFF0F172A), size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onWhatsApp(phone, orderRef),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF059669), size: 16),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address,
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Cancelled Order Multi-Item Details & Timestamp
            _buildCancelledOrderItemsList(orderItems, createdAt),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsList(List<dynamic> orderItems, Map<String, dynamic> o) {
    if (orderItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.set_meal_rounded, size: 28, color: Color(0xFF059669)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fresh Seafood Item',
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    final hasMultiple = orderItems.length > 1;
    final totalWeight = orderItems.fold<double>(
      0.0,
      (sum, it) => sum + ((it['quantity_kg'] as num?)?.toDouble() ?? 1.0),
    );

    final paymentMethod = (o['payment_method'] ?? 'COD').toString().toUpperCase();
    final paymentStatus = (o['payment_status'] ?? '').toString().toLowerCase();
    final isPaid = paymentStatus == 'paid' || (paymentMethod != 'COD' && paymentStatus != 'pending');
    final deliveryCharge = (o['delivery_charge'] as num? ?? 0).toDouble();
    final discountAmount = (o['discount_amount'] as num? ?? 0).toDouble();
    final walletAmount = (o['wallet_amount_used'] as num? ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasMultiple ? const Color(0xFFCBD5E1) : const Color(0xFFF1F5F9),
          width: hasMultiple ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMultiple) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, size: 13, color: Color(0xFF2563EB)),
                  const SizedBox(width: 5),
                  Text(
                    '${orderItems.length} Seafood Items in this Order',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D4ED8),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ${totalWeight.toStringAsFixed(totalWeight.truncateToDouble() == totalWeight ? 0 : 1)} kg',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orderItems.length,
            separatorBuilder: (context, index) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: Color(0xFFE2E8F0)),
            ),
            itemBuilder: (context, idx) {
              final it = orderItems[idx];
              final fishData = it['fish_items'] is Map ? it['fish_items'] : null;
              final itemName = fishData != null
                  ? (fishData['name'] ?? fishData['name_en'] ?? it['item_name'] ?? 'Fresh Seafood')
                  : (it['item_name'] ?? 'Fresh Seafood');
              final itemTamil = fishData != null ? (fishData['tamil_name'] ?? '') : '';
              final itemImage = fishData != null ? fishData['image_url'] as String? : null;
              final qty = (it['quantity_kg'] as num? ?? 1.0).toDouble();
              final rawCutting = it['cutting_type'] as String?;
              final withCleaning = it['with_cleaning'] == true;
              final cleaningFee = (it['cleaning_fee'] as num? ?? 0).toDouble();
              final sizePref = (it['size_preference'] ?? '').toString().trim();

              final pricePerKg = (it['price_per_kg'] as num? ?? fishData?['price_per_kg'] ?? 0).toDouble();
              final itemTotal = (pricePerKg * qty) + cleaningFee;

              final formattedQty = qty < 1.0
                  ? '${(qty * 1000).toInt()}g'
                  : '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} kg';

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  OptimizedImage(
                    imageUrl: itemImage,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName.toString(),
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (itemTamil.isNotEmpty) ...[
                          Text(
                            itemTamil,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10.5,
                              color: const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatCuttingTypeDisplay(rawCutting),
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475569),
                              ),
                            ),
                            if (withCleaning) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Text(
                                  cleaningFee > 0 ? 'Cleaned (+₹${cleaningFee.toStringAsFixed(0)})' : 'Cleaned',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                            if (sizePref.isNotEmpty && sizePref.toLowerCase() != 'none') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sizePref,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          formattedQty,
                          style: AppTextStyles.badge.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (itemTotal > 0) ...[
                        Text(
                          '₹${itemTotal.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                      if (pricePerKg > 0) ...[
                        Text(
                          '₹${pricePerKg.toStringAsFixed(0)}/kg',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
          if (deliveryCharge > 0 || discountAmount > 0 || walletAmount > 0 || paymentMethod.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 6),
              child: Divider(height: 1, color: Color(0xFFE2E8F0)),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isPaid ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaid ? Icons.check_circle_rounded : Icons.payments_rounded,
                        size: 11,
                        color: isPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 3.5),
                      Text(
                        isPaid ? 'PAID ($paymentMethod)' : 'COLLECT: $paymentMethod',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isPaid ? const Color(0xFF059669) : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [
                    if (deliveryCharge > 0) ...[
                      Text(
                        'Delivery: ₹${deliveryCharge.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                      ),
                    ],
                    if (discountAmount > 0) ...[
                      Text(
                        'Discount: -₹${discountAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)),
                      ),
                    ],
                    if (walletAmount > 0) ...[
                      Text(
                        'Wallet: -₹${walletAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCancelledOrderItemsList(List<dynamic> orderItems, String? createdAt) {
    if (orderItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.set_meal_rounded, size: 14, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Fresh Seafood Item',
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...orderItems.map((it) {
            final fishData = it['fish_items'] is Map ? it['fish_items'] : null;
            final itemName = fishData != null
                ? (fishData['name'] ?? fishData['name_en'] ?? it['item_name'] ?? 'Fresh Seafood')
                : (it['item_name'] ?? 'Fresh Seafood');
            final itemTamil = fishData != null ? (fishData['tamil_name'] ?? '') : '';
            final qty = (it['quantity_kg'] as num? ?? 1.0).toDouble();

            final formattedQty = qty < 1.0
                ? '${(qty * 1000).toInt()}g'
                : '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} kg';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.set_meal_rounded, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$itemName ${itemTamil.isNotEmpty ? "($itemTamil)" : ""}',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formattedQty,
                    style: AppTextStyles.badge.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatElapsedTime(createdAt),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 9.5,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
