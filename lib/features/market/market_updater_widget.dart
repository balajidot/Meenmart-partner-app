import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/image_crop_dialog.dart';
import '../../core/widgets/animated_search_hint.dart';

class MarketUpdaterWidget extends StatefulWidget {
  final bool onlyAvailableItems;
  final Color? themeColor;

  const MarketUpdaterWidget({
    super.key,
    this.onlyAvailableItems = false,
    this.themeColor,
  });

  @override
  State<MarketUpdaterWidget> createState() => _MarketUpdaterWidgetState();
}

class _MarketUpdaterWidgetState extends State<MarketUpdaterWidget> {
  Color get _brandColor => widget.themeColor ?? const Color(0xFF059669);
  final SoundService _soundService = SoundService();
  String _searchQuery = '';
  Timer? _searchDebounce;
  String _selectedCategory = 'All';
  String _selectedSort = 'default'; // 'default', 'low_stock', 'high_margin', 'name', 'high_stock'
  bool _isLoading = true;

  // Filter Flags
  bool _showOutOfStockOnly = false;
  bool _showLowStockOnly = false;
  bool _showAvailableOnly = false;

  List<Map<String, dynamic>> _marketItems = [];
  List<String> _categories = ['All', 'Fish', 'Prawns', 'Crab', 'Squid', 'Lobster', 'Dry Fish'];
  RealtimeChannel? _realtimeChannel;

