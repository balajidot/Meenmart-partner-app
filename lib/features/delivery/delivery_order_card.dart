import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';
import '../support/store_support_chat_screen.dart';

class DeliveryOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Function(String newStatus) onStatusUpdate;

  const DeliveryOrderCard({
    super.key,
    required this.order,
    required this.onStatusUpdate,
  });

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openCustomerChat(BuildContext context, String phone, String orderRef, String customerName) {
    AppHaptics.selectionClick();
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

  Future<void> _openGoogleMaps(dynamic lat, dynamic lng, String address) async {
    Uri uri;
    if (lat != null && lng != null && (lat != 0 || lng != 0)) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    } else {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? 'packed').toString().toLowerCase();
    final orderRef = formatDisplayOrderNumber(order['order_ref'], order['id']);
    final customerName = (order['customer_name'] != null && order['customer_name'].toString().trim().isNotEmpty)
        ? order['customer_name'].toString().trim()
        : 'Customer';
    final address = order['delivery_address'] ?? 'Address not provided';
    final phone = order['phone']?.toString() ?? '';
    final totalPrice = double.tryParse(order['total_price']?.toString() ?? '0') ?? 0.0;
    final paymentMethod = (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final isCod = paymentMethod == 'cod';
    final deliveryLat = order['delivery_lat'];
    final deliveryLng = order['delivery_lng'];
    final distanceKm = double.tryParse(order['distance_km']?.toString() ?? '0') ?? 0.0;
    final items = order['order_items'] as List<dynamic>? ?? [];
    final preOrderSlot = order['pre_order_slot']?.toString();

    final isPacked = status == 'packed';
    final isOutForDelivery = status == 'out_for_delivery';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOutForDelivery
              ? AppColors.primary.withAlpha(120)
              : const Color(0xFFE2E8F0),
          width: isOutForDelivery ? 1.5 : 1.0,
        ),
        boxShadow: isOutForDelivery
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(30),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: isOutForDelivery
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.navyBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      orderRef,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (preOrderSlot != null && preOrderSlot.isNotEmpty)
                    Expanded(
                      child: Text(
                        '🕒 $preOrderSlot',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  _buildStatusBadge(status),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(
                            '📍 ${distanceKm.toStringAsFixed(1)} km',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // ── Address ──
                  Text(
                    address,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Quick Communication & Navigation Row ──
                  Row(
                    children: [
                      // 🧭 Google Maps Navigation Button
                      Expanded(
                        flex: 3,
                        child: OutlinedButton.icon(
                          onPressed: () => _openGoogleMaps(deliveryLat, deliveryLng, address),
                          icon: const Icon(Icons.navigation_rounded, size: 16, color: Color(0xFF2563EB)),
                          label: Text(
                            'Navigate',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1D4ED8),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFEFF6FF),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 📞 Call Customer Button
                      if (phone.isNotEmpty) ...[
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            onPressed: () => _makePhoneCall(phone),
                            icon: const Icon(Icons.call_rounded, size: 16, color: Color(0xFF16A34A)),
                            label: Text(
                              'Call',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFF0FDF4),
                              side: const BorderSide(color: Color(0xFF86EFAC)),
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
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Icon(Icons.chat_bubble_rounded, size: 18, color: Color(0xFF16A34A)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Fish Items Summary ──
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
                        children: items.map((item) {
                          final fish = item['fish_items'];
                          final name = fish != null
                              ? (fish['tamil_name'] ?? fish['name'] ?? 'மீன்')
                              : (item['fish_tamil_name'] ?? item['fish_name'] ?? 'மீன்');
                          final qty = item['quantity_kg'] ?? 1.0;
                          final cut = item['cutting_type'] ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                const Text('🐟 ', style: TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Text(
                                    '$name (${qty}kg)${cut.isNotEmpty ? " • $cut" : ""}',
                                    style: GoogleFonts.notoSansTamil(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF334155),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Payment Alert Box ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCod ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCod ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCod ? Icons.monetization_on_rounded : Icons.check_circle_rounded,
                              size: 18,
                              color: isCod ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isCod ? 'Cash on Delivery (COD)' : 'Paid Online (PAID)',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isCod ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${totalPrice.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isCod ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Action Buttons ──
                  if (isPacked)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => onStatusUpdate('out_for_delivery'),
                        icon: const Icon(Icons.two_wheeler_rounded, size: 20),
                        label: Text(
                          'Start Delivery ➔',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deliveryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    )
                  else if (isOutForDelivery)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmDeliveredDialog(context),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                        label: Text(
                          'Mark as Delivered 🎉',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                        ),
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
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Confirm Delivery',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.navyBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isCod
                  ? 'Have you collected ₹${totalPrice.toStringAsFixed(0)} cash from the customer?'
                  : 'Has the parcel been handed over to the customer?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: 14,
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
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Yes, Delivered ✅',
                      style: GoogleFonts.inter(
                        fontSize: 14,
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
        label = '📦 Packed';
        break;
      case 'out_for_delivery':
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        label = '🛵 Out for Delivery';
        break;
      case 'delivered':
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF166534);
        label = '🎉 Delivered Today';
        break;
      default:
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF475569);
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansTamil(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
