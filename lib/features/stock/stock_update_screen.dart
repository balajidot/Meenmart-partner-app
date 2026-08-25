import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/inventory_repository.dart';
import '../drawer/partner_drawer.dart';

class StockUpdateScreen extends StatefulWidget {
  const StockUpdateScreen({super.key});

  @override
  State<StockUpdateScreen> createState() => _StockUpdateScreenState();
}

class _StockUpdateScreenState extends State<StockUpdateScreen> {
  List<Map<String, dynamic>> _fishItems = [];
  bool _isLoading = true;
  final SoundService _soundService = SoundService();

  @override
  void initState() {
    super.initState();
    _fetchStockItems();
  }

  Future<void> _fetchStockItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryRepository().fetchInventory(forceRefresh: true);

      if (mounted) {
        setState(() {
          _fishItems = List<Map<String, dynamic>>.from(items);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Stock fetch error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleAvailability(int index, bool value) async {
    AppHaptics.selectionClick();
    final item = _fishItems[index];
    final int itemId = (item['id'] as num).toInt();

    setState(() {
      _fishItems[index]['is_available'] = value;
      _fishItems[index]['available'] = value;
    });

    try {
      final success = await InventoryRepository().updateItemStockOrPrice(
        itemId: itemId,
        isAvailable: value,
      );

      if (!success) {
        throw Exception('Database update returned false');
      }

      _soundService.playSuccessChime();
      AppHaptics.success();
    } catch (e) {
      debugPrint('Stock update notice: $e');
      // Revert if error
      if (mounted) {
        setState(() {
          _fishItems[index]['is_available'] = !value;
          _fishItems[index]['available'] = !value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update stock: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
                onPressed: () {
                  AppHaptics.selectionClick();
                  Navigator.pop(context);
                },
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
                  onPressed: () {
                    AppHaptics.selectionClick();
                    Scaffold.of(ctx).openDrawer();
                  },
                ),
              ),
        title: Text(
          'Stock & Availability',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16.5, color: const Color(0xFF0F172A)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            tooltip: 'Refresh Catalog',
            onPressed: () {
              AppHaptics.selectionClick();
              _fetchStockItems();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _fetchStockItems,
              child: _fishItems.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text(
                              'No Fish Items Found in Database',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.all(16),
                      itemCount: _fishItems.length,
                      itemBuilder: (context, index) {
                        final item = _fishItems[index];
                        final isAvailable = item['is_available'] == true || item['available'] == true;
                        final name = item['name'] ?? item['name_en'] ?? 'Fish Item';
                        final tamilName = item['tamil_name'] ?? item['name_ta'] ?? '';
                        final stockKg = (item['stock_kg'] as num? ?? 0.0).toDouble();
                        final price = (item['price_per_kg'] as num? ?? 0.0).toDouble();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isAvailable ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.025),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isAvailable ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.set_meal_rounded,
                                  color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$name ${tamilName.isNotEmpty ? "($tamilName)" : ""}',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: isAvailable ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          isAvailable ? 'In Stock: ${stockKg.toStringAsFixed(0)} kg' : 'OUT OF STOCK (இருப்பில்லை)',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                          ),
                                        ),
                                        if (price > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '•  ₹${price.toStringAsFixed(0)}/kg',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: isAvailable,
                                activeThumbColor: const Color(0xFF059669),
                                onChanged: (val) => _toggleAvailability(index, val),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