  static const List<Map<String, String>> _supabaseCuttingStyles = [
    {'id': 'curry_cut', 'label': 'Curry Cut'},
    {'id': 'fry_cut', 'label': 'Fry Cut / Slices'},
    {'id': 'whole_cleaned', 'label': 'Whole Cleaned'},
    {'id': 'biryani_cut', 'label': 'Biryani Cut'},
  ];


  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchLiveInventory();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final db = Supabase.instance.client;
      final rows = await db.from('categories').select('name, is_active').order('id', ascending: true);
      final activeCats = List<Map<String, dynamic>>.from(rows)
          .where((c) => c['is_active'] != false)
          .map((c) => (c['name'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toList();

      if (activeCats.isNotEmpty && mounted) {
        setState(() {
          _categories = ['All', ...activeCats];
        });
      }
    } catch (e) {
      debugPrint('Categories fetch notice: $e');
    }
  }

  Future<void> _fetchLiveInventory() async {
    try {
      final db = Supabase.instance.client;
      List<dynamic> rows;
      try {
        rows = await db
            .from('fish_items')
            .select('*')
            .or('is_deleted.eq.false,is_deleted.is.null')
            .order('id', ascending: true);
      } catch (_) {
        rows = await db.from('fish_items').select('*').order('id', ascending: true);
      }

      final items = List<Map<String, dynamic>>.from(rows)
          .where((item) => (item['is_deleted'] ?? false) != true)
          .toList();

      if (mounted) {
        setState(() {
          _marketItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Supabase fish_items fetch notice: $e');
      if (mounted && _marketItems.isEmpty) {
        _useFallbackItems();
      }
    }
  }

  void _useFallbackItems() {
    setState(() {
      _marketItems = [
        {
          'id': 1,
          'category': 'Fish',
          'name': 'Vanjiram (Seer Fish)',
          'tamil_name': 'வஞ்சிரம்',
          'buying_price': 900.0,
          'price_per_kg': 1250.0,
          'stock_kg': 15.5,
          'available': true,
          'has_cleaning': true,
          'cleaning_charge': 30.0,
          'image_url': 'https://images.unsplash.com/photo-1534483509719-3feaee7c30da?w=400',
          'allowed_cutting_types': ['Whole', 'Slices', 'Curry Cut'],
        },
        {
          'id': 2,
          'category': 'Fish',
          'name': 'Pomfret (Vavval)',
          'tamil_name': 'வௌவ்வால்',
          'buying_price': 800.0,
          'price_per_kg': 1100.0,
          'stock_kg': 4.4,
          'available': true,
          'has_cleaning': true,
          'cleaning_charge': 25.0,
          'image_url': 'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=400',
          'allowed_cutting_types': ['Whole', 'Cleaned'],
        },
      ];
      _isLoading = false;
    });
  }

  void _subscribeRealtime() {
    try {
      final db = Supabase.instance.client;
      _realtimeChannel = db.channel('store-fish-items-realtime').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'fish_items',
        callback: (_) => _fetchLiveInventory(),
      );
      _realtimeChannel?.subscribe();
    } catch (e) {
      debugPrint('Realtime channel notice: $e');
    }
  }

  static const _validDbColumns = {
    'name',
    'tamil_name',
    'price_per_kg',
    'category',
    'available',
    'stock_kg',
    'image_url',
    'badge',
    'cleaning_charge',
    'has_cleaning',
    'preparation_minutes',
    'buying_price',
    'is_deleted',
    'min_order_kg',
    'allowed_cutting_types',
    'display_order',
  };

  Future<void> _updateItemInDb(dynamic itemId, Map<String, dynamic> changes) async {
    try {
      final db = Supabase.instance.client;
      final targetId = int.tryParse(itemId.toString()) ?? itemId;

      final cleanChanges = <String, dynamic>{};
      for (final entry in changes.entries) {
        if (entry.value != null && _validDbColumns.contains(entry.key)) {
          cleanChanges[entry.key] = entry.value;
        }
      }

      if (cleanChanges.containsKey('price_per_kg')) {
        cleanChanges['price_per_kg'] = (cleanChanges['price_per_kg'] as num).toDouble();
      }

      await db.from('fish_items').update(cleanChanges).eq('id', targetId);
      debugPrint('✅ Supabase fish_items ($targetId) updated: $cleanChanges');
    } catch (e) {
      debugPrint('❌ Supabase fish_items update error: $e');
    }
  }

  Future<void> _toggleMasterSwitch(bool turnOn) async {
    AppHaptics.mediumImpact();
    setState(() {
      for (var item in _marketItems) {
        item['available'] = turnOn;
      }
    });

    try {
      await Supabase.instance.client.from('fish_items').update({'available': turnOn}).neq('id', 0);
    } catch (e) {
      debugPrint('Master switch update error: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(turnOn ? '✅ All Seafood Items Switched ON' : '⚠️ All Seafood Items Switched OFF'),
          backgroundColor: turnOn ? const Color(0xFF059669) : const Color(0xFFDC2626),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<String?> _pickAndUploadImage(ImageSource source) async {
    return await ImageCropDialog.pickCropAndUpload(
      context: context,
      source: source,
      bucketName: 'fish-images',
      title: 'Adjust & Crop Seafood Photo',
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final name = (item['name'] ?? item['name_en'] ?? 'Seafood Item').toString();
    final tamilName = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();
    final itemId = item['id'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete Item?',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                  ),
                  Text(
                    '$name ${tamilName.isNotEmpty ? "($tamilName)" : ""}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this seafood item from live market inventory?',
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF334155), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      AppHaptics.heavyImpact();
      setState(() {
        _marketItems.removeWhere((i) => i['id'] == itemId);
      });

      if (itemId != null) {
        try {
          final db = Supabase.instance.client;
          await db.from('fish_items').update({'is_deleted': true, 'available': false}).eq('id', itemId);
        } catch (e) {
          debugPrint('Delete fish notice: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('🗑️ $name deleted from inventory', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _adjustStock(Map<String, dynamic> item, double delta) {
    AppHaptics.lightImpact();
    final current = (item['stock_kg'] as num? ?? 0).toDouble();
    final updated = (current + delta).clamp(0.0, 1000.0);
    final shouldBeAvail = updated > 0 ? true : false;

    setState(() {
      item['stock_kg'] = updated;
      item['available'] = shouldBeAvail;
    });

    if (item['id'] != null) {
      _updateItemInDb(item['id'], {
        'stock_kg': updated,
        'available': shouldBeAvail,
      });
    }
  }

  // Quick In-Place Price Adjuster Dial
  void _showQuickPriceAdjustDialog(Map<String, dynamic> item) {
    final buyingPrice = (item['buying_price'] as num? ?? 0).toDouble();
    final currentPrice = (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toDouble();
    final nameEn = (item['name'] ?? item['name_en'] ?? 'Fish').toString();
    final nameTa = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();

    final priceCtrl = TextEditingController(text: currentPrice.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setDialogState) {
            final enteredPrice = double.tryParse(priceCtrl.text) ?? currentPrice;
            final margin = enteredPrice - buyingPrice;
            final marginPercent = enteredPrice > 0 ? ((margin / enteredPrice) * 100) : 0.0;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF059669), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameEn,
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (nameTa.isNotEmpty) ...[
                                Text(
                                  nameTa,
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Purchasing Rate & Live Margin
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Purchased: ₹${buyingPrice.toStringAsFixed(0)}/kg',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: margin >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: margin >= 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                            ),
                            child: Text(
                              margin >= 0
                                   ? '+₹${margin.toStringAsFixed(0)} (${marginPercent.toStringAsFixed(0)}% Margin)'
                                  : 'Loss: -₹${margin.abs().toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: margin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Price Input Field
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                        suffixText: '/ kg',
                        suffixStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w700),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8)),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),

                    // Quick Delta Pills
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [-50.0, -20.0, -10.0, 10.0, 20.0, 50.0].map((delta) {
                        final isPlus = delta > 0;
                        return InkWell(
                          onTap: () {
                            AppHaptics.selectionClick();
                            final curr = double.tryParse(priceCtrl.text) ?? currentPrice;
                            final nxt = (curr + delta).clamp(10.0, 10000.0);
                            priceCtrl.text = nxt.toStringAsFixed(0);
                            setDialogState(() {});
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isPlus ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isPlus ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                            ),
                            child: Text(
                              isPlus ? '+₹${delta.toStringAsFixed(0)}' : '-₹${delta.abs().toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isPlus ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Save / Cancel Actions
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text('CANCEL', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              final finalPrice = double.tryParse(priceCtrl.text) ?? currentPrice;
                              if (item['id'] != null) {
                                _updateItemInDb(item['id'], {'price_per_kg': finalPrice});
                              }
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (mounted) {
                                setState(() {
                                  item['price_per_kg'] = finalPrice;
                                  item['price'] = finalPrice;
                                });
                                AppHaptics.success();
                                _soundService.playSuccessChime();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('⚡ ${item['name']} Price Updated to ₹${finalPrice.toStringAsFixed(0)}/kg'),
                                    backgroundColor: const Color(0xFF059669),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            child: Text('UPDATE PRICE', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Quick In-Place Stock Adjuster Dial
  void _showQuickStockAdjustDialog(Map<String, dynamic> item) {
    final currentStock = (item['stock_kg'] as num? ?? 0).toDouble();
    final nameEn = (item['name'] ?? item['name_en'] ?? 'Fish').toString();
    final nameTa = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();

    final stockCtrl = TextEditingController(text: currentStock.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Icon(Icons.scale_rounded, color: Color(0xFF2563EB), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameEn,
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (nameTa.isNotEmpty) ...[
                                Text(
                                  nameTa,
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Stock Input Field
                    TextField(
                      controller: stockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        suffixText: 'kg',
                        suffixStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF2563EB), fontWeight: FontWeight.w800),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.8)),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),

                    // Quick Arrival Crate Adders
                    Text(
                      'QUICK CRATE ARRIVAL:',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        {'label': '+1 kg', 'val': 1.0},
                        {'label': '+5 kg (Crate)', 'val': 5.0},
                        {'label': '+10 kg (Box)', 'val': 10.0},
                        {'label': '+25 kg (Basket)', 'val': 25.0},
                        {'label': 'Reset to 0kg', 'val': -999.0},
                      ].map((btn) {
                        final val = btn['val'] as double;
                        final isReset = val < 0;
                        return InkWell(
                          onTap: () {
                            AppHaptics.selectionClick();
                            if (isReset) {
                              stockCtrl.text = '0.0';
                            } else {
                              final curr = double.tryParse(stockCtrl.text) ?? currentStock;
                              final nxt = (curr + val).clamp(0.0, 2000.0);
                              stockCtrl.text = nxt.toStringAsFixed(1);
                            }
                            setDialogState(() {});
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isReset ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isReset ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              btn['label'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isReset ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: Text('CANCEL', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              final finalStock = double.tryParse(stockCtrl.text) ?? currentStock;
                              final shouldBeAvail = finalStock > 0;
                              if (item['id'] != null) {
                                _updateItemInDb(item['id'], {
                                  'stock_kg': finalStock,
                                  'available': shouldBeAvail,
                                });
                              }
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (mounted) {
                                setState(() {
                                  item['stock_kg'] = finalStock;
                                  item['available'] = shouldBeAvail;
                                });
                                AppHaptics.success();
                                _soundService.playSuccessChime();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('⚡ ${item['name']} Stock Set to ${finalStock.toStringAsFixed(1)} kg'),
                                    backgroundColor: const Color(0xFF2563EB),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            child: Text('UPDATE STOCK', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Morning Market Bulk Price & Rate Update Sheet
  void _showBulkPriceUpdateSheet() {
    final buyingControllers = <dynamic, TextEditingController>{};
    final sellingControllers = <dynamic, TextEditingController>{};

    for (var item in _marketItems) {
      final id = item['id'];
      final buyingPrice = (item['buying_price'] as num? ?? 0).toDouble();
      final sellingPrice = (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toDouble();

      buyingControllers[id] = TextEditingController(text: buyingPrice > 0 ? buyingPrice.toStringAsFixed(0) : '0');
      sellingControllers[id] = TextEditingController(text: sellingPrice > 0 ? sellingPrice.toStringAsFixed(0) : '0');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setRateState) {
            double totalMargin = 0.0;
            int count = 0;
            for (var item in _marketItems) {
              final id = item['id'];
              final buy = double.tryParse(buyingControllers[id]?.text ?? '0') ?? 0.0;
              final sell = double.tryParse(sellingControllers[id]?.text ?? '0') ?? 0.0;
              if (sell > 0) {
                totalMargin += (sell - buy);
                count++;
              }
            }
            final avgMargin = count > 0 ? (totalMargin / count) : 0.0;

            // Batch Markup Strategy Helpers
            void applyPercentageMarkup(double percentage) {
              AppHaptics.mediumImpact();
              for (var item in _marketItems) {
                final id = item['id'];
                final buy = double.tryParse(buyingControllers[id]?.text ?? '0') ?? 0.0;
                if (buy > 0) {
                  final calculatedSelling = (buy * (1.0 + percentage / 100.0)).round();
                  final rounded = ((calculatedSelling + 4) ~/ 5) * 5;
                  sellingControllers[id]?.text = rounded.toString();
                }
              }
              setRateState(() {});
            }

            void applyFlatMarkup(double flatAdd) {
              AppHaptics.mediumImpact();
              for (var item in _marketItems) {
                final id = item['id'];
                final buy = double.tryParse(buyingControllers[id]?.text ?? '0') ?? 0.0;
                if (buy > 0) {
                  final rounded = (buy + flatAdd).round();
                  sellingControllers[id]?.text = rounded.toString();
                }
              }
              setRateState(() {});
            }

            void resetToCurrent() {
              AppHaptics.selectionClick();
              for (var item in _marketItems) {
                final id = item['id'];
                final buyingPrice = (item['buying_price'] as num? ?? 0).toDouble();
                final sellingPrice = (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toDouble();
                buyingControllers[id]?.text = buyingPrice > 0 ? buyingPrice.toStringAsFixed(0) : '0';
                sellingControllers[id]?.text = sellingPrice > 0 ? sellingPrice.toStringAsFixed(0) : '0';
              }
              setRateState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                top: 14,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Icon(Icons.price_change_rounded, color: Color(0xFFD97706), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BULK RATE CARD',
                                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                              ),
                              Text(
                                'Update buying and selling rates easily in one place',
                                style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Batch Strategy Quick-Pills Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Text(
                              'QUICK MARKUP:',
                              style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 0.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => applyPercentageMarkup(20),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text('🎯 +20% Margin', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF2563EB))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => applyPercentageMarkup(25),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Text('🔥 +25% Margin', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => applyPercentageMarkup(30),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE9D5FF)),
                              ),
                              child: Text('✨ +30% Margin', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF9333EA))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => applyFlatMarkup(50),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text('+₹50 Flat', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => applyFlatMarkup(100),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text('+₹100 Flat', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: resetToCurrent,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text('↺ Reset', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Summary Stats Banner (Zero Overflow)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    'Species: ${_marketItems.length} | Rates Table',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: avgMargin >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: avgMargin >= 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                            ),
                            child: Text(
                              'Avg Margin: ₹${avgMargin.toStringAsFixed(0)} / kg',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: avgMargin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Table Column Headers
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 44),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('SEAFOOD', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 0.3)),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text('BUY RATE', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 0.3)),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 80,
                            child: Text('SELL RATE', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 0.3)),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable List of Species
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _marketItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final item = _marketItems[index];
                          final id = item['id'];
                          final nameEn = (item['name'] ?? item['name_en'] ?? 'Fish').toString();
                          final nameTa = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();
                          final img = item['image_url'] as String?;
                          final buyCtrl = buyingControllers[id]!;
                          final sellCtrl = sellingControllers[id]!;

                          final buyVal = double.tryParse(buyCtrl.text) ?? 0.0;
                          final sellVal = double.tryParse(sellCtrl.text) ?? 0.0;
                          final profit = sellVal - buyVal;
                          final profitPct = sellVal > 0 ? ((profit / sellVal) * 100.0) : 0.0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: (img != null && img.isNotEmpty)
                                          ? CachedNetworkImage(
                                              imageUrl: img,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => Container(width: 44, height: 44, color: const Color(0xFFF1F5F9)),
                                              errorWidget: (context, url, error) => Container(width: 44, height: 44, color: const Color(0xFFF1F5F9), child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF94A3B8))),
                                            )
                                          : Container(width: 44, height: 44, color: const Color(0xFFF1F5F9), child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF94A3B8))),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nameEn,
                                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (nameTa.isNotEmpty) ...[
                                            Text(
                                              nameTa,
                                              style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          const SizedBox(height: 2),
                                          // Margin badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: profit >= 0 ? (profitPct >= 20 ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF)) : const Color(0xFFFEF2F2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              profit >= 0 ? '+₹${profit.toStringAsFixed(0)} (${profitPct.toStringAsFixed(0)}%)' : 'Loss: -₹${profit.abs().toStringAsFixed(0)}',
                                              style: GoogleFonts.inter(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w900,
                                                color: profit >= 0 ? (profitPct >= 20 ? const Color(0xFF059669) : const Color(0xFF2563EB)) : const Color(0xFFDC2626),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // Buying Price Field
                                    SizedBox(
                                      width: 76,
                                      height: 38,
                                      child: TextField(
                                        controller: buyCtrl,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569)),
                                        decoration: InputDecoration(
                                          prefixText: '₹',
                                          prefixStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandColor, width: 1.5)),
                                        ),
                                        onChanged: (_) => setRateState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // Selling Price Field
                                    SizedBox(
                                      width: 80,
                                      height: 38,
                                      child: TextField(
                                        controller: sellCtrl,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: _brandColor),
                                        decoration: InputDecoration(
                                          prefixText: '₹',
                                          prefixStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: _brandColor),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                          filled: true,
                                          fillColor: _brandColor.withValues(alpha: 0.06),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandColor.withValues(alpha: 0.3))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandColor.withValues(alpha: 0.3))),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandColor, width: 1.5)),
                                        ),
                                        onChanged: (_) => setRateState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Micro delta adjusters for this row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('Adjust Sell: ', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        AppHaptics.selectionClick();
                                        final cur = double.tryParse(sellCtrl.text) ?? 0.0;
                                        if (cur >= 10) {
                                          sellCtrl.text = (cur - 10).toStringAsFixed(0);
                                          setRateState(() {});
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                                        child: Text('-10', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF475569))),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        AppHaptics.selectionClick();
                                        final cur = double.tryParse(sellCtrl.text) ?? 0.0;
                                        sellCtrl.text = (cur + 10).toStringAsFixed(0);
                                        setRateState(() {});
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(4)),
                                        child: Text('+10', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        AppHaptics.selectionClick();
                                        final cur = double.tryParse(sellCtrl.text) ?? 0.0;
                                        sellCtrl.text = (cur + 50).toStringAsFixed(0);
                                        setRateState(() {});
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                        child: Text('+50', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF2563EB))),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Hero Sync Button (Theme Sync with _brandColor)
                    Container(
                      width: double.infinity,
                      height: 50,
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
                          onTap: () async {
                            for (var item in _marketItems) {
                              final id = item['id'];
                              final buyCtrl = buyingControllers[id];
                              final sellCtrl = sellingControllers[id];
                              if (buyCtrl != null && sellCtrl != null) {
                                final newBuy = double.tryParse(buyCtrl.text) ?? (item['buying_price'] as num? ?? 0).toDouble();
                                final newSell = double.tryParse(sellCtrl.text) ?? (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toDouble();

                                item['buying_price'] = newBuy;
                                item['price_per_kg'] = newSell;
                                item['price'] = newSell;

                                if (id != null) {
                                  _updateItemInDb(id, {
                                    'buying_price': newBuy,
                                    'price_per_kg': newSell,
                                    'price': newSell,
                                  });
                                }
                              }
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              setState(() {});
                              AppHaptics.success();
                              _soundService.playSuccessChime();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'All Bulk Seafood Rates Updated & Synced!',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: _brandColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                'SYNC ALL RATES TO LIVE MARKET',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Morning Market Bulk Stock-In Sheet
  void _showBulkStockInSheet() {
    final stockControllers = <dynamic, TextEditingController>{};
    for (var item in _marketItems) {
      final id = item['id'];
      final currentStock = (item['stock_kg'] as num? ?? 0).toDouble();
      stockControllers[id] = TextEditingController(text: currentStock.toStringAsFixed(1));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setBulkState) {
            double totalBulkKg = 0.0;
            for (var ctrl in stockControllers.values) {
              totalBulkKg += double.tryParse(ctrl.text) ?? 0.0;
            }

            return Padding(
              padding: EdgeInsets.only(
                top: 14,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _brandColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                          ),
                          child: Icon(Icons.inventory_2_rounded, color: _brandColor, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MORNING BULK STOCK-IN',
                                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                              ),
                              Text(
                                'Quickly update morning market crate arrivals in one view',
                                style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Total Summary Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Stock Active: ${_marketItems.length} Species',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                          ),
                          Text(
                            '${totalBulkKg.toStringAsFixed(1)} kg Total',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: _brandColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Scrollable Table of Items
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _marketItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final item = _marketItems[index];
                          final id = item['id'];
                          final nameEn = (item['name'] ?? item['name_en'] ?? 'Fish').toString();
                          final nameTa = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();
                          final img = item['image_url'] as String?;
                          final ctrl = stockControllers[id]!;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: (img != null && img.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: img,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Container(width: 44, height: 44, color: const Color(0xFFF1F5F9)),
                                          errorWidget: (context, url, error) => Container(width: 44, height: 44, color: const Color(0xFFF1F5F9), child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF94A3B8))),
                                        )
                                      : Container(width: 44, height: 44, color: const Color(0xFFF1F5F9), child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF94A3B8))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nameEn,
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (nameTa.isNotEmpty) ...[
                                        Text(
                                          nameTa,
                                          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        (item['available'] == true) ? '🟢 Available in Market' : '🔴 Out of Stock',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: (item['available'] == true) ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 72,
                                  height: 38,
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                    decoration: InputDecoration(
                                      suffixText: 'kg',
                                      suffixStyle: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandColor, width: 1.5)),
                                    ),
                                    onChanged: (_) => setBulkState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Hero Save Button
                    Container(
                      width: double.infinity,
                      height: 50,
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
                          onTap: () async {
                            for (var item in _marketItems) {
                              final id = item['id'];
                              final ctrl = stockControllers[id];
                              if (ctrl != null) {
                                final newStock = double.tryParse(ctrl.text) ?? (item['stock_kg'] as num? ?? 0).toDouble();
                                final shouldBeAvail = newStock > 0;
                                item['stock_kg'] = newStock;
                                item['available'] = shouldBeAvail;
                                if (id != null) {
                                  _updateItemInDb(id, {'stock_kg': newStock, 'available': shouldBeAvail});
                                }
                              }
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              setState(() {});
                              AppHaptics.success();
                              _soundService.playSuccessChime();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Bulk Morning Stock-In Updated & Synced!',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: _brandColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.sync_rounded, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                'SAVE & SYNC ALL STOCKS',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Add Daily Catch Modal
  void _showAddNewCatchSheet() {
    final nameCtrl = TextEditingController();
    final tamilNameCtrl = TextEditingController();
    final buyingPriceCtrl = TextEditingController(text: '500');
    final priceCtrl = TextEditingController(text: '750');
    final stockCtrl = TextEditingController(text: '10.0');
    final minOrderKgCtrl = TextEditingController(text: '0.5');
    final cleaningFeeCtrl = TextEditingController(text: '25');
    String selectedCategory = _categories.firstWhere((c) => c != 'All', orElse: () => 'Fish');
    String photoUrl = '';
    List<String> selectedCuttings = ['curry_cut', 'fry_cut', 'whole_cleaned'];
    bool hasCleaning = true;
    bool isUploading = false;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setAddState) {
            final buying = double.tryParse(buyingPriceCtrl.text) ?? 0;
            final selling = double.tryParse(priceCtrl.text) ?? 0;
            final margin = selling - buying;

            return Padding(
              padding: EdgeInsets.only(
                top: 12,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header (Clean & Focused: "Add New Item")
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _brandColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.add_shopping_cart_rounded, color: _brandColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add New Item',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                              ),
                              Text(
                                'Add seafood to live market catalog',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),

                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. PRODUCT PHOTO PREVIEW & EDIT CONTROLS
                            Text('ITEM PHOTO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  // Photo Preview Box
                                  Container(
                                    width: 66,
                                    height: 66,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: photoUrl.isNotEmpty ? _brandColor : const Color(0xFFCBD5E1), width: photoUrl.isNotEmpty ? 2 : 1),
                                      color: Colors.white,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: isUploading
                                          ? Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _brandColor)))
                                          : (photoUrl.isNotEmpty && photoUrl.startsWith('http'))
                                              ? CachedNetworkImage(
                                                  imageUrl: photoUrl,
                                                  width: 66,
                                                  height: 66,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _brandColor))),
                                                  errorWidget: (context, url, error) => const Icon(Icons.set_meal_rounded, size: 28, color: Color(0xFF94A3B8)),
                                                )
                                              : Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.add_a_photo_outlined, size: 22, color: _brandColor),
                                                    const SizedBox(height: 2),
                                                    Text('No Photo', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                                                  ],
                                                ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Upload Action Buttons (Camera / Gallery / Delete)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: InkWell(
                                                onTap: isUploading
                                                    ? null
                                                    : () async {
                                                        AppHaptics.selectionClick();
                                                        setAddState(() => isUploading = true);
                                                        final uploadedUrl = await _pickAndUploadImage(ImageSource.camera);
                                                        if (uploadedUrl != null) {
                                                          setAddState(() {
                                                            photoUrl = uploadedUrl;
                                                            isUploading = false;
                                                          });
                                                        } else {
                                                          setAddState(() => isUploading = false);
                                                        }
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: _brandColor.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.camera_alt_rounded, size: 14, color: _brandColor),
                                                      const SizedBox(width: 4),
                                                      Text('Camera', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _brandColor)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: InkWell(
                                                onTap: isUploading
                                                    ? null
                                                    : () async {
                                                        AppHaptics.selectionClick();
                                                        setAddState(() => isUploading = true);
                                                        final uploadedUrl = await _pickAndUploadImage(ImageSource.gallery);
                                                        if (uploadedUrl != null) {
                                                          setAddState(() {
                                                            photoUrl = uploadedUrl;
                                                            isUploading = false;
                                                          });
                                                        } else {
                                                          setAddState(() => isUploading = false);
                                                        }
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(Icons.photo_library_rounded, size: 14, color: Color(0xFF2563EB)),
                                                      const SizedBox(width: 4),
                                                      Text('Gallery', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF1E40AF))),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (photoUrl.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: isUploading
                                                    ? null
                                                    : () {
                                                        AppHaptics.lightImpact();
                                                        setAddState(() => photoUrl = '');
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFEF2F2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFFECACA)),
                                                  ),
                                                  child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          photoUrl.isNotEmpty ? 'Photo selected • Tap to change' : 'Add photo to attract more orders',
                                          style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. CATEGORY SELECTION
                            Text('CATEGORY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.3)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: _categories.where((c) => c != 'All').map((cat) {
                                final isSel = cat == selectedCategory;
                                return ChoiceChip(
                                  label: Text(cat, style: GoogleFonts.inter(fontSize: 11, fontWeight: isSel ? FontWeight.w800 : FontWeight.w600)),
                                  selected: isSel,
                                  selectedColor: _brandColor,
                                  labelStyle: TextStyle(color: isSel ? Colors.white : const Color(0xFF0F172A)),
                                  onSelected: (sel) {
                                    if (sel) setAddState(() => selectedCategory = cat);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),

                            // 3. ITEM NAMES (ENGLISH & TAMIL)
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: nameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Fish Name (English)',
                                      labelStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: tamilNameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'தமிழ் பெயர் (Tamil)',
                                      labelStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // 4. PRICING & PROFIT CARD
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('PRICING & PROFIT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: margin >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          margin >= 0 ? '+₹${margin.toStringAsFixed(0)} Profit' : 'Loss: -₹${margin.abs().toStringAsFixed(0)}',
                                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: margin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: buyingPriceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Buying Rate ₹/kg',
                                            prefixText: '₹ ',
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          ),
                                          onChanged: (_) => setAddState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: priceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Selling Rate ₹/kg',
                                            prefixText: '₹ ',
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          ),
                                          onChanged: (_) => setAddState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 5. STOCK & MINIMUM ORDER QTY
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: stockCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Initial Stock (kg)',
                                      suffixText: 'kg',
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: minOrderKgCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Min Order (kg)',
                                      suffixText: 'kg',
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Quick min kg selector pills
                            Row(
                              children: [
                                Text('Quick Min Qty: ', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                ...['0.25', '0.50', '1.00'].map((m) {
                                  final isMatch = minOrderKgCtrl.text == m;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: InkWell(
                                      onTap: () {
                                        AppHaptics.selectionClick();
                                        setAddState(() => minOrderKgCtrl.text = m);
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isMatch ? _brandColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: isMatch ? _brandColor : const Color(0xFFCBD5E1)),
                                        ),
                                        child: Text('$m kg', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: isMatch ? _brandColor : const Color(0xFF475569))),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // 6. SIZE PREFERENCE & CLEANING OPTIONS CARD
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  // Cleaning Option Toggle
                                  Row(
                                    children: [
                                      const Icon(Icons.cleaning_services_rounded, size: 18, color: Color(0xFF059669)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Cleaning Service Available', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                                            Text('Offer store cutting/cleaning to buyer', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B))),
                                          ],
                                        ),
                                      ),
                                      Transform.scale(
                                        scale: 0.8,
                                        child: Switch.adaptive(
                                          value: hasCleaning,
                                          activeTrackColor: _brandColor,
                                          onChanged: (val) => setAddState(() => hasCleaning = val),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (hasCleaning) ...[
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: cleaningFeeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Cleaning Fee ₹/kg',
                                        prefixText: '₹ ',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 7. 4 ALLOWED CUTTING CHOICES
                            Text('ALLOWED CUTTING CHOICES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.3)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _supabaseCuttingStyles.map((cut) {
                                final cutId = cut['id']!;
                                final cutLabel = cut['label']!;
                                final isSel = selectedCuttings.contains(cutId);
                                return FilterChip(
                                  label: Text(cutLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: isSel ? FontWeight.w800 : FontWeight.w500)),
                                  selected: isSel,
                                  selectedColor: _brandColor.withValues(alpha: 0.12),
                                  labelStyle: TextStyle(color: isSel ? _brandColor : const Color(0xFF0F172A)),
                                  checkmarkColor: _brandColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSel ? _brandColor : const Color(0xFFE2E8F0))),
                                  onSelected: (sel) {
                                    setAddState(() {
                                      if (sel) {
                                        selectedCuttings.add(cutId);
                                      } else {
                                        selectedCuttings.remove(cutId);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Add Button (With Validation & Loading State)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final tamilName = tamilNameCtrl.text.trim();

                                if (name.isEmpty && tamilName.isEmpty) {
                                  AppHaptics.warning();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Please enter Item Name (English or Tamil)'),
                                        backgroundColor: const Color(0xFFDC2626),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final finalName = name.isNotEmpty ? name : tamilName;
                                final buying = double.tryParse(buyingPriceCtrl.text) ?? 0.0;
                                final selling = double.tryParse(priceCtrl.text) ?? 0.0;

                                if (selling <= 0) {
                                  AppHaptics.warning();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Please enter a valid selling price per kg'),
                                        backgroundColor: const Color(0xFFDC2626),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final stock = double.tryParse(stockCtrl.text) ?? 10.0;
                                final minOrderKg = double.tryParse(minOrderKgCtrl.text) ?? 0.5;
                                final cleanFee = double.tryParse(cleaningFeeCtrl.text) ?? 25.0;

                                setAddState(() => isSubmitting = true);

                                final newItemPayload = <String, dynamic>{
                                  'name': finalName,
                                  'tamil_name': tamilName,
                                  'category': selectedCategory,
                                  'buying_price': buying,
                                  'price_per_kg': selling,
                                  'stock_kg': stock,
                                  'min_order_kg': minOrderKg,
                                  'available': stock > 0,
                                  'has_cleaning': hasCleaning,
                                  'cleaning_charge': cleanFee,
                                  'image_url': photoUrl.isNotEmpty ? photoUrl : null,
                                  'badge': null,
                                  'allowed_cutting_types': selectedCuttings,
                                  'preparation_minutes': 15,
                                  'created_at': DateTime.now().toUtc().toIso8601String(),
                                };

                                Map<String, dynamic>? addedRow;
                                try {
                                  final db = Supabase.instance.client;
                                  final inserted = await db.from('fish_items').insert(newItemPayload).select();
                                  if (inserted.isNotEmpty) {
                                    addedRow = Map<String, dynamic>.from(inserted.first);
                                  }
                                } catch (e) {
                                  debugPrint('Add fish error: $e');
                                  addedRow = newItemPayload;
                                }

                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }

                                if (mounted) {
                                  if (addedRow != null) {
                                    setState(() {
                                      _marketItems.insert(0, addedRow!);
                                    });
                                  }
                                  AppHaptics.success();
                                  _soundService.playSuccessChime();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Text('$finalName Added to Live Market!', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                      backgroundColor: _brandColor,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_rounded, size: 20, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ADD TO LIVE MARKET',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Full Customization Bottom Sheet (Presets removed, clean preview & edit)
  void _showComprehensiveEditSheet(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(text: (item['name'] ?? item['name_en'] ?? '').toString());
    final tamilNameCtrl = TextEditingController(text: (item['tamil_name'] ?? item['name_ta'] ?? '').toString());
    final buyingPriceCtrl = TextEditingController(text: (item['buying_price'] as num? ?? 0).toStringAsFixed(0));
    final priceCtrl = TextEditingController(text: (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toStringAsFixed(0));
    final stockCtrl = TextEditingController(text: (item['stock_kg'] as num? ?? 0).toStringAsFixed(1));
    final minOrderKgCtrl = TextEditingController(text: (item['min_order_kg'] as num? ?? 0.5).toStringAsFixed(2));
    final cleaningFeeCtrl = TextEditingController(text: (item['cleaning_charge'] as num? ?? 25.0).toStringAsFixed(0));

    String editPhotoUrl = (item['image_url'] ?? '').toString().trim();
    bool isUploadingPhoto = false;
    bool hasCleaning = (item['has_cleaning'] ?? true) == true;
    bool isAvailable = (item['available'] ?? true) == true;

    List<String> currentCuttings = [];
    final rawCuttings = item['allowed_cutting_types'] ?? item['cutting_types'];
    if (rawCuttings is List) {
      currentCuttings = rawCuttings.map((e) => e.toString()).toList();
    } else {
      currentCuttings = ['curry_cut', 'fry_cut', 'whole_cleaned'];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final buyingPrice = double.tryParse(buyingPriceCtrl.text) ?? 0;
            final sellingPrice = double.tryParse(priceCtrl.text) ?? 0;
            final profitMargin = sellingPrice - buyingPrice;

            return Padding(
              padding: EdgeInsets.only(
                top: 12,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _brandColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.edit_note_rounded, color: _brandColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nameCtrl.text.isNotEmpty ? nameCtrl.text : 'Edit Item',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Update pricing, stock & options',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),

                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Photo Box
                            Text('ITEM PHOTO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.3)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 66,
                                    height: 66,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: editPhotoUrl.isNotEmpty ? _brandColor : const Color(0xFFCBD5E1), width: editPhotoUrl.isNotEmpty ? 2 : 1),
                                      color: Colors.white,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: isUploadingPhoto
                                          ? Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _brandColor)))
                                          : (editPhotoUrl.isNotEmpty && editPhotoUrl.startsWith('http'))
                                              ? CachedNetworkImage(
                                                  imageUrl: editPhotoUrl,
                                                  width: 66,
                                                  height: 66,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _brandColor))),
                                                  errorWidget: (context, url, error) => const Icon(Icons.set_meal_rounded, size: 28, color: Color(0xFF94A3B8)),
                                                )
                                              : Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.add_a_photo_outlined, size: 22, color: _brandColor),
                                                    const SizedBox(height: 2),
                                                    Text('No Photo', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                                                  ],
                                                ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: InkWell(
                                                onTap: isUploadingPhoto
                                                    ? null
                                                    : () async {
                                                        AppHaptics.selectionClick();
                                                        setModalState(() => isUploadingPhoto = true);
                                                        final uploadedUrl = await _pickAndUploadImage(ImageSource.camera);
                                                        if (uploadedUrl != null) {
                                                          setModalState(() {
                                                            editPhotoUrl = uploadedUrl;
                                                            isUploadingPhoto = false;
                                                          });
                                                        } else {
                                                          setModalState(() => isUploadingPhoto = false);
                                                        }
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: _brandColor.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.camera_alt_rounded, size: 14, color: _brandColor),
                                                      const SizedBox(width: 4),
                                                      Text('Camera', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _brandColor)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: InkWell(
                                                onTap: isUploadingPhoto
                                                    ? null
                                                    : () async {
                                                        AppHaptics.selectionClick();
                                                        setModalState(() => isUploadingPhoto = true);
                                                        final uploadedUrl = await _pickAndUploadImage(ImageSource.gallery);
                                                        if (uploadedUrl != null) {
                                                          setModalState(() {
                                                            editPhotoUrl = uploadedUrl;
                                                            isUploadingPhoto = false;
                                                          });
                                                        } else {
                                                          setModalState(() => isUploadingPhoto = false);
                                                        }
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(Icons.photo_library_rounded, size: 14, color: Color(0xFF2563EB)),
                                                      const SizedBox(width: 4),
                                                      Text('Gallery', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF1E40AF)),),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (editPhotoUrl.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: isUploadingPhoto
                                                    ? null
                                                    : () {
                                                        AppHaptics.lightImpact();
                                                        setModalState(() => editPhotoUrl = '');
                                                      },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFEF2F2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFFECACA)),
                                                  ),
                                                  child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          editPhotoUrl.isNotEmpty ? 'Photo selected • Tap to change' : 'Tap to upload item photo',
                                          style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Availability Switch
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isAvailable ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isAvailable ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  Icon(isAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded, color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isAvailable ? 'Item Available for Sale' : 'Out of Stock / Turned OFF',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: isAvailable,
                                    activeTrackColor: _brandColor,
                                    onChanged: (val) => setModalState(() => isAvailable = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Pricing & Profit
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
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('PRICING & PROFIT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: profitMargin >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          profitMargin >= 0 ? '+₹${profitMargin.toStringAsFixed(0)} Profit' : 'Loss: -₹${profitMargin.abs().toStringAsFixed(0)}',
                                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: profitMargin >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: buyingPriceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Buying Rate ₹',
                                            prefixText: '₹ ',
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          ),
                                          onChanged: (_) => setModalState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: priceCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Selling Rate ₹/kg',
                                            prefixText: '₹ ',
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          ),
                                          onChanged: (_) => setModalState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Names
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: nameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'English Name',
                                      labelStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: tamilNameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'தமிழ் பெயர்',
                                      labelStyle: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Stock & Min Order
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: stockCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Current Stock (kg)',
                                      suffixText: 'kg',
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: minOrderKgCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Min Order (kg)',
                                      suffixText: 'kg',
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Options Card (Cleaning)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.cleaning_services_rounded, size: 18, color: Color(0xFF059669)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('Cleaning Service Available', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                                      ),
                                      Transform.scale(
                                        scale: 0.8,
                                        child: Switch.adaptive(
                                          value: hasCleaning,
                                          activeTrackColor: _brandColor,
                                          onChanged: (val) => setModalState(() => hasCleaning = val),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (hasCleaning) ...[
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: cleaningFeeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Cleaning Fee ₹/kg',
                                        prefixText: '₹ ',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 4 Allowed Cutting Styles
                            Text('ALLOWED CUTTING CHOICES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.3)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _supabaseCuttingStyles.map((cut) {
                                final cutId = cut['id']!;
                                final cutLabel = cut['label']!;
                                final isSel = currentCuttings.contains(cutId);
                                return FilterChip(
                                  label: Text(cutLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: isSel ? FontWeight.w800 : FontWeight.w500)),
                                  selected: isSel,
                                  selectedColor: _brandColor.withValues(alpha: 0.12),
                                  labelStyle: TextStyle(color: isSel ? _brandColor : const Color(0xFF0F172A)),
                                  checkmarkColor: _brandColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSel ? _brandColor : const Color(0xFFE2E8F0))),
                                  onSelected: (sel) {
                                    setModalState(() {
                                      if (sel) {
                                        currentCuttings.add(cutId);
                                      } else {
                                        currentCuttings.remove(cutId);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final newName = nameCtrl.text.trim();
                          final newTamilName = tamilNameCtrl.text.trim();
                          final newBuying = double.tryParse(buyingPriceCtrl.text) ?? 0.0;
                          final newSelling = double.tryParse(priceCtrl.text) ?? 0.0;
                          final newStock = double.tryParse(stockCtrl.text) ?? 0.0;
                          final newMinOrder = double.tryParse(minOrderKgCtrl.text) ?? 0.5;
                          final newCleaningFee = double.tryParse(cleaningFeeCtrl.text) ?? 25.0;

                          if (item['id'] != null) {
                            _updateItemInDb(item['id'], {
                              if (newName.isNotEmpty) 'name': newName,
                              if (newTamilName.isNotEmpty) 'tamil_name': newTamilName,
                              'buying_price': newBuying,
                              'price_per_kg': newSelling,
                              'stock_kg': newStock,
                              'min_order_kg': newMinOrder,
                              'available': isAvailable && (newStock > 0),
                              'has_cleaning': hasCleaning,
                              'cleaning_charge': newCleaningFee,
                              'allowed_cutting_types': currentCuttings,
                              'image_url': editPhotoUrl,
                            });
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }

                          if (mounted) {
                            setState(() {
                              if (newName.isNotEmpty) item['name'] = newName;
                              if (newTamilName.isNotEmpty) item['tamil_name'] = newTamilName;
                              item['buying_price'] = newBuying;
                              item['price_per_kg'] = newSelling;
                              item['price'] = newSelling;
                              item['stock_kg'] = newStock;
                              item['min_order_kg'] = newMinOrder;
                              item['available'] = isAvailable && (newStock > 0);
                              item['has_cleaning'] = hasCleaning;
                              item['cleaning_charge'] = newCleaningFee;
                              item['allowed_cutting_types'] = currentCuttings;
                              item['image_url'] = editPhotoUrl;
                            });
                            AppHaptics.success();
                            _soundService.playSuccessChime();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text('${item['name']} Updated & Synced!', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                backgroundColor: _brandColor,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'SAVE CHANGES',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Delete Item Option Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          backgroundColor: const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteItem(item);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                        label: Text(
                          'Delete Item from Catalog',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatCuttingLabel(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower == 'curry_cut' || lower == 'curry cut') return 'Curry Cut';
    if (lower == 'fry_cut' || lower == 'fry cut' || lower == 'slices') return 'Fry Cut';
    if (lower == 'whole_cleaned' || lower == 'cleaned' || lower == 'whole') return 'Whole Cleaned';
    if (lower == 'biryani_cut' || lower == 'biryani cut') return 'Biryani Cut';
    if (lower == 'headless') return 'Headless';
    if (lower == 'peeled_and_deveined' || lower == 'peeled & deveined' || lower == 'peeled') return 'Peeled';
    return raw.replaceAll('_', ' ').trim();
  }

  // Enhanced Fish Item Card
  Widget _buildFishItemCard(Map<String, dynamic> item) {
    final nameEn = (item['name'] ?? item['name_en'] ?? 'Fresh Seafood').toString();
    final nameTa = (item['tamil_name'] ?? item['name_ta'] ?? '').toString();
    final buyingPrice = (item['buying_price'] as num? ?? 0).toDouble();
    final sellingPrice = (item['price_per_kg'] as num? ?? item['price'] as num? ?? 0).toDouble();
    final stock = (item['stock_kg'] as num? ?? 0).toDouble();
    final minOrderKg = (item['min_order_kg'] as num? ?? 0.5).toDouble();
    final isAvail = (item['available'] == true) && stock > 0;
    final isLowStock = stock > 0 && stock < 5.0;
    final isOutOfStock = !isAvail || stock <= 0;
    final imageUrl = item['image_url'] as String?;
    final cleaningFee = (item['cleaning_charge'] as num? ?? 25.0).toDouble();
    final hasCleaning = (item['has_cleaning'] ?? true) == true;
    final cuttingTypes = item['allowed_cutting_types'] as List? ?? [];

    final profitMargin = sellingPrice - buyingPrice;
    final profitPercent = sellingPrice > 0 ? ((profitMargin / sellingPrice) * 100) : 0.0;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOutOfStock
                ? const Color(0xFFFECACA)
                : (isLowStock ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Image Thumbnail + Fish Name & Tamil Name + Availability Switch
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _showComprehensiveEditSheet(item),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: (imageUrl != null && imageUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 180,
                                  memCacheHeight: 180,
                                  maxWidthDiskCache: 600,
                                  maxHeightDiskCache: 600,
                                  errorWidget: (context, url, error) => Container(width: 60, height: 60, color: const Color(0xFFF1F5F9), child: Icon(Icons.set_meal_rounded, color: _brandColor, size: 24)),
                                )
                              : Container(width: 60, height: 60, color: const Color(0xFFF1F5F9), child: Icon(Icons.set_meal_rounded, color: _brandColor, size: 24)),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3.5),
                          decoration: BoxDecoration(
                            color: _brandColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 9, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nameEn,
                              style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isLowStock) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                              child: Text('LOW STOCK', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w900, color: const Color(0xFFD97706))),
                            ),
                          ],
                        ],
                      ),
                      if (nameTa.isNotEmpty) ...[
                        Text(
                          nameTa,
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 5),

                      // Clickable Stock Pill (Tap to Quick Adjust)
                      InkWell(
                        onTap: () => _showQuickStockAdjustDialog(item),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isOutOfStock ? const Color(0xFFFEE2E2) : (isLowStock ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isOutOfStock ? const Color(0xFFFCA5A5) : (isLowStock ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isOutOfStock ? const Color(0xFFDC2626) : (isLowStock ? const Color(0xFFD97706) : _brandColor),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOutOfStock ? 'Out of Stock (Tap to set)' : 'Stock: ${stock.toStringAsFixed(1)} kg ✎',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: isOutOfStock ? const Color(0xFFDC2626) : (isLowStock ? const Color(0xFFD97706) : _brandColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: isAvail,
                    activeTrackColor: _brandColor,
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFCBD5E1),
                    onChanged: (val) {
                      AppHaptics.lightImpact();
                      setState(() {
                        item['available'] = val;
                      });
                      if (item['id'] != null) {
                        _updateItemInDb(item['id'] as int, {'available': val});
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Purchasing Rate vs Selling Rate & Live Margin Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Buying: ₹${buyingPrice.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        ),
                        // Tap Selling Rate to Quick Edit
                        InkWell(
                          onTap: () => _showQuickPriceAdjustDialog(item),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _brandColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _brandColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'Selling: ₹${sellingPrice.toStringAsFixed(0)}/kg ✎',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: _brandColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (buyingPrice > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: profitMargin >= 0
                            ? (profitPercent >= 25 ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF))
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: profitMargin >= 0
                              ? (profitPercent >= 25 ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE))
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Text(
                        profitMargin >= 0
                            ? '+₹${profitMargin.toStringAsFixed(0)} (${profitPercent.toStringAsFixed(0)}%)'
                            : 'Loss: -₹${profitMargin.abs().toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: profitMargin >= 0
                              ? (profitPercent >= 25 ? const Color(0xFF059669) : const Color(0xFF2563EB))
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Quick Crate Action Buttons (-1kg, +1kg, +5kg, +10kg) + CUSTOMIZE
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _showComprehensiveEditSheet(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 13, color: Color(0xFF0F172A)),
                          const SizedBox(width: 4),
                          Text(
                            'CUSTOMIZE',
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // -1kg
                  InkWell(
                    onTap: () => _adjustStock(item, -1.0),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text('-1kg', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // +1kg
                  InkWell(
                    onTap: () => _adjustStock(item, 1.0),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text('+1kg', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // +5kg (Crate)
                  InkWell(
                    onTap: () => _adjustStock(item, 5.0),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text('+5kg', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFF2563EB))),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // +10kg (Box)
                  InkWell(
                    onTap: () => _adjustStock(item, 10.0),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE9D5FF)),
                      ),
                      child: Text('+10kg', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFF9333EA))),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // Delete Item Quick Button
                  InkWell(
                    onTap: () => _deleteItem(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ),

            // Badges Row: Min kg, Size Pref, Clean fee, Cutting Types
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                // Min Order KG Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 10, color: Color(0xFFD97706)),
                      const SizedBox(width: 3),
                      Text(
                        'Min: ${minOrderKg.toStringAsFixed(minOrderKg.truncateToDouble() == minOrderKg ? 0 : 2)} kg',
                        style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFFB45309), fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                // Size Preference Pill
                if (hasSizePref) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.straighten_rounded, size: 10, color: Color(0xFF2563EB)),
                        const SizedBox(width: 3),
                        Text('Size: S/M/L', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF1D4ED8), fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
                // Cleaning Fee Pill
                if (hasCleaning) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _brandColor.withValues(alpha: 0.25)),
                    ),
                    child: Text('Clean: ₹${cleaningFee.toStringAsFixed(0)}/kg', style: GoogleFonts.inter(fontSize: 9.5, color: _brandColor, fontWeight: FontWeight.w700)),
                  ),
                ],
                // Allowed Cutting Choices Pills
                ...cuttingTypes.take(3).map((ct) {
                  final formatted = _formatCuttingLabel(ct.toString());
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(formatted, style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF475569), fontWeight: FontWeight.w600)),
                  );
                }),
                if (cuttingTypes.length > 3) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text('+${cuttingTypes.length - 3} cuts', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMarketShimmerList() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 130, height: 16, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(width: 80, height: 14, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildMarketShimmerList();
    }

    final totalSpecies = _marketItems.length;
    final availableCount = _marketItems.where((i) {
      final stock = (i['stock_kg'] as num? ?? 0).toDouble();
      return (i['available'] == true) && stock > 0;
    }).length;
    final lowStockCount = _marketItems.where((i) {
      final stock = (i['stock_kg'] as num? ?? 0).toDouble();
      return stock > 0 && stock < 5.0;
    }).length;
    final outOfStockCount = _marketItems.where((i) {
      final stock = (i['stock_kg'] as num? ?? 0).toDouble();
      final isAvail = (i['available'] == true);
      return !isAvail || stock <= 0;
    }).length;

    // Filter Logic
    var filteredList = _marketItems.where((item) {
      final isAvail = (item['available'] == true);
      final stock = (item['stock_kg'] as num? ?? 0).toDouble();

      if (widget.onlyAvailableItems && (!isAvail || stock <= 0)) {
        return false;
      }

      final category = (item['category'] ?? 'Fish').toString();
      final matchesCategory = _selectedCategory == 'All' || category == _selectedCategory;

      final query = _searchQuery.toLowerCase();
      final name = (item['name'] ?? item['name_en'] ?? '').toString().toLowerCase();
      final tamilName = (item['tamil_name'] ?? item['name_ta'] ?? '').toString().toLowerCase();
      final matchesQuery = name.contains(query) || tamilName.contains(query);

      bool matchesStock = true;
      if (_showOutOfStockOnly) {
        matchesStock = !isAvail || stock <= 0;
      } else if (_showLowStockOnly) {
        matchesStock = stock > 0 && stock < 5.0;
      } else if (_showAvailableOnly) {
        matchesStock = isAvail && stock > 0;
      }

      return matchesCategory && matchesQuery && matchesStock;
    }).toList();

    // Sorting Logic
    if (_selectedSort == 'low_stock') {
      filteredList.sort((a, b) {
        final sa = (a['stock_kg'] as num? ?? 0).toDouble();
        final sb = (b['stock_kg'] as num? ?? 0).toDouble();
        return sa.compareTo(sb);
      });
    } else if (_selectedSort == 'high_margin') {
      filteredList.sort((a, b) {
        final ma = ((a['price_per_kg'] as num? ?? 0) - (a['buying_price'] as num? ?? 0)).toDouble();
        final mb = ((b['price_per_kg'] as num? ?? 0) - (b['buying_price'] as num? ?? 0)).toDouble();
        return mb.compareTo(ma);
      });
    } else if (_selectedSort == 'name') {
      filteredList.sort((a, b) {
        final na = (a['name'] ?? '').toString();
        final nb = (b['name'] ?? '').toString();
        return na.compareTo(nb);
      });
    } else if (_selectedSort == 'high_stock') {
      filteredList.sort((a, b) {
        final sa = (a['stock_kg'] as num? ?? 0).toDouble();
        final sb = (b['stock_kg'] as num? ?? 0).toDouble();
        return sb.compareTo(sa);
      });
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _fetchLiveInventory,
          color: _brandColor,
          backgroundColor: Colors.white,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.only(bottom: 85),
            children: [
              // Executive Compact Control Panel Card
              Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Row (Cleaned: + CATCH removed in favor of floating button)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: _brandColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.storefront_rounded, size: 16, color: _brandColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.onlyAvailableItems ? 'Live Market Available' : 'Market Inventory Control',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.onlyAvailableItems ? 'Live Catch in Store' : 'Daily Sourcing & Stock Management',
                                style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!widget.onlyAvailableItems) ...[
                      const SizedBox(height: 10),
                      // Compact Action Toolbar: Bulk Rates, Bulk Stock, All On, All Off
                      Row(
                        children: [
                          // Bulk Rates
                          Expanded(
                            child: InkWell(
                              onTap: _showBulkPriceUpdateSheet,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.price_change_rounded, size: 14, color: Color(0xFFD97706)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Price Rates',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Bulk Stock
                          Expanded(
                            child: InkWell(
                              onTap: _showBulkStockInSheet,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.inventory_2_rounded, size: 14, color: Color(0xFF2563EB)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Stock Volume',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF1E40AF)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // All On Button
                          InkWell(
                            onTap: () => _toggleMasterSwitch(true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Icon(Icons.power_settings_new_rounded, size: 16, color: Color(0xFF059669)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // All Off Button
                          InkWell(
                            onTap: () => _toggleMasterSwitch(false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: const Icon(Icons.power_off_rounded, size: 16, color: Color(0xFFDC2626)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Interactive Live Metric Status Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // All Species
                          InkWell(
                            onTap: () {
                              AppHaptics.selectionClick();
                              setState(() {
                                _showOutOfStockOnly = false;
                                _showLowStockOnly = false;
                                _showAvailableOnly = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: (!_showOutOfStockOnly && !_showLowStockOnly && !_showAvailableOnly)
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'All ($totalSpecies)',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: (!_showOutOfStockOnly && !_showLowStockOnly && !_showAvailableOnly)
                                      ? Colors.white
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // In-Stock / Live
                          InkWell(
                            onTap: () {
                              AppHaptics.selectionClick();
                              setState(() {
                                _showAvailableOnly = !_showAvailableOnly;
                                _showOutOfStockOnly = false;
                                _showLowStockOnly = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: _showAvailableOnly ? const Color(0xFF059669) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _showAvailableOnly ? Colors.white : const Color(0xFF059669),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Live ($availableCount)',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _showAvailableOnly ? Colors.white : const Color(0xFF065F46),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Low Stock
                          InkWell(
                            onTap: () {
                              AppHaptics.selectionClick();
                              setState(() {
                                _showLowStockOnly = !_showLowStockOnly;
                                _showOutOfStockOnly = false;
                                _showAvailableOnly = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: _showLowStockOnly ? const Color(0xFFD97706) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _showLowStockOnly ? Colors.white : const Color(0xFFD97706),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Low Stock ($lowStockCount)',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _showLowStockOnly ? Colors.white : const Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Out of Stock
                          InkWell(
                            onTap: () {
                              AppHaptics.selectionClick();
                              setState(() {
                                _showOutOfStockOnly = !_showOutOfStockOnly;
                                _showLowStockOnly = false;
                                _showAvailableOnly = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: _showOutOfStockOnly ? const Color(0xFFDC2626) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _showOutOfStockOnly ? Colors.white : const Color(0xFFDC2626),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Sold Out ($outOfStockCount)',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _showOutOfStockOnly ? Colors.white : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Search Field with Sorting Popup
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _searchQuery.isNotEmpty ? _brandColor.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (_searchQuery.isEmpty)
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: IgnorePointer(
                                    child: AnimatedSearchHint(
                                      hints: const [
                                        'Search "Vanjaram / Seer Fish"...',
                                        'Search "Tiger Prawns / Shrimp"...',
                                        'Search "White Pomfret"...',
                                        'Search "Red Snapper / Sankara"...',
                                        'Search "Blue Sea Crab"...',
                                        'Search "Nethili / Anchovy"...',
                                        'Search "Squid / Kanava"...',
                                      ],
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
                                        color: const Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            TextField(
                              onChanged: (val) {
                                _searchDebounce?.cancel();
                                _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                                  if (mounted) {
                                    setState(() => _searchQuery = val);
                                  }
                                });
                              },
                              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(
                                filled: false,
                                fillColor: Colors.transparent,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 17, color: Color(0xFF94A3B8)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            setState(() => _searchQuery = '');
                          },
                        ),
                      PopupMenuButton<String>(
                        initialValue: _selectedSort,
                        tooltip: 'Sort Items',
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        icon: Icon(
                          Icons.sort_rounded,
                          size: 19,
                          color: _selectedSort != 'default' ? _brandColor : const Color(0xFF64748B),
                        ),
                        onSelected: (val) {
                          AppHaptics.selectionClick();
                          setState(() => _selectedSort = val);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'default', child: Text('⚡ Default (Category)')),
                          const PopupMenuItem(value: 'low_stock', child: Text('⚠️ Low Stock First')),
                          const PopupMenuItem(value: 'high_margin', child: Text('💰 Highest Profit Margin')),
                          const PopupMenuItem(value: 'name', child: Text('🔤 Name (A - Z)')),
                          const PopupMenuItem(value: 'high_stock', child: Text('⚖️ Stock (High to Low)')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Categories Bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () {
                          AppHaptics.selectionClick();
                          setState(() {
                            _selectedCategory = cat;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? _brandColor : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? _brandColor : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            cat,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // Fish List
              if (filteredList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.search_off_rounded, size: 40, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        Text(
                          widget.onlyAvailableItems ? 'No available seafood items right now' : 'No seafood matching search/filters',
                          style: GoogleFonts.inter(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: filteredList.map((item) => _buildFishItemCard(item)).toList(),
                  ),
                ),
            ],
          ),
        ),

        // Compact Circular Floating Action Button: + (Simple Add Catch)
        Positioned(
          bottom: 16,
          right: 16,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_brandColor, _brandColor.withValues(alpha: 0.9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _brandColor.withValues(alpha: 0.40),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  AppHaptics.selectionClick();
                  _showAddNewCatchSheet();
                },
                child: const Center(
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
