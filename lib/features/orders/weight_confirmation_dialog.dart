import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/optimized_image.dart';

class WeightConfirmationDialog extends StatefulWidget {
  final String orderRef;
  final double orderedWeightKg;
  final double pricePerKg;
  final double? orderedTotalPrice;
  final List<dynamic>? orderItems;
  final Color? themeColor;
  final Function(double confirmedWeight, double finalPrice, String? weightProofUrl) onConfirmed;

  const WeightConfirmationDialog({
    super.key,
    required this.orderRef,
    required this.orderedWeightKg,
    required this.pricePerKg,
    this.orderedTotalPrice,
    this.orderItems,
    this.themeColor,
    required this.onConfirmed,
  });

  @override
  State<WeightConfirmationDialog> createState() => _WeightConfirmationDialogState();
}

class _WeightConfirmationDialogState extends State<WeightConfirmationDialog> {
  Color get _brandColor => widget.themeColor ?? const Color(0xFF14B8A6);
  late TextEditingController _weightCtrl;
  late double _calculatedTotal;
  String? _capturedPhotoUrl;
  bool _isUploading = false;

  double get _baseTotal => widget.orderedTotalPrice ?? (widget.orderedWeightKg * widget.pricePerKg);

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(text: widget.orderedWeightKg.toStringAsFixed(2));
    _calculatedTotal = _baseTotal;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  void _updateCalculatedTotal(String val) {
    final weight = double.tryParse(val) ?? widget.orderedWeightKg;
    setState(() {
      if (widget.orderedWeightKg > 0) {
        final ratio = weight / widget.orderedWeightKg;
        _calculatedTotal = (_baseTotal * ratio).clamp(0.0, 999999.0);
      } else {
        _calculatedTotal = weight * widget.pricePerKg;
      }
    });
  }

  void _adjustWeight(double delta) {
    AppHaptics.selectionClick();
    final current = double.tryParse(_weightCtrl.text) ?? widget.orderedWeightKg;
    final updated = (current + delta).clamp(0.05, 99.0);
    _weightCtrl.text = updated.toStringAsFixed(2);
    _updateCalculatedTotal(_weightCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.orderItems ?? [];
    final hasMultipleItems = items.length > 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                    ),
                    child: Icon(Icons.scale_rounded, color: _brandColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Net Weight Confirmation',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: 0.2,
                          ),
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
                ],
              ),
              const SizedBox(height: 14),

              // Ordered Info Card
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Booked Weight',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.orderedWeightKg.toStringAsFixed(2)} kg',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasMultipleItems ? 'Avg Price / kg' : 'Price / kg (₹)',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹${widget.pricePerKg.toStringAsFixed(0)}/kg',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (hasMultipleItems) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 6),
                      Text(
                        'Items: ${items.map((it) {
                          final fish = it['fish_items'] is Map ? it['fish_items'] : {};
                          final name = (fish['name'] ?? it['item_name'] ?? 'Fish').toString();
                          final q = (it['quantity_kg'] as num? ?? 1.0).toDouble();
                          return '$name (${q.toStringAsFixed(1)}kg)';
                        }).join(', ')}',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Actual Cleaned Weight Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Scale Weight (kg):',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Enter weight in kg',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Numeric Input Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _brandColor, width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: _brandColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                  onChanged: _updateCalculatedTotal,
                  decoration: InputDecoration(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 16, top: 12),
                      child: Text(
                        'kg',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Quick Adjust Delta Bar
              Row(
                children: [
                  Expanded(child: _buildQuickAdjustPill('-0.10', () => _adjustWeight(-0.10))),
                  const SizedBox(width: 6),
                  Expanded(child: _buildQuickAdjustPill('-0.05', () => _adjustWeight(-0.05))),
                  const SizedBox(width: 6),
                  Expanded(child: _buildQuickAdjustPill('+0.05', () => _adjustWeight(0.05))),
                  const SizedBox(width: 6),
                  Expanded(child: _buildQuickAdjustPill('+0.10', () => _adjustWeight(0.10))),
                ],
              ),
              const SizedBox(height: 12),

              // Weight Difference & Approval Notice Card
              () {
                final currentW = double.tryParse(_weightCtrl.text) ?? widget.orderedWeightKg;
                final diffKg = currentW - widget.orderedWeightKg;
                final diffPrice = _calculatedTotal - _baseTotal;
                final isChanged = diffKg.abs() > 0.02;

                if (isChanged) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Color(0xFFD97706), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weight Variance: ${diffKg > 0 ? "+" : ""}${diffKg.toStringAsFixed(2)} kg (${diffPrice > 0 ? "+₹" : "-₹"}${diffPrice.abs().toStringAsFixed(0)})',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'An approval request will be sent to the customer via WhatsApp/App.',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }(),

              // Final Bill Amount Card (Synced with _brandColor)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _brandColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Final Amount:',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      '₹${_calculatedTotal.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: _brandColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Camera Photo Proof
              if (_capturedPhotoUrl != null) ...[
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      height: 110,
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
                const SizedBox(height: 12),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _isUploading ? null : _captureAndUploadPhoto,
                  icon: _isUploading
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _brandColor))
                      : Icon(Icons.camera_alt_rounded, size: 18, color: _brandColor),
                  label: Text(
                    _isUploading ? 'Uploading scale photo...' : 'Take Scale Photo (Optional)',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: _brandColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    side: BorderSide(color: _brandColor.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: const Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Action Buttons
              Row(
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
                                  final weight = double.tryParse(_weightCtrl.text) ?? widget.orderedWeightKg;
                                  widget.onConfirmed(weight, _calculatedTotal, _capturedPhotoUrl);
                                  Navigator.pop(context);
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(
                              child: Builder(
                                builder: (context) {
                                  final currentW = double.tryParse(_weightCtrl.text) ?? widget.orderedWeightKg;
                                  final isChanged = (currentW - widget.orderedWeightKg).abs() > 0.02;
                                  return FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      isChanged ? 'Send for Approval ➡️' : 'Confirm Weight',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
                                    ),
                                  );
                                },
                              ),
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

  Widget _buildQuickAdjustPill(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
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
