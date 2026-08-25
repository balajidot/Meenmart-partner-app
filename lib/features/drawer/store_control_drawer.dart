import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';

class StoreControlDrawer extends StatefulWidget {
  final VoidCallback? onRefreshRequested;

  const StoreControlDrawer({
    super.key,
    this.onRefreshRequested,
  });

  @override
  State<StoreControlDrawer> createState() => _StoreControlDrawerState();
}

class _StoreControlDrawerState extends State<StoreControlDrawer> {
  String _selectedTab = 'analytics'; // 'analytics', 'profile', 'partners', 'settings'

  // Dynamic Analytics Data
  double _todayRevenue = 0.0;
  int _todayOrders = 0;
  int _todayPackedCount = 0;

  double _weeklyRevenue = 0.0;
  int _weeklyOrders = 0;
  int _weeklyPackedCount = 0;

  double _monthlyRevenue = 0.0;
  int _monthlyOrders = 0;
  int _monthlyPackedCount = 0;

  final List<double> _weeklyGraphValues = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  final List<String> _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  List<Map<String, dynamic>> _deliveryPartners = [];

  @override
  void initState() {
    super.initState();
    _fetchStoreMetrics();
  }

  Future<void> _fetchStoreMetrics() async {
    try {
      final db = Supabase.instance.client;
      final orderRows = await db.from('orders').select('total_price, created_at, status');

      double todayRev = 0;
      int todayCnt = 0;
      int todayP = 0;

      double weekRev = 0;
      int weekCnt = 0;
      int weekP = 0;

      double monthRev = 0;
      int monthCnt = 0;
      int monthP = 0;

      final now = DateTime.now();
      if (orderRows.isNotEmpty) {
        for (var row in orderRows) {
          final price = (row['total_price'] as num? ?? 0).toDouble();
          final status = (row['status'] ?? '').toString().toLowerCase();
          final isDelivered = status == 'delivered' || status == 'completed';
          final isPacked = status == 'packed' || status == 'handed_over' || status == 'completed' || status == 'out_for_delivery';
          final isCancelled = status == 'cancelled' || status == 'cancel_requested';

          final dtStr = row['created_at']?.toString();
          if (dtStr != null && !isCancelled) {
            try {
              final dt = DateTime.parse(dtStr);
              final diffDays = now.difference(dt).inDays;

              if (diffDays < 1 && dt.day == now.day) {
                if (isDelivered) todayRev += price;
                todayCnt++;
                if (isPacked) todayP++;
              }
              if (diffDays <= 7) {
                if (isDelivered) weekRev += price;
                weekCnt++;
                if (isPacked) weekP++;
              }
              if (diffDays <= 30) {
                if (isDelivered) monthRev += price;
                monthCnt++;
                if (isPacked) monthP++;
              }
            } catch (_) {}
          }
        }
      }

      // Fetch active delivery partners
      List<Map<String, dynamic>> partners = [];
      try {
        final partnerRows = await db.from('delivery_partners').select('*').order('id', ascending: true);
        partners = List<Map<String, dynamic>>.from(partnerRows);
      } catch (_) {
        try {
          final staffRows = await db.from('store_staff').select('*').order('name', ascending: true);
          partners = staffRows.where((s) {
            final roles = (s['roles'] as List?) ?? [];
            final roleStr = s['role']?.toString() ?? '';
            return roles.contains('delivery_partner') || roles.contains('delivery') || roleStr.contains('delivery');
          }).map((s) => {
            'name': s['name'] ?? 'Delivery Partner',
            'phone': s['phone'] ?? '',
            'vehicle': s['vehicle_number'] ?? 'TN18-BIKE',
            'status': s['status'] ?? 'Available',
          }).toList();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _todayRevenue = todayRev;
          _todayOrders = todayCnt;
          _todayPackedCount = todayP;
          _weeklyRevenue = weekRev;
          _weeklyOrders = weekCnt;
          _weeklyPackedCount = weekP;
          _monthlyRevenue = monthRev;
          _monthlyOrders = monthCnt;
          _monthlyPackedCount = monthP;
          _deliveryPartners = partners;
        });
      }
    } catch (e) {
      debugPrint('Store metrics fetch warning: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // Executive Clean White Header Banner
          Container(
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/store_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MEENMART STORE',
                            style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A), letterSpacing: 0.2),
                          ),
                          Text(
                            'Pazhaverkadu Operational Hub',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle_rounded, color: Color(0xFF059669), size: 7),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE MARKET HUB ONLINE',
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Drawer Navigation Options
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  icon: Icons.bar_chart_rounded,
                  title: 'Analytics & Sales Tracking',
                  tamilSubtitle: 'Sales & packing metrics',
                  tabKey: 'analytics',
                ),
                _buildDrawerItem(
                  icon: Icons.store_rounded,
                  title: 'Store Profile & Hub Location',
                  tamilSubtitle: 'Store profile & address',
                  tabKey: 'profile',
                ),
                _buildDrawerItem(
                  icon: Icons.delivery_dining_rounded,
                  title: 'Delivery Partners Roster',
                  tamilSubtitle: 'Active delivery fleet',
                  tabKey: 'partners',
                ),
                _buildDrawerItem(
                  icon: Icons.tune_rounded,
                  title: 'System & Audio Settings',
                  tamilSubtitle: 'App preferences & sound',
                  tabKey: 'settings',
                ),
                const Divider(height: 24, indent: 16, endIndent: 16),

                // CONTENT BODY FOR SELECTED TAB
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _buildTabContent(),
                ),
              ],
            ),
          ),

          // Brand Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Image.asset(
                    'assets/icons/store_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'MeenMart Store Control v1.0',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Footer Logout Button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  AppHaptics.mediumImpact();
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (_) {}
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('LOGOUT STORE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String tamilSubtitle,
    required String tabKey,
  }) {
    final isSel = _selectedTab == tabKey;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSel ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: isSel ? AppColors.primary : AppColors.textSecondary, size: 22),
        title: Text(
          title,
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: isSel ? FontWeight.w900 : FontWeight.w700, color: isSel ? AppColors.navyBlue : AppColors.textPrimary),
        ),
        subtitle: Text(
          tamilSubtitle,
          style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary),
        ),
        onTap: () {
          AppHaptics.selectionClick();
          setState(() {
            _selectedTab = tabKey;
          });
        },
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 'analytics':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PACKING TRACKING CARDS (TODAY, WEEKLY, MONTHLY PACKED)
            Text('PACKING & FULFILLMENT TRACKING', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
            const SizedBox(height: 8),
            _buildPackingSummaryGrid(),
            const SizedBox(height: 14),

            // PERFORMANCE BAR GRAPH CHART
            _buildPerformanceBarGraph(),
            const SizedBox(height: 14),

            // REVENUE & SALES TRACKING CARDS
            Text('REVENUE & SALES TRACKING', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
            const SizedBox(height: 8),
            _buildMetricCard(
              title: "TODAY'S SALES",
              revenue: _todayRevenue,
              orders: _todayOrders,
              color: AppColors.accent,
              icon: Icons.today_rounded,
            ),
            const SizedBox(height: 8),
            _buildMetricCard(
              title: "WEEKLY SALES",
              revenue: _weeklyRevenue,
              orders: _weeklyOrders,
              color: AppColors.primary,
              icon: Icons.date_range_rounded,
            ),
            const SizedBox(height: 8),
            _buildMetricCard(
              title: "MONTHLY SALES",
              revenue: _monthlyRevenue,
              orders: _monthlyOrders,
              color: const Color(0xFF8B5CF6),
              icon: Icons.calendar_month_rounded,
            ),
          ],
        );

      case 'profile':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('STORE PROFILE & HUB INFO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
              const SizedBox(height: 8),
              _buildInfoRow('Store Name:', 'MeenMart Fresh Seafood Store'),
              _buildInfoRow('Hub Location:', 'Pazhaverkadu Operational Hub'),
              _buildInfoRow('Contact Phone:', '+91 93843 32235'),
              _buildInfoRow('Operating Hours:', '05:00 AM - 09:00 PM'),
              _buildInfoRow('Status:', 'Active & Dispatching'),
            ],
          ),
        );

      case 'partners':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DELIVERY PARTNERS ROSTER', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
            const SizedBox(height: 8),
            ..._deliveryPartners.map((p) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['name']?.toString() ?? 'Delivery Partner', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyBlue)),
                          Text('${p['phone'] ?? ''} • ${p['vehicle'] ?? 'TN18-BIKE'}', style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(p['status']?.toString() ?? 'Available', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.accent)),
                    ),
                  ],
                ),
              );
            }),
          ],
        );

      case 'settings':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AUDIO & VIBRATION SETTINGS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
              title: Text('Order Notification Chime', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
              trailing: Switch.adaptive(value: true, activeThumbColor: AppColors.primary, onChanged: (_) {}),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vibration_rounded, color: AppColors.accent),
              title: Text('Haptic Vibration Feedback', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
              trailing: Switch.adaptive(value: true, activeThumbColor: AppColors.accent, onChanged: (_) {}),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPackingSummaryGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPackingMetricTile(
                label: 'TODAY PACKED',
                count: '$_todayPackedCount Packages',
                color: AppColors.accent,
                icon: Icons.inventory_2_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPackingMetricTile(
                label: 'WEEKLY PACKED',
                count: '$_weeklyPackedCount Packages',
                color: AppColors.primary,
                icon: Icons.all_inbox_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildPackingMetricTile(
          label: 'MONTHLY PACKED',
          count: '$_monthlyPackedCount Packages Completed',
          color: const Color(0xFF8B5CF6),
          icon: Icons.task_alt_rounded,
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildPackingMetricTile({
    required String label,
    required String count,
    required Color color,
    required IconData icon,
    bool isFullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
                Text(count, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceBarGraph() {
    final maxVal = _weeklyGraphValues.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEKLY PACKING GRAPH 📊',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 0.8),
                  ),
                  Text(
                    'Fulfillment & Dispatch Activity',
                    style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white70),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('98% Rate', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 95,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_weeklyGraphValues.length, (idx) {
                final heightPct = maxVal > 0 ? (_weeklyGraphValues[idx] / maxVal) : 0.2;
                final isToday = idx == 5; // Saturday/Sunday peak
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${_weeklyGraphValues[idx].toInt()}',
                      style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: isToday ? AppColors.accent : Colors.white70),
                    ),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 16,
                      height: 58 * heightPct,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isToday
                              ? [AppColors.accent, const Color(0xFF34D399)]
                              : [AppColors.primary, const Color(0xFF60A5FA)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _weekDays[idx],
                      style: GoogleFonts.inter(fontSize: 8.5, fontWeight: isToday ? FontWeight.w900 : FontWeight.w600, color: isToday ? AppColors.accent : Colors.white60),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required double revenue,
    required int orders,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text('₹${revenue.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
            child: Text('$orders Orders', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.navyBlue)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
          Expanded(child: Text(val, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.navyBlue))),
        ],
      ),
    );
  }
}
