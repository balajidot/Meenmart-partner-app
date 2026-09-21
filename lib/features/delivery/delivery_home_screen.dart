import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/delivery_tracking_service.dart';
import '../drawer/partner_drawer.dart';
import 'delivery_order_card.dart';

class DeliveryHomeScreen extends StatefulWidget {
  const DeliveryHomeScreen({super.key});

  @override
  State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State<DeliveryHomeScreen>
    with SingleTickerProviderStateMixin {
  final SoundService _soundService = SoundService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _liveOrders = [];
  RealtimeChannel? _ordersSubscription;
  String _selectedFilter = 'active'; // 'active' | 'out_for_delivery' | 'delivered'

  // Duty and Rider State
  String _dutyStatus = 'online'; // 'online' | 'break' | 'offline'
  String _partnerName = 'MeenMart Hero';
  String _vehicleNumber = 'TN18BV2156';
  String _vehicleType = 'Bike';
  String _partnerPhone = '9384332235';
  int? _partnerId;

  // Duty timer: real time since the partner went ONLINE (persisted per user)
  DateTime? _dutyOnlineSince;
  Timer? _dutyTicker;

  String? get _dutyPrefsKey {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid == null ? null : 'duty_online_since_$uid';
  }

  Future<void> _loadDutyStart() async {
    final key = _dutyPrefsKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (mounted) setState(() => _dutyOnlineSince = _dutyStatus == 'online' ? parsed : null);
    } catch (_) {}
  }

