import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/optimized_image.dart';
import 'widgets/order_card_widget.dart';

class _ItemWeightEntry {
  final Map<String, dynamic> rawItem;
  final TextEditingController controller;
  final FocusNode focusNode;
  final double bookedWeight;
  final double pricePerKg;
  final double cleaningFee;
  final bool withCleaning;
  final String name;
  final String tamilName;
  final String? imageUrl;
  final String cuttingType;

  _ItemWeightEntry({
    required this.rawItem,
    required this.controller,
    required this.focusNode,
    required this.bookedWeight,
    required this.pricePerKg,
    required this.cleaningFee,
    required this.withCleaning,
    required this.name,
    required this.tamilName,
    this.imageUrl,
    required this.cuttingType,
  });

  double get currentWeight => double.tryParse(controller.text) ?? bookedWeight;
  double get currentSubtotal => (currentWeight * pricePerKg) + (withCleaning ? cleaningFee : 0.0);
  double get bookedSubtotal => (bookedWeight * pricePerKg) + (withCleaning ? cleaningFee : 0.0);
}

class WeightConfirmationDialog extends StatefulWidget {
  final String orderRef;
  final double orderedWeightKg;
  final double pricePerKg;
  final double? orderedTotalPrice;
  final List<dynamic>? orderItems;
  final double deliveryCharge;
  final double discountAmount;
  final Color? themeColor;
  final Function(
    double confirmedWeight,
    double finalPrice,
    String? weightProofUrl,
    List<Map<String, dynamic>> verifiedItems,
  ) onConfirmed;

  const WeightConfirmationDialog({
    super.key,
    required this.orderRef,
    required this.orderedWeightKg,
    required this.pricePerKg,
    this.orderedTotalPrice,
    this.orderItems,
    this.deliveryCharge = 0.0,
    this.discountAmount = 0.0,
    this.themeColor,
    required this.onConfirmed,
  });

  @override
  State<WeightConfirmationDialog> createState() => _WeightConfirmationDialogState();
}

