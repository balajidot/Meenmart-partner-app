import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/widgets/optimized_image.dart';

class SourcingConfirmationDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Color themeColor;
  final Function(double totalWeightKg, double totalCost, List<Map<String, dynamic>> itemsSummary) onConfirmed;

  const SourcingConfirmationDialog({
    super.key,
    required this.order,
    required this.themeColor,
    required this.onConfirmed,
  });

  @override
  State<SourcingConfirmationDialog> createState() => _SourcingConfirmationDialogState();
}

class _SourcingConfirmationDialogState extends State<SourcingConfirmationDialog> {
  final List<Map<String, dynamic>> _itemControllers = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final items = widget.order['order_items'] as List? ?? [];
    for (var item in items) {
      final fish = item['fish_items'] as Map<String, dynamic>?;
      final orderedQty = (item['quantity_kg'] as num? ?? 1.0).toDouble();
      final defaultPrice = (fish?['price_per_kg'] as num? ?? 500.0).toDouble() * 0.75;

      final weightCtrl = TextEditingController(text: orderedQty.toStringAsFixed(2));
      final costCtrl = TextEditingController(text: (defaultPrice * orderedQty).toStringAsFixed(0));

      _itemControllers.add({
        'item': item,
        'fish': fish,
        'is_procured': true,
        'weight_ctrl': weightCtrl,
        'cost_ctrl': costCtrl,
      });
    }