  Future<void> _saveDutyStart(DateTime? value) async {
    final key = _dutyPrefsKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value.toIso8601String());
      }
    } catch (_) {}
  }

  // Animation controller for live radar pulse
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _dutyTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // Realtime subscription starts inside _fetchLiveDeliveryOrders once the
    // partner id is known, so it can be filtered to this partner's orders.
    _fetchLiveDeliveryOrders();
  }

  @override
  void dispose() {
    // Do NOT stop GPS here: the drawer uses context.go(), which disposes this
    // screen while the rider is still ON DUTY. Tracking stops only when duty
    // goes Break/Offline or on sign-out (see AuthNotifier).
    _radarController.dispose();
    _dutyTicker?.cancel();
    _ordersSubscription?.unsubscribe();
    super.dispose();
  }

  String _formatDutyDuration() {
    final since = _dutyOnlineSince;
    if (since == null) return '--';
    final diff = DateTime.now().difference(since);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  static const _deliveryStatuses = ['packed', 'out_for_delivery', 'delivered'];
  int _fetchSeq = 0; // ignore responses from older overlapping refreshes

  Future<void> _fetchLiveDeliveryOrders() async {
    if (!mounted) return;
    // Full-screen spinner only on first load; realtime refreshes update silently.
    if (_liveOrders.isEmpty) setState(() => _isLoading = true);

    // Partner already identified: only the order list needs refreshing.
    if (_partnerId != null) {
      final seq = ++_fetchSeq;
      try {
        final response = await Supabase.instance.client
            .from('orders')
            .select('*, order_items(*, fish_items(*))')
            .eq('delivery_partner_id', _partnerId!)
            .inFilter('status', _deliveryStatuses)
            .order('created_at', ascending: false)
            .limit(50);
        if (mounted && seq == _fetchSeq) {
          setState(() {
            _liveOrders = List<Map<String, dynamic>>.from(response);
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error refreshing delivery orders: $e');
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final db = Supabase.instance.client;
      final user = db.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Check partner row by user_id first
      var partner = await db
          .from('delivery_partners')
          .select('id, name, phone, vehicle_number, vehicle_type, duty_status')
          .eq('user_id', user.id)
          .maybeSingle();

      // No partner row linked to this login. Do NOT fall back to matching by
      // phone: that can attach this login to someone else's partner record,
      // and the server rejects delivery completion for it anyway.
      if (partner == null) {
        final staff = await db
            .from('store_staff')
            .select('name, phone, roles, vehicle_number')
            .eq('auth_id', user.id)
            .maybeSingle();

        if (staff != null) {
          _partnerName = staff['name']?.toString() ?? 'MeenMart Hero';
          if (staff['vehicle_number'] != null) {
            _vehicleNumber = staff['vehicle_number'].toString();
          }
        }

        final roles = (staff?['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final isAdminOrManager = roles.contains('admin') || roles.contains('store_manager');

        // Store Manager / Admin fallback view
        if (partner == null && isAdminOrManager) {
          final allDeliveryOrders = await db
              .from('orders')
              .select('*, order_items(*, fish_items(*))')
              .inFilter('status', ['packed', 'out_for_delivery', 'delivered'])
              .order('created_at', ascending: false)
              .limit(50);

          if (mounted) {
            setState(() {
              _liveOrders = List<Map<String, dynamic>>.from(allDeliveryOrders);
              _isLoading = false;
            });
          }
          _subscribeRealtimeOrders(partnerId: null);
          return;
        }
      }

      if (partner != null) {
        _partnerId = int.tryParse(partner['id'].toString());
        _partnerName = partner['name']?.toString() ?? _partnerName;
        _partnerPhone = partner['phone']?.toString() ?? _partnerPhone;
        _vehicleNumber = partner['vehicle_number']?.toString() ?? _vehicleNumber;
        _vehicleType = partner['vehicle_type']?.toString() ?? _vehicleType;
        if (partner['duty_status'] != null) {
          _dutyStatus = partner['duty_status'].toString().toLowerCase();
        }

        // Trigger Live GPS Tracing if Online
        if (_dutyStatus == 'online' && _partnerId != null) {
          DeliveryTrackingService.instance.startTracking(partnerId: _partnerId!);
        }
        await _loadDutyStart();
        _subscribeRealtimeOrders(partnerId: _partnerId);
      }

      if (partner == null) {
        if (mounted) {
          setState(() {
            _liveOrders = [];
            _isLoading = false;
          });
        }
        return;
      }

      final response = await db
          .from('orders')
          .select('*, order_items(*, fish_items(*))')
          .eq('delivery_partner_id', partner['id'])
          .inFilter('status', ['packed', 'out_for_delivery', 'delivered'])
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

  /// [partnerId] null = manager overview (no chime). Otherwise only this
  /// partner's orders trigger a refresh / chime.
  void _subscribeRealtimeOrders({required int? partnerId}) {
    if (_ordersSubscription != null) return; // already subscribed (refetch path)
    _ordersSubscription = Supabase.instance.client
        .channel('delivery_orders_${partnerId ?? 'manager'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: partnerId == null
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'delivery_partner_id',
                  value: partnerId,
                ),
          callback: (payload) {
            if (!mounted) return;
            final newRec = payload.newRecord;
            final oldRec = payload.oldRecord;
            final newStatus = newRec['status']?.toString().toLowerCase();
            final oldStatus = oldRec['status']?.toString().toLowerCase();

            // Chime only when an order is newly dispatched to THIS partner.
            if (partnerId != null &&
                payload.eventType == PostgresChangeEvent.update &&
                newStatus == 'out_for_delivery' &&
                oldStatus != 'out_for_delivery') {
              HapticService.heavyImpact();
              _soundService.playNewOrderChime();
            }
            _fetchLiveDeliveryOrders();
          },
        )
        .subscribe();
  }

  Future<void> _updateDutyStatus(String status) async {
    HapticService.selectionClick();
    final previousStatus = _dutyStatus;
    setState(() => _dutyStatus = status);

    try {
      if (_partnerId != null) {
        // RLS silently updates 0 rows when not allowed, so check the result.
        final rows = await Supabase.instance.client.from('delivery_partners').update({
          'duty_status': status,
          'is_available': status == 'online',
        }).eq('id', _partnerId!).select('id');
        if (rows.isEmpty) {
          throw StateError('Duty status was not saved for this account');
        }

        final since = status == 'online' ? (_dutyOnlineSince ?? DateTime.now()) : null;
        await _saveDutyStart(since);
        if (mounted) setState(() => _dutyOnlineSince = since);

        // Start or stop live GPS tracking based on duty status
        if (status == 'online') {
          await DeliveryTrackingService.instance.startTracking(partnerId: _partnerId!);
        } else {
          await DeliveryTrackingService.instance.stopTracking();
        }
      }

      if (mounted) {
        String msg = '🟢 You are ONLINE — live GPS tracking broadcasting to customer!';
        if (status == 'break') msg = '☕ You are on BREAK — live tracking paused';
        if (status == 'offline') msg = '🔴 You are OFFLINE — duty & GPS stopped';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: status == 'online'
                ? const Color(0xFF059669)
                : status == 'break'
                    ? const Color(0xFFD97706)
                    : const Color(0xFF475569),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
            content: Text(
              msg,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating duty status: $e');
      if (mounted) {
        setState(() => _dutyStatus = previousStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: const Text('❌ Duty status update failed — please try again'),
          ),
        );
      }
    }
  }

  Future<void> _updateOrderStatus(int orderId, String newStatus) async {
    HapticService.heavyImpact();

    try {
      if (newStatus != 'delivered') {
        throw StateError('Only the store manager can dispatch an order.');
      }
      final result = await Supabase.instance.client.rpc(
        'complete_assigned_delivery',
        params: {'p_order_id': orderId},
      );
      if (result == null) throw StateError('Delivery completion was not saved');
      // Success sound only after the server confirmed the delivery.
      _soundService.playSuccessChime();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '🎉 Order delivered successfully!',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
                ),
              ],
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

  // Don't gate on canLaunchUrl() (unreliable on Android 11+); try and report.
  Future<void> _launchOrWarn(Uri uri, String failMessage) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl failed for $uri: $e');
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(failMessage)),
      );
    }
  }

  Future<void> _callStoreManager() async {
    HapticService.selectionClick();
    await _launchOrWarn(Uri(scheme: 'tel', path: '9384332235'), 'Call app திறக்க முடியவில்லை');
  }

  Future<void> _openStoreHubNavigation() async {
    HapticService.selectionClick();
    await _launchOrWarn(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=MeenMart+Pazhaverkadu'),
      'Google Maps திறக்க முடியவில்லை',
    );
  }

  void _openDelayOrSosDialog() {
    HapticService.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report Delay or Emergency',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navyBlue,
                              ),
                            ),
                            Text(
                              'Instantly alerts store operations team',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDelayOption(
                    icon: Icons.tire_repair_rounded,
                    iconColor: const Color(0xFFEA580C),
                    iconBg: const Color(0xFFFFF7ED),
                    title: 'Tyre Puncture / Bike Breakdown',
                    desc: 'Vehicle trouble on route',
                    onTap: () => _submitDelayReport('Vehicle breakdown / puncture reported'),
                  ),
                  _buildDelayOption(
                    icon: Icons.cloudy_snowing,
                    iconColor: const Color(0xFF0284C7),
                    iconBg: const Color(0xFFF0F9FF),
                    title: 'Heavy Rain / Waterlogging',
                    desc: 'Slow transit due to weather conditions',
                    onTap: () => _submitDelayReport('Heavy rain delay reported'),
                  ),
                  _buildDelayOption(
                    icon: Icons.phone_disabled_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    iconBg: const Color(0xFFFAF5FF),
                    title: 'Customer Phone Unreachable',
                    desc: 'Customer not answering call at location',
                    onTap: () => _submitDelayReport('Customer phone unreachable reported'),
                  ),
                  _buildDelayOption(
                    icon: Icons.traffic_rounded,
                    iconColor: const Color(0xFFD97706),
                    iconBg: const Color(0xFFFEF3C7),
                    title: 'Severe Traffic / Bridge Block',
                    desc: 'Expected 15-20 min transit delay',
                    onTap: () => _submitDelayReport('Severe traffic delay reported'),
                  ),
                  _buildDelayOption(
                    icon: Icons.emergency_rounded,
                    iconColor: const Color(0xFFDC2626),
                    iconBg: const Color(0xFFFEF2F2),
                    title: 'Emergency / Urgent Assistance',
                    desc: 'Immediate manager call required',
                    isCritical: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      _callStoreManager();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDelayOption({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String desc,
    required VoidCallback onTap,
    bool isCritical = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isCritical ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isCritical ? const Color(0xFF991B1B) : AppColors.navyBlue,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        desc,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitDelayReport(String message) async {
    Navigator.pop(context);
    HapticService.heavyImpact();

    // supabase_flutter v2 only sends a query when it is awaited; the old
    // un-awaited insert was never executed.
    try {
      await Supabase.instance.client.from('manager_activity_logs').insert({
        'staff_name': _partnerName,
        'role': 'delivery_partner',
        'event_type': 'delivery_delay_alert',
        'description': '$message (Rider: $_partnerName, $_vehicleNumber)',
      });
    } catch (e) {
      debugPrint('Delay report failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: const Text('❌ Report அனுப்ப முடியவில்லை — Store-ஐ நேரடியாக call செய்யுங்கள்'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Store team notified: $message',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCashDepositDialog(double cashInHand) {
    HapticService.selectionClick();
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
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF2563EB), size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Store Cash Deposit',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.navyBlue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hand over today\'s collected COD float at Pazhaverkadu Hub counter.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collected COD in Hand:',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  Text(
                    '₹${cashInHand.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
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
                      'Close',
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _submitCashDeposit(cashInHand);
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      'Handed to Store ✅',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _submitCashDeposit(double amount) {
    HapticService.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          '💵 ₹${amount.toStringAsFixed(0)} deposit logged at store counter!',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  void _showGpsTrackingDetails(TrackingStatus status) {
    HapticService.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final pos = status.position;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: status.isBroadcasting
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFFBEB),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.satellite_alt_rounded,
                      color: status.isBroadcasting
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Customer GPS Broadcast',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navyBlue,
                          ),
                        ),
                        Text(
                          status.isBroadcasting
                              ? 'Active • Streaming to customer live map'
                              : 'Waiting for GPS location fix',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildGpsStatRow('Assigned Rider', _partnerName),
                    const Divider(height: 14),
                    _buildGpsStatRow('Vehicle No', _vehicleNumber),
                    const Divider(height: 14),
                    _buildGpsStatRow(
                      'Coordinates',
                      pos != null
                          ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
                          : 'Acquiring GPS fix...',
                    ),
                    const Divider(height: 14),
                    _buildGpsStatRow(
                      'Accuracy',
                      pos != null ? '±${pos.accuracy.toStringAsFixed(1)} meters' : 'N/A',
                    ),
                    const Divider(height: 14),
                    _buildGpsStatRow(
                      'Realtime Ping',
                      status.lastSyncTime != null
                          ? 'Just now (${status.lastSyncTime!.minute}:${status.lastSyncTime!.second.toString().padLeft(2, '0')})'
                          : 'Broadcasting...',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navyBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGpsStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppColors.navyBlue,
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_selectedFilter == 'out_for_delivery') {
      return _liveOrders.where((o) => o['status'] == 'out_for_delivery').toList();
    } else if (_selectedFilter == 'delivered') {
      return _liveOrders.where((o) => o['status'] == 'delivered').toList();
    }
    // 'active' returns all ongoing: packed and out_for_delivery
    return _liveOrders.where((o) => o['status'] == 'out_for_delivery' || o['status'] == 'packed').toList();
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _liveOrders.where((o) => o['status'] == 'out_for_delivery' || o['status'] == 'packed').toList();
    final outForDeliveryOrders = _liveOrders.where((o) => o['status'] == 'out_for_delivery').toList();
    final deliveredOrders = _liveOrders.where((o) => o['status'] == 'delivered').toList();

    final activeCount = activeOrders.length;
    final outCount = outForDeliveryOrders.length;
    final deliveredCount = deliveredOrders.length;

    // COD Cash In Hand (Collected from delivered orders today)
    final codCollectedInHand = deliveredOrders
        .where((o) => (o['payment_method'] ?? 'cod').toString().toLowerCase() == 'cod')
        .fold<double>(0.0, (sum, o) => sum + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0.0));

    // COD Pending to collect from active out for delivery orders
    final codPendingToCollect = outForDeliveryOrders
        .where((o) => (o['payment_method'] ?? 'cod').toString().toLowerCase() == 'cod')
        .fold<double>(0.0, (sum, o) => sum + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0.0));

    // Estimated Earnings: ₹40 base per completed order + any delivery fee
    final estimatedEarnings = deliveredOrders.fold<double>(0.0, (sum, o) {
      final fee = double.tryParse(o['delivery_charge']?.toString() ?? '') ?? 40.0;
      return sum + (fee > 0 ? fee : 40.0);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const PartnerDrawer(),
      body: Column(
        children: [
          // ── Pinned Shift Command Header (Always visible, perfectly positioned) ──
          _buildShiftCommandHeader(),

          // ── Scrollable Body with Pull-to-Refresh ──
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchLiveDeliveryOrders,
              color: AppColors.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  // ── Hero Earnings & Incentive Card ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildHeroEarningsCard(
                        estimatedEarnings: estimatedEarnings,
                        deliveredCount: deliveredCount,
                        targetCount: 6,
                        codCollectedInHand: codCollectedInHand,
                        codPendingToCollect: codPendingToCollect,
                      ),
                    ),
                  ),

                  // ── Rider Quick Tools Strip ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildQuickToolsStrip(),
                    ),
                  ),

                  // ── Filter Chips ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: _buildFilterChips(activeCount, outCount, deliveredCount),
                    ),
                  ),

                  // ── Orders List or Radar Empty State ──
                  if (_isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  else if (_filteredOrders.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildRadarEmptyState(),
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

                  const SliverToBoxAdapter(child: SizedBox(height: 50)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCommandHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1128),
            Color(0xFF141F36),
            Color(0xFF1E293B),
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Drawer Menu + Title & Hub + SOS + Refresh
              Row(
                children: [
                  Builder(
                    builder: (ctx) => InkWell(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(20),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white.withAlpha(25)),
                        ),
                        child: const Icon(Icons.menu_rounded, color: Colors.white, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Image.asset('assets/icons/store_logo.png', fit: BoxFit.contain),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'MeenMart Partner',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pazhaverkadu Hub',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 🚨 SOS Quick Alert Button
                  InkWell(
                    onTap: _openDelayOrSosDialog,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withAlpha(40),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDC2626).withAlpha(150)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 15),
                          const SizedBox(width: 4),
                          Text(
                            'SOS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFCA5A5),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Refresh Icon
                  InkWell(
                    onTap: () {
                      HapticService.lightImpact();
                      _fetchLiveDeliveryOrders();
                    },
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Rider Info Bar + Shift Timer
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(40),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                    ),
                    child: const Center(
                      child: Icon(Icons.two_wheeler_rounded, color: Color(0xFF34D399), size: 18),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _partnerName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Text(
                              _vehicleNumber,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '•  $_vehicleType',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Duty duration badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(50),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Colors.white.withAlpha(15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 11, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          _formatDutyDuration(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Live Customer GPS Tracing Status Indicator ──
              ValueListenableBuilder<TrackingStatus>(
                valueListenable: DeliveryTrackingService.instance.statusNotifier,
                builder: (context, trackingStatus, _) {
                  final isBroadcasting = trackingStatus.isBroadcasting;
                  final isGpsOff = trackingStatus.state == TrackingState.gpsDisabled ||
                      trackingStatus.state == TrackingState.permissionDenied;

                  Color pillBg = isBroadcasting
                      ? const Color(0xFF059669).withAlpha(35)
                      : isGpsOff
                          ? const Color(0xFFD97706).withAlpha(35)
                          : Colors.white.withAlpha(15);
                  Color pillBorder = isBroadcasting
                      ? const Color(0xFF10B981).withAlpha(100)
                      : isGpsOff
                          ? const Color(0xFFF59E0B).withAlpha(120)
                          : Colors.white.withAlpha(20);
                  Color textColor = isBroadcasting
                      ? const Color(0xFF6EE7B7)
                      : isGpsOff
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFF94A3B8);

                  return InkWell(
                    onTap: () {
                      if (isGpsOff) {
                        DeliveryTrackingService.instance.openSettings();
                      } else {
                        _showGpsTrackingDetails(trackingStatus);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: pillBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isBroadcasting
                                ? Icons.satellite_alt_rounded
                                : isGpsOff
                                    ? Icons.location_off_rounded
                                    : Icons.location_on_outlined,
                            size: 13,
                            color: textColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isBroadcasting
                                  ? 'Customer Live GPS: Connected & Broadcasting'
                                  : isGpsOff
                                      ? 'GPS Location Disabled • Tap to enable for customer'
                                      : 'Live GPS: Waiting for duty session',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.info_outline_rounded,
                            size: 12,
                            color: textColor.withAlpha(180),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // 3-Way Segmented Duty Toggle (Online / Break / Offline)
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Row(
                  children: [
                    _buildDutySegment('online', '🟢 Online', const Color(0xFF059669)),
                    _buildDutySegment('break', '☕ Break', const Color(0xFFD97706)),
                    _buildDutySegment('offline', '🔴 Offline', const Color(0xFF475569)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDutySegment(String id, String label, Color activeColor) {
    final isSelected = _dutyStatus == id;
    return Expanded(
      child: InkWell(
        onTap: () => _updateDutyStatus(id),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withAlpha(80),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroEarningsCard({
    required double estimatedEarnings,
    required int deliveredCount,
    required int targetCount,
    required double codCollectedInHand,
    required double codPendingToCollect,
  }) {
    final progress = (deliveredCount / targetCount).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          // Top row: Earnings + Trips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY\'S EARNINGS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '₹${estimatedEarnings.toStringAsFixed(0)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$deliveredCount Delivered',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF15803D),
                        ),
                      ),
                      Text(
                        'Base ₹40 / trip',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Daily Target Incentive Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(11),
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
                    Row(
                      children: [
                        const Icon(Icons.military_tech_rounded, color: Color(0xFFD97706), size: 17),
                        const SizedBox(width: 5),
                        Text(
                          'Daily Target Incentive',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyBlue,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$deliveredCount / $targetCount Trips',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 1.0 ? const Color(0xFF059669) : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  deliveredCount >= targetCount
                      ? '🎉 Target unlocked! ₹150 daily bonus added.'
                      : 'Complete ${targetCount - deliveredCount} more deliveries today to unlock ₹150 bonus!',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: deliveredCount >= targetCount
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          // COD Float / Cash in Hand Strip
          if (codCollectedInHand > 0 || codPendingToCollect > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: Color(0xFFDC2626), size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cash in Hand: ₹${codCollectedInHand.toStringAsFixed(0)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF991B1B),
                          ),
                        ),
                        if (codPendingToCollect > 0)
                          Text(
                            '+₹${codPendingToCollect.toStringAsFixed(0)} pending to collect',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (codCollectedInHand > 0)
                    ElevatedButton(
                      onPressed: () => _openCashDepositDialog(codCollectedInHand),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        'Deposit 🏦',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickToolsStrip() {
    return Row(
      children: [
        // 🚨 Report Delay
        Expanded(
          child: _buildToolButton(
            icon: Icons.access_time_filled_rounded,
            label: 'Report Delay',
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFFFBEB),
            borderColor: const Color(0xFFFDE68A),
            onTap: _openDelayOrSosDialog,
          ),
        ),
        const SizedBox(width: 8),
        // 📞 Store Call
        Expanded(
          child: _buildToolButton(
            icon: Icons.support_agent_rounded,
            label: 'Store Call',
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
            borderColor: const Color(0xFFBFDBFE),
            onTap: _callStoreManager,
          ),
        ),
        const SizedBox(width: 8),
        // 📍 Store Hub
        Expanded(
          child: _buildToolButton(
            icon: Icons.storefront_rounded,
            label: 'Store Hub',
            color: const Color(0xFF059669),
            bgColor: const Color(0xFFECFDF5),
            borderColor: const Color(0xFFA7F3D0),
            onTap: _openStoreHubNavigation,
          ),
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(int activeCount, int outCount, int deliveredCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterChip('active', '🔥 Active', activeCount),
          const SizedBox(width: 8),
          _buildFilterChip('out_for_delivery', '🛵 Out for Delivery', outCount),
          const SizedBox(width: 8),
          _buildFilterChip('delivered', '✅ Delivered Today', deliveredCount),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String id, String label, int count) {
    final isSelected = _selectedFilter == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = id);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navyBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.navyBlue : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.navyBlue.withAlpha(30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withAlpha(40) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Radar pulse graphic
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120 + (_radarController.value * 30),
                      height: 120 + (_radarController.value * 30),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withAlpha((40 * (1.0 - _radarController.value)).toInt()),
                      ),
                    ),
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withAlpha(20),
                      ),
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF059669),
                      ),
                      child: const Center(
                        child: Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              _selectedFilter == 'delivered'
                  ? 'No completed orders yet today'
                  : 'Ready for Orders • Scanning Live Radar',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navyBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == 'delivered'
                  ? 'Completed trips will be archived here with detailed earnings summary.'
                  : 'You are connected to Pazhaverkadu store. Orders assigned for delivery will pop up here with instant audio chime.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                HapticService.lightImpact();
                _fetchLiveDeliveryOrders();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Refresh Dispatch Radar',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navyBlue,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
