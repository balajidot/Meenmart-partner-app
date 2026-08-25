import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/app_update_service.dart';
import '../drawer/partner_drawer.dart';
import 'delivery_order_card.dart';

class DeliveryHomeScreen extends StatefulWidget {
  const DeliveryHomeScreen({super.key});

  @override
  State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State<DeliveryHomeScreen> {
  final SoundService _soundService = SoundService();
  bool _isOnline = true;
  bool _isLoading = true;
  List<Map<String, dynamic>> _liveOrders = [];
  RealtimeChannel? _ordersSubscription;
  String _selectedFilter = 'active'; // 'active' | 'out_for_delivery' | 'delivered'

  @override
  void initState() {
    super.initState();
    _fetchLiveDeliveryOrders();
    _subscribeRealtimeOrders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPrompt(context);
        AppUpdateService().subscribeRealtime(context);
      }
    });
  }

  @override
  void dispose() {
    _ordersSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchLiveDeliveryOrders() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final userId = db.auth.currentUser?.id;
      if (userId == null) throw StateError('Session expired');
      final partner = await db
          .from('delivery_partners')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      if (partner == null) throw StateError('No delivery-partner profile is linked to this account');
      final response = await db
          .from('orders')
          .select('*, order_items(*, fish_items(*))')
          .eq('delivery_partner_id', partner['id'])
          .inFilter('status', ['out_for_delivery', 'delivered'])
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _liveOrders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching live delivery orders: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeRealtimeOrders() {
    _ordersSubscription = Supabase.instance.client
        .channel('public:delivery_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final newRec = payload.newRecord;
            final oldRec = payload.oldRecord;
            final newStatus = newRec['status']?.toString().toLowerCase();
            final oldStatus = oldRec['status']?.toString().toLowerCase();

            // Alert sound when a new order is inserted or an existing order is dispatched/handed over
            if (payload.eventType == PostgresChangeEvent.insert ||
                (payload.eventType == PostgresChangeEvent.update &&
                    newStatus == 'out_for_delivery' &&
                    oldStatus != 'out_for_delivery')) {
              HapticService.heavyImpact();
              _soundService.playNewOrderChime();
            }
            _fetchLiveDeliveryOrders();
          },
        )
        .subscribe();
  }

  Future<void> _updateOrderStatus(int orderId, String newStatus) async {
    HapticService.heavyImpact();
    _soundService.playSuccessChime();

    try {
      if (newStatus != 'delivered') {
        throw StateError('Only the store manager can dispatch an order.');
      }
      final result = await Supabase.instance.client.rpc(
        'complete_assigned_delivery',
        params: {'p_order_id': orderId},
      );
      if (result == null) throw StateError('Delivery completion was not saved');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: newStatus == 'delivered' ? const Color(0xFF16A34A) : AppColors.deliveryBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(
              newStatus == 'delivered'
                  ? '🎉 Order delivered successfully!'
                  : '🛵 Order status updated to Out for Delivery!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        );
        _fetchLiveDeliveryOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error updating status: $e'),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_selectedFilter == 'out_for_delivery') {
      return _liveOrders.where((o) => o['status'] == 'out_for_delivery').toList();
    } else if (_selectedFilter == 'delivered') {
      return _liveOrders.where((o) => o['status'] == 'delivered').toList();
    }
    return _liveOrders.where((o) => o['status'] == 'out_for_delivery').toList();
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _liveOrders.where((o) => o['status'] == 'out_for_delivery').toList();
    final outForDeliveryCount = _liveOrders.where((o) => o['status'] == 'out_for_delivery').length;
    final deliveredTodayCount = _liveOrders.where((o) => o['status'] == 'delivered').length;

    // Total COD cash to collect
    final codTotal = activeOrders
        .where((o) => (o['payment_method'] ?? 'cod').toString().toLowerCase() == 'cod')
        .fold<double>(0.0, (sum, o) => sum + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0.0));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/icons/store_logo.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MeenMart Partner',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.navyBlue,
                    ),
                  ),
                  Text(
                    'Live Delivery Tracker',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 🟢 Online / Offline Pill Switch
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isOnline ? const Color(0xFFF0FDF4) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isOnline ? const Color(0xFFBBF7D0) : const Color(0xFFCBD5E1),
              ),
            ),
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isOnline = !_isOnline);
              },
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isOnline ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _isOnline ? const Color(0xFF15803D) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.navyBlue),
            onPressed: () {
              HapticService.lightImpact();
              _fetchLiveDeliveryOrders();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLiveDeliveryOrders,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Dashboard Metrics Row ──
                    _buildMetricsGrid(activeOrders.length, outForDeliveryCount, deliveredTodayCount, codTotal),
                    const SizedBox(height: 20),

                    // ── Filter Chips ──
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('active', '🔥 Active (${activeOrders.length})'),
                          const SizedBox(width: 8),
                          _buildFilterChip('out_for_delivery', '🛵 Out for Delivery ($outForDeliveryCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('delivered', '✅ Delivered ($deliveredTodayCount)'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Orders List ──
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_filteredOrders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.local_shipping_outlined, size: 48, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No delivery orders right now',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'New dispatched orders will appear here automatically.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final order = _filteredOrders[index];
                      final orderId = int.tryParse(order['id'].toString()) ?? 0;
                      return DeliveryOrderCard(
                        key: ValueKey(orderId),
                        order: order,
                        onStatusUpdate: (newStatus) => _updateOrderStatus(orderId, newStatus),
                      );
                    },
                    childCount: _filteredOrders.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(int activeCount, int outCount, int deliveredCount, double codTotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  'In Hand',
                  '$activeCount',
                  const Color(0xFFF0FDF4),
                  const Color(0xFF16A34A),
                  Icons.inventory_2_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricItem(
                  'On The Way',
                  '$outCount',
                  const Color(0xFFEFF6FF),
                  const Color(0xFF2563EB),
                  Icons.two_wheeler_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricItem(
                  'Delivered Today',
                  '$deliveredCount',
                  const Color(0xFFFAF5FF),
                  const Color(0xFF9333EA),
                  Icons.check_circle_rounded,
                ),
              ),
            ],
          ),
          if (codTotal > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.payments_rounded, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Total Pending COD to Collect:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '₹${codTotal.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color bg, Color iconColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.navyBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansTamil(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String id, String label) {
    final isSelected = _selectedFilter == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = id);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navyBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.navyBlue : const Color(0xFFCBD5E1),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.navyBlue.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansTamil(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