class _WeightConfirmationDialogState extends State<WeightConfirmationDialog> {
  Color get _brandColor => widget.themeColor ?? const Color(0xFF14B8A6);
  final List<_ItemWeightEntry> _entries = [];
  String? _capturedPhotoUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _initEntries();
  }

  void _initEntries() {
    final items = widget.orderItems ?? [];
    if (items.isNotEmpty) {
      for (final raw in items) {
        final it = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
        final fish = it['fish_items'] is Map ? it['fish_items'] : {};
        final name = (fish['name'] ?? fish['name_en'] ?? it['item_name'] ?? 'Fresh Seafood').toString();
        final tamilName = (fish['tamil_name'] ?? '').toString();
        final imageUrl = fish['image_url'] as String?;
        final bookedW = (it['quantity_kg'] as num? ?? 1.0).toDouble();
        final price = (it['price_per_kg'] as num? ?? fish['price_per_kg'] ?? widget.pricePerKg).toDouble();
        final cleaningFee = (it['cleaning_fee'] as num? ?? 0.0).toDouble();
        final withCleaning = it['with_cleaning'] == true;
        final cuttingType = (it['cutting_type'] ?? 'Whole').toString();

        final ctrl = TextEditingController(text: bookedW.toStringAsFixed(2));
        final fNode = FocusNode();
        _entries.add(_ItemWeightEntry(
          rawItem: it,
          controller: ctrl,
          focusNode: fNode,
          bookedWeight: bookedW,
          pricePerKg: price,
          cleaningFee: cleaningFee,
          withCleaning: withCleaning,
          name: name,
          tamilName: tamilName,
          imageUrl: imageUrl,
          cuttingType: cuttingType,
        ));
      }
    } else {
      // Fallback single synthetic item
      final ctrl = TextEditingController(text: widget.orderedWeightKg.toStringAsFixed(2));
      final fNode = FocusNode();
      _entries.add(_ItemWeightEntry(
        rawItem: {'id': 0, 'quantity_kg': widget.orderedWeightKg, 'price_per_kg': widget.pricePerKg},
        controller: ctrl,
        focusNode: fNode,
        bookedWeight: widget.orderedWeightKg,
        pricePerKg: widget.pricePerKg,
        cleaningFee: 0.0,
        withCleaning: false,
        name: 'Fresh Seafood',
        tamilName: '',
        imageUrl: null,
        cuttingType: 'Whole',
      ));
    }
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.controller.dispose();
      e.focusNode.dispose();
    }
    super.dispose();
  }

  double get _totalConfirmedWeight => _entries.fold<double>(0.0, (sum, e) => sum + e.currentWeight);
  double get _totalBookedWeight => _entries.fold<double>(0.0, (sum, e) => sum + e.bookedWeight);
  double get _itemsSubtotal => _entries.fold<double>(0.0, (sum, e) => sum + e.currentSubtotal);
  double get _baseItemsSubtotal => _entries.fold<double>(0.0, (sum, e) => sum + e.bookedSubtotal);

  double get _calculatedFinalTotal {
    final subtotal = _itemsSubtotal;
    if (widget.orderedTotalPrice != null && _entries.length == 1 && _entries.first.rawItem['id'] == 0) {
      final ratio = _entries.first.bookedWeight > 0 ? (_totalConfirmedWeight / _entries.first.bookedWeight) : 1.0;
      return (widget.orderedTotalPrice! * ratio).clamp(0.0, 999999.0);
    }
    return (subtotal + widget.deliveryCharge - widget.discountAmount).clamp(0.0, 999999.0);
  }

  double get _baseTotal {
    if (widget.orderedTotalPrice != null) return widget.orderedTotalPrice!;
    return (_baseItemsSubtotal + widget.deliveryCharge - widget.discountAmount).clamp(0.0, 999999.0);
  }

  void _adjustItemWeight(_ItemWeightEntry entry, double delta) {
    AppHaptics.selectionClick();
    final current = entry.currentWeight;
    final updated = (current + delta).clamp(0.05, 99.0);
    entry.controller.text = updated.toStringAsFixed(2);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = _entries.length > 1;
    final totalW = _totalConfirmedWeight;
    final bookedW = _totalBookedWeight;
    final diffKg = totalW - bookedW;
    final finalPrice = _calculatedFinalTotal;
    final diffPrice = finalPrice - _baseTotal;
    final isChanged = diffKg.abs() > 0.02;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Sticky Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                    ),
                    child: Icon(Icons.scale_rounded, color: _brandColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Weight Verification',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            if (hasMultiple) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  '${_entries.length} Items',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Order: ${widget.orderRef.replaceAll(RegExp(r'0+(?=\d)'), '')}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _brandColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Multi-Item Instruction Callout
                    if (hasMultiple)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Weigh each seafood item on digital scale & adjust below.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // List of Item Cards
                    ..._entries.asMap().entries.map((indexed) {
                      final idx = indexed.key;
                      final entry = indexed.value;
                      return _buildItemWeightCard(entry, idx + 1, hasMultiple);
                    }),

                    const SizedBox(height: 12),

                    // Grand Totals Summary Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _brandColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Scale Weight',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${totalW.toStringAsFixed(2)} kg',
                                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                                      ),
                                      if (diffKg.abs() > 0.02) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: diffKg > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            '${diffKg > 0 ? "+" : ""}${diffKg.toStringAsFixed(2)} kg',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: diffKg > 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              Container(width: 1, height: 32, color: _brandColor.withValues(alpha: 0.2)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Final Bill Amount',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${finalPrice.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: _brandColor),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Weight Difference Notice
                    if (isChanged) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
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
                                    'Variance: ${diffKg > 0 ? "+" : ""}${diffKg.toStringAsFixed(2)} kg (${diffPrice >= 0 ? "+₹" : "-₹"}${diffPrice.abs().toStringAsFixed(0)})',
                                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Customer will be notified to approve the updated net weight.',
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

                    // Camera Photo Proof
                    if (_capturedPhotoUrl != null) ...[
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _brandColor, width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: OptimizedImage(
                                imageUrl: _capturedPhotoUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 400,
                                memCacheHeight: 300,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: InkWell(
                              onTap: () => setState(() => _capturedPhotoUrl = null),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: _isUploading ? null : _captureAndUploadPhoto,
                        icon: _isUploading
                            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _brandColor))
                            : Icon(Icons.camera_alt_rounded, size: 16, color: _brandColor),
                        label: Text(
                          _isUploading ? 'Uploading scale photo...' : 'Take Scale Photo Proof (Optional)',
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: _brandColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 40),
                          side: BorderSide(color: _brandColor.withValues(alpha: 0.35)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          backgroundColor: const Color(0xFFF8FAFC),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Sticky Bottom Action Bar
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Back',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_brandColor, _brandColor.withValues(alpha: 0.88)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _brandColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _isUploading
                              ? null
                              : () {
                                  AppHaptics.success();
                                  final verifiedItems = _entries.map((e) {
                                    return {
                                      'order_item_id': e.rawItem['id'],
                                      'name': e.name,
                                      'old_quantity_kg': e.bookedWeight,
                                      'confirmed_quantity_kg': e.currentWeight,
                                      'proposed_quantity_kg': e.currentWeight,
                                      'price_per_kg': e.pricePerKg,
                                      'cleaning_fee': e.cleaningFee,
                                      'with_cleaning': e.withCleaning,
                                      'cutting_type': e.cuttingType,
                                    };
                                  }).toList();

                                  widget.onConfirmed(totalW, finalPrice, _capturedPhotoUrl, verifiedItems);
                                  Navigator.pop(context);
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isChanged ? 'Send for Approval ➡️' : 'Confirm Weight (${totalW.toStringAsFixed(2)}kg)',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
                                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildItemWeightCard(_ItemWeightEntry entry, int itemIndex, bool hasMultiple) {
    final curWeight = entry.currentWeight;
    final itemSubtotal = entry.currentSubtotal;
    final itemDiff = curWeight - entry.bookedWeight;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: itemDiff.abs() > 0.02 ? _brandColor.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
          width: itemDiff.abs() > 0.02 ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item Thumbnail + Title + Booked Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              OptimizedImage(
                imageUrl: entry.imageUrl,
                width: 40,
                height: 40,
                memCacheWidth: 88,
                memCacheHeight: 88,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (hasMultiple) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$itemIndex',
                              style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569)),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            entry.name,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (entry.tamilName.isNotEmpty) ...[
                      Text(
                        entry.tamilName,
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          OrderCardWidget.formatCuttingTypeDisplay(entry.cuttingType),
                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                        ),
                        if (entry.withCleaning) ...[
                          Text(
                            '• Cleaned',
                            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                          ),
                        ],
                        Text(
                          '• Booked: ${entry.bookedWeight.toStringAsFixed(2)}kg',
                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        ),
                        Text(
                          '(@ ₹${entry.pricePerKg.toStringAsFixed(0)}/kg)',
                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Scale Input & Quick Adjusters
          Row(
            children: [
              // Digital Scale Weight Input Field
              Container(
                width: 105,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _brandColor, width: 1.5),
                ),
                child: TextField(
                  controller: entry.controller,
                  focusNode: entry.focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: itemIndex == _entries.length ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) {
                    if (itemIndex < _entries.length) {
                      _entries[itemIndex].focusNode.requestFocus();
                    } else {
                      FocusScope.of(context).unfocus();
                    }
                  },
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8, top: 10),
                      child: Text(
                        'kg',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Quick Adjust Pills
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildQuickAdjustPill('-0.10', () => _adjustItemWeight(entry, -0.10))),
                    const SizedBox(width: 4),
                    Expanded(child: _buildQuickAdjustPill('-0.05', () => _adjustItemWeight(entry, -0.05))),
                    const SizedBox(width: 4),
                    Expanded(child: _buildQuickAdjustPill('+0.05', () => _adjustItemWeight(entry, 0.05))),
                    const SizedBox(width: 4),
                    Expanded(child: _buildQuickAdjustPill('+0.10', () => _adjustItemWeight(entry, 0.10))),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Item Subtotal & Difference Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (itemDiff.abs() > 0.02) ...[
                Text(
                  'Diff: ${itemDiff > 0 ? "+" : ""}${itemDiff.toStringAsFixed(2)} kg',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: itemDiff > 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ] else ...[
                Text(
                  'Scale verified',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                ),
              ],
              Text(
                'Subtotal: ₹${itemSubtotal.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdjustPill(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
        ),
      ),
    );
  }

  Future<void> _captureAndUploadPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file == null) return;

    setState(() => _isUploading = true);
    try {
      final cleanRef = widget.orderRef.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'weight_proof_${cleanRef}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final fileBytes = await file.readAsBytes();
      var uploadBytes = fileBytes;
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          fileBytes,
          minWidth: 600,
          minHeight: 600,
          quality: 50,
          format: CompressFormat.jpeg,
        );
        if (compressed.isNotEmpty) {
          uploadBytes = Uint8List.fromList(compressed);
        }
      } catch (_) {}

      final db = Supabase.instance.client;
      await db.storage.from('fish-images').uploadBinary(
        fileName,
        uploadBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '3600', upsert: true),
      );

      final url = db.storage.from('fish-images').getPublicUrl(fileName);
      if (mounted) {
        setState(() => _capturedPhotoUrl = url);
        AppHaptics.success();
      }
    } catch (e) {
      debugPrint('Scale photo upload notice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scale Photo Upload Notice: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}