    if (_itemControllers.isEmpty) {
      _itemControllers.add({
        'item': {'quantity_kg': 1.0, 'cutting_type': 'Curry Cut'},
        'fish': {'name': 'Fresh Fish', 'tamil_name': 'பச்சை மீன்'},
        'is_procured': true,
        'weight_ctrl': TextEditingController(text: '1.00'),
        'cost_ctrl': TextEditingController(text: '400'),
      });
    }
  }

  @override
  void dispose() {
    for (var row in _itemControllers) {
      row['weight_ctrl'].dispose();
      row['cost_ctrl'].dispose();
    }
    super.dispose();
  }

  double get _totalOrderedWeight {
    final items = widget.order['order_items'] as List? ?? [];
    if (items.isEmpty) return 1.0;
    return items.fold<double>(0.0, (sum, it) => sum + (it['quantity_kg'] as num? ?? 1.0).toDouble());
  }

  double get _totalProcuredWeight {
    double sum = 0;
    for (var row in _itemControllers) {
      if (row['is_procured'] == true) {
        sum += double.tryParse(row['weight_ctrl'].text) ?? 0.0;
      }
    }
    return sum;
  }

  double get _totalProcuredCost {
    double sum = 0;
    for (var row in _itemControllers) {
      if (row['is_procured'] == true) {
        sum += double.tryParse(row['cost_ctrl'].text) ?? 0.0;
      }
    }
    return sum;
  }

  String _formatCuttingType(String? rawCutting) {
    if (rawCutting == null || rawCutting.isEmpty) return 'Whole Fish';
    final lower = rawCutting.toLowerCase().trim();
    if (lower.contains('slice') || lower.contains('fry')) {
      return 'Slice Cut';
    } else if (lower.contains('curry')) {
      return 'Curry Cut';
    } else if (lower.contains('biryani')) {
      return 'Biryani Cut';
    } else if (lower.contains('clean')) {
      return 'Cleaned';
    } else if (lower.contains('peel')) {
      return 'Peeled';
    } else if (lower.contains('headless')) {
      return 'Headless';
    }
    return rawCutting;
  }

  @override
  Widget build(BuildContext context) {
    final orderRef = widget.order['order_ref'] ?? 'ORDER #${widget.order['id']}';
    final customerName = widget.order['customer_name'] ?? 'Customer';
    final address = widget.order['delivery_address'] ?? 'Pazhaverkadu area';
    final diffWeight = _totalProcuredWeight - _totalOrderedWeight;
    final isWeightChanged = diffWeight.abs() > 0.02;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 730),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header - Pure Tamil
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.shopping_basket_rounded, color: widget.themeColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seafood Sourcing & Weight Check',
                          style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                        ),
                        Text(
                          'Order: $orderRef',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: widget.themeColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Scrollable Items list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer & Delivery Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, size: 20, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customerName,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                                ),
                                Text(
                                  address,
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.themeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_itemControllers.length} Seafood Items',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: widget.themeColor),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      'Booked Seafood Items:',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
                    ),
                    const SizedBox(height: 8),

                    // Items Checklist & Weight inputs
                    ..._itemControllers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;
                      final fish = row['fish'] as Map<String, dynamic>?;
                      final item = row['item'] as Map<String, dynamic>?;
                      final name = fish?['name'] ?? 'Fresh Fish';
                      final tamilName = fish?['tamil_name'] ?? '';
                      final displayName = tamilName.isNotEmpty ? tamilName : name;
                      final subName = tamilName.isNotEmpty ? name : '';
                      final bookedQty = (item?['quantity_kg'] as num? ?? 1.0).toDouble();
                      final cutting = _formatCuttingType(item?['cutting_type']);
                      final imgUrl = fish?['image_url'] as String?;
                      final isProcured = row['is_procured'] as bool;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isProcured ? Colors.white : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isProcured ? widget.themeColor.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
                            width: isProcured ? 1.5 : 1.0,
                          ),
                          boxShadow: isProcured
                              ? [
                                  BoxShadow(
                                    color: widget.themeColor.withValues(alpha: 0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Fish image / icon
                                if (imgUrl != null && imgUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: OptimizedImage(
                                      imageUrl: imgUrl,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: widget.themeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.set_meal_rounded, color: widget.themeColor, size: 24),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                      ),
                                      if (subName.isNotEmpty)
                                        Text(
                                          subName,
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                        ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Booked: ${bookedQty.toStringAsFixed(1)} kg',
                                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF2563EB)),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              cutting,
                                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox.adaptive(
                                  value: isProcured,
                                  activeColor: widget.themeColor,
                                  onChanged: (val) {
                                    setState(() {
                                      _itemControllers[idx]['is_procured'] = val ?? true;
                                    });
                                  },
                                ),
                              ],
                            ),

                            if (isProcured) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  // Procured Weight
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Sourced Weight (kg)',
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: row['weight_ctrl'] as TextEditingController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            suffixText: 'kg',
                                            suffixStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // Buying Cost
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Buying Cost (₹)',
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: row['cost_ctrl'] as TextEditingController,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            prefixText: '₹ ',
                                            prefixStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Summary Card & Confirmation Button
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('Total Weight', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                            const SizedBox(height: 2),
                            Text(
                              '${_totalProcuredWeight.toStringAsFixed(2)} kg',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: widget.themeColor),
                            ),
                          ],
                        ),
                        Container(height: 26, width: 1, color: const Color(0xFFCBD5E1)),
                        Column(
                          children: [
                            Text('Total Sourcing Cost', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                            const SizedBox(height: 2),
                            Text(
                              '₹${_totalProcuredCost.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (isWeightChanged) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: Color(0xFFD97706), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Weight Variance: ${_totalOrderedWeight.toStringAsFixed(2)}kg ➡️ ${_totalProcuredWeight.toStringAsFixed(2)}kg (${diffWeight > 0 ? "+" : ""}${diffWeight.toStringAsFixed(2)} kg)',
                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'An approval request will be sent to the customer via WhatsApp/App.',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFFB45309)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isWeightChanged ? const Color(0xFFEA580C) : widget.themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() => _isSubmitting = true);
                              final itemsSummary = _itemControllers.map((row) {
                                final fish = row['fish'] as Map<String, dynamic>?;
                                return {
                                  'name': fish?['name'] ?? 'Fresh Fish',
                                  'tamil_name': fish?['tamil_name'] ?? '',
                                  'is_procured': row['is_procured'],
                                  'weight_kg': double.tryParse(row['weight_ctrl'].text) ?? 1.0,
                                  'cost': double.tryParse(row['cost_ctrl'].text) ?? 0.0,
                                };
                              }).toList();

                              widget.onConfirmed(
                                _totalProcuredWeight,
                                _totalProcuredCost,
                                itemsSummary,
                              );
                              Navigator.of(context).pop();
                            },
                      icon: _isSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Icon(isWeightChanged ? Icons.send_rounded : Icons.check_circle_rounded, size: 20),
                      label: Text(
                        _isSubmitting
                            ? 'Saving...'
                            : (isWeightChanged ? 'Send for Approval ➡️' : 'Fish Sourced ➡️ Cleaning'),
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800),
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
}
