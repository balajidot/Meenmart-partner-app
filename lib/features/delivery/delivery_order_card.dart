import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/optimized_image.dart';
import '../support/store_support_chat_screen.dart';

class DeliveryOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Function(String newStatus) onStatusUpdate;

  const DeliveryOrderCard({
    super.key,
    required this.order,
    required this.onStatusUpdate,
  });

  static void _showLaunchError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red.shade700, content: Text(message)),
    );
  }

  // Don't gate on canLaunchUrl(): on Android 11+ it can return false even
  // when an app can handle the link. Try to launch and report real failures.
  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl failed for $uri: $e');
      return false;
    }
  }

  Future<void> _makePhoneCall(BuildContext context, String phone) async {
    HapticService.selectionClick();
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) {
      _showLaunchError(context, 'Customer phone number இல்லை');
      return;
    }
    final ok = await _tryLaunch(Uri(scheme: 'tel', path: cleanPhone));
    if (!ok && context.mounted) {
      _showLaunchError(context, 'Call app திறக்க முடியவில்லை — $cleanPhone');
    }
  }

  void _openCustomerChat(BuildContext context, String phone, String orderRef, String customerName) {
    HapticService.selectionClick();
    final customerUserId = order['user_id']?.toString() ?? '';
    final orderId = (order['id'] as num?)?.toInt();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreSupportChatScreen(
          customerUserId: customerUserId,
          orderId: orderId,
          orderRef: orderRef,
          customerName: customerName,
          customerPhone: phone,
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(BuildContext context, dynamic lat, dynamic lng, String address) async {
    HapticService.selectionClick();
    final latD = double.tryParse(lat?.toString() ?? '');
    final lngD = double.tryParse(lng?.toString() ?? '');
    final hasCoords = latD != null && lngD != null && (latD.abs() > 0.0001 || lngD.abs() > 0.0001);

    final candidates = <Uri>[
      if (hasCoords) ...[
        // 1. Google Maps app, straight into turn-by-turn navigation (bike mode)
        Uri.parse('google.navigation:q=$latD,$lngD&mode=l'),
        // 2. Google Maps directions link (app or browser)
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latD,$lngD&travelmode=two-wheeler'),
        // 3. Any installed maps app
        Uri.parse('geo:$latD,$lngD?q=$latD,$lngD'),
      ] else
        Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
    ];

    for (final uri in candidates) {
      if (await _tryLaunch(uri)) return;
    }
    if (context.mounted) {
      _showLaunchError(context, 'Google Maps திறக்க முடியவில்லை. Maps app install ஆகியுள்ளதா என்று பாருங்கள்.');
    }
  }

  void _copyAddressToClipboard(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 8),
            Text(
              'Delivery address copied to clipboard',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  static String formatDisplayOrderNumber(dynamic rawRef, [dynamic id]) {
    if (rawRef != null) {
      final str = rawRef.toString().trim();
      final numMatch = RegExp(r'\d+').firstMatch(str);
      if (numMatch != null) {
        final numVal = int.tryParse(numMatch.group(0)!) ?? 0;
        final formattedNum = numVal < 10 ? '0$numVal' : '$numVal';
        return '#$formattedNum';
      }
      return str;
    }
    if (id != null) {
      final numVal = int.tryParse(id.toString()) ?? 0;
      final formattedNum = numVal < 10 ? '0$numVal' : '$numVal';
      return '#$formattedNum';
    }
    return '#01';
  }

  static String formatSlotDisplay(String slot) {
    return slot
        .replaceAll(':00', '')
        .replaceAll('01:', '1:')
        .replaceAll(' - 0', ' - ');
  }

  static String cleanAddress(String raw) {
    final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final unique = <String>[];
    for (final p in parts) {
      if (unique.isEmpty || unique.last.toLowerCase() != p.toLowerCase()) {
        unique.add(p);
      }
    }
    return unique.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? 'out_for_delivery').toString().toLowerCase();
    final orderRef = formatDisplayOrderNumber(order['order_ref'], order['id']);
    final customerName = (order['customer_name'] != null && order['customer_name'].toString().trim().isNotEmpty)
        ? order['customer_name'].toString().trim()
        : 'Customer';
    final rawAddress = order['delivery_address'] ?? 'Address not provided';
    final address = cleanAddress(rawAddress);
    final phone = order['phone']?.toString() ?? '';
    final totalPrice = double.tryParse(order['total_price']?.toString() ?? '0') ?? 0.0;
    final paymentMethod = (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final isCod = paymentMethod == 'cod';
    final deliveryLat = order['delivery_lat'];
    final deliveryLng = order['delivery_lng'];
    final distanceKm = double.tryParse(order['distance_km']?.toString() ?? '0') ?? 0.0;
    final items = order['order_items'] as List<dynamic>? ?? [];
    final preOrderSlot = order['pre_order_slot']?.toString();

    final isOutForDelivery = status == 'out_for_delivery';
    final isDelivered = status == 'delivered';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOutForDelivery
              ? const Color(0xFF0284C7).withAlpha(120)
              : isDelivered
                  ? const Color(0xFF10B981).withAlpha(80)
                  : const Color(0xFFE2E8F0),
          width: isOutForDelivery ? 1.5 : 1.0,
        ),
        boxShadow: isOutForDelivery
            ? [
                BoxShadow(
                  color: const Color(0xFF0284C7).withAlpha(20),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ]
            : AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Strip ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: isOutForDelivery
                  ? const Color(0xFFEFF6FF)
                  : isDelivered
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: AppColors.navyBlue,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      orderRef,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (preOrderSlot != null && preOrderSlot.isNotEmpty)
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF475569)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              formatSlotDisplay(preOrderSlot),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFD97706)),
                          SizedBox(width: 2),
                          Text(
                            'Express Delivery',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  _buildStatusBadge(status),
                ],
              ),
            ),

            // ── High-Contrast Payment Method Banner (Overflow-Proof) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isCod ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                border: Border(
                  bottom: BorderSide(
                    color: isCod ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isCod ? const Color(0xFFDC2626) : const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            isCod ? Icons.payments_rounded : Icons.check_circle_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isCod ? '💵 COLLECT CASH' : '💳 PAID ONLINE',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                  color: isCod ? const Color(0xFF991B1B) : const Color(0xFF065F46),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                isCod
                                    ? 'Collect before handing over parcel'
                                    : 'Pre-paid • No cash collection',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isCod ? const Color(0xFFB91C1C) : const Color(0xFF047857),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹${totalPrice.toStringAsFixed(totalPrice.truncateToDouble() == totalPrice ? 0 : 2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: isCod ? const Color(0xFF991B1B) : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Customer Name & Distance ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          customerName,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppColors.navyBlue,
                          ),
                        ),
                      ),
                      if (distanceKm > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.near_me_rounded, size: 11, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Text(
                                '${distanceKm.toStringAsFixed(1)} km',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // ── Delivery Address with Copy Action ──
                  InkWell(
                    onTap: () => _copyAddressToClipboard(context, address),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF475569),
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Action Buttons Row: Navigate | Call | Chat ──
                  Row(
                    children: [
                      // 🧭 Google Maps Navigation Button
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () => _openGoogleMaps(context, deliveryLat, deliveryLng, address),
                          icon: const Icon(Icons.navigation_rounded, size: 15),
                          label: Text(
                            'Navigate Maps',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 📞 Call Customer Button
                      if (phone.isNotEmpty) ...[
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            onPressed: () => _makePhoneCall(context, phone),
                            icon: const Icon(Icons.call_rounded, size: 15, color: Color(0xFF059669)),
                            label: Text(
                              'Call',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF047857),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFECFDF5),
                              side: const BorderSide(color: Color(0xFFA7F3D0)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 💬 In-App Customer Live Chat Button
                        InkWell(
                          onTap: () => _openCustomerChat(context, phone, orderRef, customerName),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Icon(Icons.chat_bubble_rounded, size: 17, color: Color(0xFF2563EB)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Fish Items Summary with Cutting Details ──
                  if (items.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shopping_bag_outlined, size: 13, color: Color(0xFF64748B)),
                              const SizedBox(width: 6),
                              Text(
                                'Order Items (${items.length})',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...items.map((item) {
                            final fish = item['fish_items'] is Map ? item['fish_items'] : null;
                            final name = fish != null
                                ? (fish['tamil_name'] ?? fish['name'] ?? 'Fresh Fish')
                                : (item['fish_tamil_name'] ?? item['fish_name'] ?? 'Fresh Fish');
                            final imageUrl = fish != null ? fish['image_url'] as String? : null;
                            final qty = (item['quantity_kg'] as num? ?? 1.0).toDouble();
                            final cut = (item['cutting_type'] ?? '').toString();
                            final qtyDisplay = qty < 1.0
                                ? '${(qty * 1000).toInt()}g'
                                : '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)}kg';

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3.0),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                                          ? OptimizedImage(
                                              imageUrl: imageUrl.trim(),
                                              width: 28,
                                              height: 28,
                                              memCacheWidth: 56,
                                              memCacheHeight: 56,
                                              borderRadius: BorderRadius.circular(6),
                                              errorWidget: const Center(
                                                child: Text('🐟', style: TextStyle(fontSize: 13)),
                                              ),
                                            )
                                          : const Center(
                                              child: Text('🐟', style: TextStyle(fontSize: 13)),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.notoSansTamil(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.navyBlue,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (cut.isNotEmpty)
                                          Text(
                                            '🔪 $cut',
                                            style: GoogleFonts.inter(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF0284C7),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(
                                      qtyDisplay,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Customer live-location sharing toggle ──
                  if (isOutForDelivery && order['id'] != null) ...[
                    LiveLocationShareToggle(
                      key: ValueKey('live_loc_${order['id']}'),
                      orderId: (order['id'] as num).toInt(),
                      enabled: order['share_live_location'] == true,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ── Bottom Completion Action ──
                  if (isOutForDelivery)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmDeliveredDialog(context),
                        icon: const Icon(Icons.check_circle_rounded, size: 19),
                        label: Text(
                          'Handover & Complete Delivery ✅',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    )
                  else if (isDelivered)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 17),
                          const SizedBox(width: 8),
                          Text(
                            'Order Delivered Successfully 🎉',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeliveredDialog(BuildContext context) {
    final totalPrice = double.tryParse(order['total_price']?.toString() ?? '0') ?? 0.0;
    final isCod = (order['payment_method'] ?? 'cod').toString().toLowerCase() == 'cod';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCod ? const Color(0xFFFEF2F2) : const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCod ? Icons.payments_rounded : Icons.check_circle_rounded,
                color: isCod ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                size: 38,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isCod ? 'Confirm Cash Collection' : 'Confirm Delivery Handover',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17.5,
                fontWeight: FontWeight.w900,
                color: AppColors.navyBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isCod
                  ? 'Have you collected ₹${totalPrice.toStringAsFixed(0)} cash from the customer before handing over the parcel?'
                  : 'Has the parcel been handed over safely to the customer?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onStatusUpdate('delivered');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isCod ? 'Yes, Cash Collected ✅' : 'Yes, Handed Over ✅',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'packed':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        label = '📦 Ready';
        break;
      case 'out_for_delivery':
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        label = '🛵 Out for Delivery';
        break;
      case 'delivered':
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF166534);
        label = '🎉 Delivered';
        break;
      default:
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF475569);
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Rider-controlled switch: show / hide the rider's live location on the
/// customer's tracking map for one order. Server checks the rider owns it.
class LiveLocationShareToggle extends StatefulWidget {
  final int orderId;
  final bool enabled;

  const LiveLocationShareToggle({
    super.key,
    required this.orderId,
    required this.enabled,
  });

  @override
  State<LiveLocationShareToggle> createState() => _LiveLocationShareToggleState();
}

class _LiveLocationShareToggleState extends State<LiveLocationShareToggle> {
  late bool _enabled = widget.enabled;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant LiveLocationShareToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync with the latest DB value (realtime refresh), unless a
    // save is in flight.
    if (!_saving && oldWidget.enabled != widget.enabled) {
      _enabled = widget.enabled;
    }
  }

  Future<void> _toggle(bool value) async {
    if (_saving) return;
    HapticService.selectionClick();
    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await Supabase.instance.client.rpc(
        'set_order_live_location',
        params: {'p_order_id': widget.orderId, 'p_enabled': value},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: value ? const Color(0xFF059669) : const Color(0xFF475569),
          content: Text(
            value
                ? '📍 Customer-க்கு உங்கள் live location தெரியும்'
                : '🔒 Customer-க்கு live location மறைக்கப்பட்டது',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (e) {
      debugPrint('set_order_live_location failed: $e');
      if (!mounted) return;
      setState(() => _enabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('❌ Live location setting மாறவில்லை — மீண்டும் முயற்சிக்கவும்'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _enabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            on ? Icons.share_location_rounded : Icons.location_off_rounded,
            size: 20,
            color: on ? const Color(0xFF059669) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer Live Tracking',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyBlue,
                  ),
                ),
                Text(
                  on ? 'Customer-க்கு map-இல் தெரிகிறது' : 'Customer-க்கு மறைக்கப்பட்டுள்ளது',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Switch.adaptive(
              value: on,
              onChanged: _toggle,
              activeTrackColor: const Color(0xFF059669),
            ),
        ],
      ),
    );
  }
}
