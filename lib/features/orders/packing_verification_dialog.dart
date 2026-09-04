import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/optimized_image.dart';

class PackingVerificationDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Color? themeColor;
  final VoidCallback onConfirmed;

  const PackingVerificationDialog({
    super.key,
    required this.order,
    this.themeColor,
    required this.onConfirmed,
  });

  @override
  State<PackingVerificationDialog> createState() => _PackingVerificationDialogState();
}

class _PackingVerificationDialogState extends State<PackingVerificationDialog> {
  Color get _brandColor => widget.themeColor ?? const Color(0xFF0EA5E9);
  bool _isCutVerified = true;
  bool _isPouchSealed = true;
  bool _isTagAttached = true;
  bool _isIcePackPlaced = true;

  String _formatCuttingType(String rawCutting) {
    final lower = rawCutting.toLowerCase().trim();
    if (lower == 'curry_cut' || lower == 'curry cut') {
      return 'Curry Cut';
    } else if (lower == 'slices' || lower == 'fry_cut' || lower == 'fry cut') {
      return 'Fry Cut / Slices';
    } else if (lower == 'cleaned' || lower == 'whole_cleaned') {
      return 'Whole Cleaned';
    } else if (lower == 'whole') {
      return 'Whole Fish';
    } else if (lower == 'biryani_cut' || lower == 'biryani cut') {
      return 'Biryani Cut';
    } else if (lower == 'headless') {
      return 'Headless';
    } else if (lower == 'peeled & deveined' || lower == 'peeled_and_deveined' || lower == 'peeled') {
      return 'Peeled & Deveined';
    }
    return rawCutting.replaceAll('_', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final rawRef = (order['order_ref'] ?? order['id'] ?? '1').toString();
    final numMatch = RegExp(r'\d+').allMatches(rawRef);
    final orderNum = numMatch.isNotEmpty ? int.tryParse(numMatch.last.group(0)!) ?? 1 : 1;
    final orderRef = '#${orderNum < 10 ? "0$orderNum" : "$orderNum"}';
    final customerName = order['customer_name'] ?? 'Customer';
    final address = order['delivery_address'] ?? 'Pulicat Delivery Area';
    final deliverySlot = order['delivery_slot'] ?? 'Standard Delivery';
    final orderItems = order['order_items'] as List? ?? [];
    final weightProofUrl = order['weight_proof_url'] as String?;

    final allChecklistPassed = _isCutVerified && _isPouchSealed && _isTagAttached && _isIcePackPlaced;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row with Order Ref & Verified Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _brandColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.inventory_2_rounded, color: _brandColor, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pack Verification',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                          ),
                          Text(
                            'Order $orderRef',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _brandColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Customer & Address Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customerName,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(
                            deliverySlot,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Seafood Items & Cutting Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (orderItems.isEmpty) ...[
                      Text(
                        'Fresh Seafood Item',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                    ] else ...[
                      for (int idx = 0; idx < orderItems.length; idx++) ...[
                        if (idx > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                          ),
                        Builder(
                          builder: (context) {
                            final it = orderItems[idx];
                            final fish = it['fish_items'] is Map ? it['fish_items'] : null;
                            final name = fish != null ? (fish['name'] ?? fish['name_en'] ?? it['item_name'] ?? 'Seafood') : (it['item_name'] ?? 'Seafood');
                            final tamil = fish != null ? (fish['tamil_name'] ?? '') : '';
                            final itemQty = (it['quantity_kg'] as num? ?? 1.0).toDouble();
                            final itemCutting = (it['cutting_type'] ?? 'Cleaned').toString();
                            final withClean = it['with_cleaning'] == true;
                            final cleaningFee = (it['cleaning_fee'] as num? ?? 0).toDouble();
                            final pricePerKg = (it['price_per_kg'] as num? ?? fish?['price_per_kg'] ?? 0).toDouble();
                            final itemTotal = (pricePerKg * itemQty) + cleaningFee;

                            final formattedItemQty = itemQty < 1.0
                                ? '${(itemQty * 1000).toInt()}g'
                                : '${itemQty.toStringAsFixed(itemQty.truncateToDouble() == itemQty ? 0 : 1)} kg';

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.toString(),
                                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                                      ),
                                      if (tamil.isNotEmpty) ...[
                                        Text(
                                          tamil,
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(color: const Color(0xFFFDE68A)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.content_cut_rounded, size: 12, color: Color(0xFFD97706)),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    _formatCuttingType(itemCutting),
                                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (withClean) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFECFDF5),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: const Color(0xFFA7F3D0)),
                                              ),
                                              child: Text(
                                                cleaningFee > 0 ? 'Cleaned (+₹${cleaningFee.toStringAsFixed(0)})' : 'Cleaned',
                                                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _brandColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        formattedItemQty,
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w900, color: _brandColor),
                                      ),
                                    ),
                                    if (itemTotal > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '₹${itemTotal.toStringAsFixed(0)}',
                                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Weight Proof Thumbnail if available
              if (weightProofUrl != null && weightProofUrl.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: OptimizedImage(
                          imageUrl: weightProofUrl,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          memCacheWidth: 100,
                          memCacheHeight: 100,
                          errorWidget: const Icon(Icons.scale_rounded, size: 24, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verified Scale Photo Attached',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                            Text(
                              'Captured during Weight stage',
                              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Mandatory Checklist
              Text(
                'MANDATORY PACKING CHECKLIST',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),

              _buildChecklistTile(
                title: 'Correct fish & cutting style verified',
                value: _isCutVerified,
                onChanged: (val) => setState(() => _isCutVerified = val ?? false),
              ),
              _buildChecklistTile(
                title: 'Leak-proof food-grade pouch sealed',
                value: _isPouchSealed,
                onChanged: (val) => setState(() => _isPouchSealed = val ?? false),
              ),
              _buildChecklistTile(
                title: 'Order QR barcode tag securely affixed',
                value: _isTagAttached,
                onChanged: (val) => setState(() => _isTagAttached = val ?? false),
              ),
              _buildChecklistTile(
                title: 'Gel ice pack placed in thermal carry bag',
                value: _isIcePackPlaced,
                onChanged: (val) => setState(() => _isIcePackPlaced = val ?? false),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'CANCEL',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: allChecklistPassed
                              ? [_brandColor, _brandColor.withValues(alpha: 0.88)]
                              : [const Color(0xFF94A3B8), const Color(0xFF64748B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: allChecklistPassed
                            ? [
                                BoxShadow(
                                  color: _brandColor.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: allChecklistPassed
                              ? () {
                                  AppHaptics.success();
                                  Navigator.pop(context);
                                  widget.onConfirmed();
                                }
                              : null,
                          child: Center(
                            child: Text(
                              'VERIFY & MARK PACKED',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistTile({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () {
        AppHaptics.selectionClick();
        onChanged(!value);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: _brandColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                  color: value ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
