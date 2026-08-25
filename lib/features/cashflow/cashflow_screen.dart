import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/widgets/image_crop_dialog.dart';
import '../drawer/partner_drawer.dart';

enum CashflowTab { overview, orderProfit, storeExpenses }
enum PeriodFilter { today, thisWeek, thisMonth, allTime, custom }

class CashflowScreen extends ConsumerStatefulWidget {
  const CashflowScreen({super.key});

  @override
  ConsumerState<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends ConsumerState<CashflowScreen> {
  final SoundService _soundService = SoundService();
  CashflowTab _selectedTab = CashflowTab.overview;
  PeriodFilter _selectedPeriod = PeriodFilter.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isLoading = true;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _manualExpenses = [];

  @override
  void initState() {
    super.initState();
    _fetchCashflowData();
  }

  String _getPeriodLabel() {
    final now = DateTime.now();
    if (_selectedPeriod == PeriodFilter.today) {
      return 'Today • ${DateFormat("dd MMM yyyy").format(now)}';
    } else if (_selectedPeriod == PeriodFilter.thisWeek) {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      return 'This Week • ${DateFormat("dd MMM").format(monday)} – ${DateFormat("dd MMM yyyy").format(now)}';
    } else if (_selectedPeriod == PeriodFilter.thisMonth) {
      final start = DateTime(now.year, now.month, 1);
      return 'This Month • ${DateFormat("01 MMM").format(start)} – ${DateFormat("dd MMM yyyy").format(now)}';
    } else if (_selectedPeriod == PeriodFilter.custom && _customStartDate != null && _customEndDate != null) {
      return 'Custom • ${DateFormat("dd MMM yyyy").format(_customStartDate!)} – ${DateFormat("dd MMM yyyy").format(_customEndDate!)}';
    }
    return 'All Time Records';
  }

  Future<void> _pickCustomDateRange() async {
    AppHaptics.selectionClick();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF059669),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = PeriodFilter.custom;
        _customStartDate = DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0);
        _customEndDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _fetchCashflowData();
    }
  }

  Future<void> _fetchCashflowData() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final now = DateTime.now();

      DateTime? filterStart;
      DateTime? filterEnd;

      if (_selectedPeriod == PeriodFilter.today) {
        filterStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
        filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_selectedPeriod == PeriodFilter.thisWeek) {
        final monday = now.subtract(Duration(days: now.weekday - 1));
        filterStart = DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
        filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_selectedPeriod == PeriodFilter.thisMonth) {
        filterStart = DateTime(now.year, now.month, 1, 0, 0, 0);
        filterEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_selectedPeriod == PeriodFilter.custom) {
        filterStart = _customStartDate;
        filterEnd = _customEndDate;
      }

      // 1. Fetch Orders with Line items and fish catalog details
      var ordersQuery = db.from('orders').select('''
        id, order_ref, customer_name, phone, delivery_address, total_price, 
        delivery_charge, discount_amount, payment_method, status, created_at,
        order_items(
          id, quantity_kg, price_per_kg, with_cleaning, cleaning_fee, cutting_type, size_preference,
          fish_items(name, tamil_name, buying_price, price_per_kg, cleaning_charge, image_url)
        )
      ''');

      if (filterStart != null) {
        ordersQuery = ordersQuery.gte('created_at', filterStart.toUtc().toIso8601String());
      }
      if (filterEnd != null) {
        ordersQuery = ordersQuery.lte('created_at', filterEnd.toUtc().toIso8601String());
      }

      final orderRows = await ordersQuery
          .order('created_at', ascending: false)
          .limit(1000)
          .timeout(const Duration(seconds: 8));

      var ordersList = List<Map<String, dynamic>>.from(orderRows);

      // 2. Fetch Manual Expenses
      var expensesQuery = db.from('expenses').select('*');
      if (filterStart != null) {
        expensesQuery = expensesQuery.gte('created_at', filterStart.toUtc().toIso8601String());
      }
      if (filterEnd != null) {
        expensesQuery = expensesQuery.lte('created_at', filterEnd.toUtc().toIso8601String());
      }

      final expenseRows = await expensesQuery
          .order('created_at', ascending: false)
          .limit(1000)
          .timeout(const Duration(seconds: 8));

      var expensesList = List<Map<String, dynamic>>.from(expenseRows);

      if (mounted) {
        setState(() {
          _orders = ordersList;
          _manualExpenses = expensesList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Cashflow fetch error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- ORDER NUMBER & DATE FORMATTING HELPERS ---

  static String formatOrderRef(dynamic rawRef, [dynamic id]) {
    if (rawRef != null) {
      final str = rawRef.toString().trim();
      final match = RegExp(r'\d+').firstMatch(str);
      if (match != null) {
        final numVal = int.tryParse(match.group(0)!) ?? 0;
        return '#${numVal < 10 ? "0$numVal" : "$numVal"}';
      }
      return str;
    }
    if (id != null) {
      final numVal = int.tryParse(id.toString()) ?? 0;
      return '#${numVal < 10 ? "0$numVal" : "$numVal"}';
    }
    return '#01';
  }

  static String formatDateTime(dynamic isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString.toString()).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final isYesterday = dt.year == now.year && dt.month == now.month && (dt.day == now.day - 1 || (dt.day == 1 && now.day != 1));

      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      final timeFormatted = '$hour:$minute $ampm';

      if (isToday) {
        return 'Today, $timeFormatted';
      } else if (isYesterday) {
        return 'Yesterday, $timeFormatted';
      } else {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final monthStr = months[dt.month - 1];
        return '${dt.day} $monthStr ${dt.year}, $timeFormatted';
      }
    } catch (_) {
      return isoString.toString();
    }
  }

  // --- ORDER STATUS CLASSIFIERS ---

  bool _isOrderDelivered(Map<String, dynamic> o) {
    final s = (o['status'] ?? '').toString().toLowerCase();
    return s == 'completed' || s == 'delivered';
  }

  bool _isOrderCancelled(Map<String, dynamic> o) {
    final s = (o['status'] ?? '').toString().toLowerCase();
    return s == 'cancelled';
  }

  bool _isOrderWaitingForDelivery(Map<String, dynamic> o) {
    return !_isOrderDelivered(o) && !_isOrderCancelled(o);
  }

  // --- FINANCIAL CALCULATIONS ENGINE ---

  double _calculateOrderFishRevenue(Map<String, dynamic> o) {
    final items = o['order_items'] as List<dynamic>? ?? [];
    double sum = 0.0;
    for (var item in items) {
      final qty = (item['quantity_kg'] as num? ?? 0.0).toDouble();
      final rate = (item['price_per_kg'] as num? ?? 0.0).toDouble();
      sum += qty * rate;
    }
    return sum;
  }

  double _calculateOrderCleaningInflow(Map<String, dynamic> o) {
    final items = o['order_items'] as List<dynamic>? ?? [];
    double sum = 0.0;
    for (var item in items) {
      final fee = (item['cleaning_fee'] as num?)?.toDouble() ?? 0.0;
      final withClean = item['with_cleaning'] == true;
      if (fee > 0) {
        sum += fee;
      } else if (withClean) {
        final fish = item['fish_items'] as Map<String, dynamic>?;
        final defClean = (fish?['cleaning_charge'] as num?)?.toDouble() ?? 30.0;
        sum += defClean;
      }
    }
    return sum;
  }

  double _calculateOrderDeliveryInflow(Map<String, dynamic> o) {
    return (o['delivery_charge'] as num? ?? 0.0).toDouble();
  }

  double _calculateOrderGrossInflow(Map<String, dynamic> o) {
    final fishRev = _calculateOrderFishRevenue(o);
    final cleanRev = _calculateOrderCleaningInflow(o);
    final delRev = _calculateOrderDeliveryInflow(o);
    final discount = (o['discount_amount'] as num? ?? 0.0).toDouble();
    final calculated = (fishRev + cleanRev + delRev - discount);
    final rawTotal = (o['total_price'] as num? ?? 0.0).toDouble();
    return calculated > 0 ? calculated : rawTotal;
  }

  double _calculateOrderProcurementCost(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    final items = o['order_items'] as List<dynamic>? ?? [];
    double sum = 0.0;
    for (var item in items) {
      final qty = (item['quantity_kg'] as num? ?? 0.0).toDouble();
      final fish = item['fish_items'] as Map<String, dynamic>?;
      double buyRate = (fish?['buying_price'] as num?)?.toDouble() ?? 0.0;
      if (buyRate <= 0.0) {
        final retailRate = (item['price_per_kg'] as num?)?.toDouble() ?? (fish?['price_per_kg'] as num?)?.toDouble() ?? 0.0;
        buyRate = retailRate * 0.70;
      }
      sum += qty * buyRate;
    }
    return sum;
  }

  double _calculateOrderCutterWage(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    final orderRef = (o['order_ref'] ?? o['id']).toString();
    for (var e in _manualExpenses) {
      if ((e['order_ref'] == orderRef || e['order_id'] == o['id']) && e['category'] == 'Cutter Labor Wage') {
        return (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    final cleanInflow = _calculateOrderCleaningInflow(o);
    if (cleanInflow > 0) return cleanInflow;

    final items = o['order_items'] as List<dynamic>? ?? [];
    bool hasCleaning = items.any((i) => i['with_cleaning'] == true);
    return hasCleaning ? 25.0 : 0.0;
  }

  double _calculateOrderDeliveryRiderWage(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    final orderRef = (o['order_ref'] ?? o['id']).toString();
    for (var e in _manualExpenses) {
      if ((e['order_ref'] == orderRef || e['order_id'] == o['id']) && e['category'] == 'Delivery Partner Payout') {
        return (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    final delInflow = _calculateOrderDeliveryInflow(o);
    return delInflow > 0 ? delInflow : 35.0;
  }

  double _calculateOrderExtraLinkedExpenses(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    final orderRef = (o['order_ref'] ?? o['id']).toString();
    double sum = 0.0;
    for (var e in _manualExpenses) {
      if ((e['order_ref'] == orderRef || e['order_id'] == o['id']) &&
          e['category'] != 'Cutter Labor Wage' &&
          e['category'] != 'Delivery Partner Payout') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  double _calculateOrderTotalCost(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    return _calculateOrderProcurementCost(o) +
        _calculateOrderCutterWage(o) +
        _calculateOrderDeliveryRiderWage(o) +
        _calculateOrderExtraLinkedExpenses(o);
  }

  double _calculateOrderNetProfit(Map<String, dynamic> o) {
    if (_isOrderCancelled(o)) return 0.0;
    return _calculateOrderGrossInflow(o) - _calculateOrderTotalCost(o);
  }

  // --- STORE AGGREGATES (STRICTLY REALIZED / DELIVERED INCOMES ONLY) ---

  /// 🟢 Total Inflow: ONLY Delivered Orders (Cancelled & Pending excluded)
  double get _totalRevenueIncome {
    double sum = 0.0;
    for (var o in _orders) {
      if (_isOrderDelivered(o)) {
        sum += _calculateOrderGrossInflow(o);
      }
    }
    return sum;
  }

  /// ⏳ Expected Pipeline Inflow (Waiting for Delivery)
  double get _pendingPipelineInflow {
    double sum = 0.0;
    for (var o in _orders) {
      if (_isOrderWaitingForDelivery(o)) {
        sum += _calculateOrderGrossInflow(o);
      }
    }
    return sum;
  }

  int get _deliveredOrdersCount => _orders.where(_isOrderDelivered).length;
  int get _waitingOrdersCount => _orders.where(_isOrderWaitingForDelivery).length;

  double get _totalProcurementCost {
    double sum = 0.0;
    for (var o in _orders) {
      if (!_isOrderCancelled(o)) {
        sum += _calculateOrderProcurementCost(o);
      }
    }
    return sum;
  }

  double get _totalCutterWages {
    double sum = 0.0;
    for (var o in _orders) {
      if (!_isOrderCancelled(o)) {
        sum += _calculateOrderCutterWage(o);
      }
    }
    return sum;
  }

  double get _totalDeliveryRiderWages {
    double sum = 0.0;
    for (var o in _orders) {
      if (!_isOrderCancelled(o)) {
        sum += _calculateOrderDeliveryRiderWage(o);
      }
    }
    return sum;
  }

  double get _totalGeneralStoreOpsExpenses {
    double sum = 0.0;
    for (var e in _manualExpenses) {
      final orderRef = e['order_ref']?.toString();
      if (orderRef == null || orderRef.isEmpty || orderRef == 'general') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      } else if (e['category'] != 'Cutter Labor Wage' && e['category'] != 'Delivery Partner Payout') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  double get _totalExpenses => _totalProcurementCost + _totalCutterWages + _totalDeliveryRiderWages + _totalGeneralStoreOpsExpenses;
  double get _netCashBalance => _totalRevenueIncome - _totalExpenses;

  /// 💵 Cash Drawer Inflow: Only DELIVERED COD Orders
  double get _cashDrawerInflow {
    double sum = 0.0;
    for (var o in _orders) {
      if (_isOrderDelivered(o)) {
        final method = (o['payment_method'] ?? 'cod').toString().toLowerCase();
        if (method == 'cod' || method == 'cash') {
          sum += _calculateOrderGrossInflow(o);
        }
      }
    }
    return sum;
  }

  double get _cashDrawerOutflow {
    double sum = 0.0;
    for (var e in _manualExpenses) {
      final mode = (e['payment_mode'] ?? 'cash_drawer').toString().toLowerCase();
      if (mode == 'cash_drawer' || mode == 'cash') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  double get _netDrawerCash => (_cashDrawerInflow - _cashDrawerOutflow).clamp(0.0, double.infinity);

  /// 📱 Online Payments: Only DELIVERED Online Orders
  double get _onlinePaymentInflow {
    double sum = 0.0;
    for (var o in _orders) {
      if (_isOrderDelivered(o)) {
        final method = (o['payment_method'] ?? 'cod').toString().toLowerCase();
        if (method != 'cod' && method != 'cash') {
          sum += _calculateOrderGrossInflow(o);
        }
      }
    }
    return sum;
  }

  // --- ACTIONS: ADD / EDIT / DELETE EXPENSES ---

  void _showAddOrEditExpenseModal({
    Map<String, dynamic>? existingExpense,
    String? preselectedOrderRef,
    String? defaultCategory,
    double? defaultAmount,
  }) {
    AppHaptics.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddOrEditExpenseModal(
        activeOrders: _orders,
        existingExpense: existingExpense,
        initialOrderRef: preselectedOrderRef,
        initialCategory: defaultCategory,
        initialAmount: defaultAmount,
      ),
    ).then((saved) {
      if (saved == true) {
        _fetchCashflowData();
      }
    });
  }

  Future<void> _confirmDeleteExpense(Map<String, dynamic> expense) async {
    AppHaptics.warning();
    final cat = expense['category'] ?? 'Expense';
    final amt = (expense['amount'] as num? ?? 0.0).toDouble();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Expense Entry?',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ),
        content: Text(
          'Are you sure you want to delete this $cat entry of ₹${amt.toStringAsFixed(0)}? This will recalculate the store balance immediately.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final db = Supabase.instance.client;
        await db.from('expenses').delete().eq('id', expense['id']);
        _soundService.playSuccessChime();
        AppHaptics.success();
        await _fetchCashflowData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ $cat of ₹${amt.toStringAsFixed(0)} deleted successfully.'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        debugPrint('Delete expense error: $e');
      }
    }
  }

  void _showOrderDetailsSheet(Map<String, dynamic> o) {
    AppHaptics.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderFinancialDetailSheet(
        order: o,
        isDelivered: _isOrderDelivered(o),
        isCancelled: _isOrderCancelled(o),
        isWaiting: _isOrderWaitingForDelivery(o),
        fishRevenue: _calculateOrderFishRevenue(o),
        cleaningInflow: _calculateOrderCleaningInflow(o),
        deliveryInflow: _calculateOrderDeliveryInflow(o),
        grossInflow: _calculateOrderGrossInflow(o),
        procurementCost: _calculateOrderProcurementCost(o),
        cutterWage: _calculateOrderCutterWage(o),
        riderWage: _calculateOrderDeliveryRiderWage(o),
        extraLinkedExpenses: _calculateOrderExtraLinkedExpenses(o),
        totalCost: _calculateOrderTotalCost(o),
        netProfit: _calculateOrderNetProfit(o),
        manualExpenses: _manualExpenses,
        onEditCutterWage: (orderRef, currentWage) {
          Navigator.pop(ctx);
          _showEditWageDialog(orderRef: orderRef, wageType: 'Cutter Labor Wage', currentAmount: currentWage, order: o);
        },
        onEditDeliveryWage: (orderRef, currentWage) {
          Navigator.pop(ctx);
          _showEditWageDialog(orderRef: orderRef, wageType: 'Delivery Partner Payout', currentAmount: currentWage, order: o);
        },
        onAddExpenseTap: (ref) {
          Navigator.pop(ctx);
          _showAddOrEditExpenseModal(preselectedOrderRef: ref);
        },
      ),
    );
  }

  void _showEditWageDialog({
    required String orderRef,
    required String wageType,
    required double currentAmount,
    required Map<String, dynamic> order,
  }) {
    final ctrl = TextEditingController(text: currentAmount.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit $wageType',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$orderRef', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              final newAmt = double.tryParse(ctrl.text) ?? 0.0;
              Navigator.pop(ctx);
              await _saveWageOverride(orderRef: orderRef, wageType: wageType, amount: newAmt, order: order);
            },
            child: Text('Save Wage', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveWageOverride({
    required String orderRef,
    required String wageType,
    required double amount,
    required Map<String, dynamic> order,
  }) async {
    try {
      final db = Supabase.instance.client;
      final authState = ref.read(authNotifierProvider);
      final profile = authState.staffProfile;
      final staffName = profile?['name'] ?? 'Store Staff';
      final staffId = profile?['id']?.toString() ?? profile?['auth_id']?.toString();
      final now = DateTime.now();

      final existing = await db
          .from('expenses')
          .select('id')
          .eq('order_ref', orderRef)
          .eq('category', wageType)
          .limit(1);

      if (existing.isNotEmpty) {
        await db.from('expenses').update({
          'amount': amount,
          'staff_name': staffName,
          'staff_id': staffId,
          'created_at': now.toIso8601String(),
        }).eq('id', existing.first['id']);
      } else {
        await db.from('expenses').insert({
          'category': wageType,
          'expense_type': wageType.contains('Cutter') ? 'labour_wage' : 'delivery_payout',
          'amount': amount,
          'order_ref': orderRef,
          'order_id': order['id'],
          'payment_mode': 'cash_drawer',
          'staff_name': staffName,
          'staff_id': staffId,
          'branch_location': profile?['branch_location'] ?? 'Pulicat Central Store',
          'date': now.toIso8601String().substring(0, 10),
        });
      }

      AppHaptics.success();
      await _fetchCashflowData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$wageType updated to ₹${amount.toStringAsFixed(0)} for Order #$orderRef'),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save wage override error: $e');
    }
  }

  void _showExpenseDetailsSheet(Map<String, dynamic> e) {
    AppHaptics.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExpenseDetailSheet(
        expense: e,
        onEditTap: () {
          Navigator.pop(ctx);
          _showAddOrEditExpenseModal(existingExpense: e);
        },
        onDeleteTap: () {
          Navigator.pop(ctx);
          _confirmDeleteExpense(e);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Open Menu',
            onPressed: () {
              AppHaptics.selectionClick();
              Scaffold.of(ctx).openDrawer();
            },
          ),
        ),
        title: Text(
          'Cashflow & Ledger',
          style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
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
            tooltip: 'Refresh Ledger',
            onPressed: _fetchCashflowData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _fetchCashflowData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. PERIOD FILTER BAR (TODAY, THIS WEEK, THIS MONTH, ALL-TIME, CALENDAR)
                    _buildPeriodFilterSection(),
                    const SizedBox(height: 12),

                    // 2. CLEAN 3-SEGMENT TAB SELECTOR
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          _buildMainTab(CashflowTab.overview, Icons.dashboard_outlined, 'Overview'),
                          _buildMainTab(CashflowTab.orderProfit, Icons.receipt_long_outlined, 'Order P&L'),
                          _buildMainTab(CashflowTab.storeExpenses, Icons.account_balance_wallet_outlined, 'Expenses'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. TAB CONTENT
                    if (_selectedTab == CashflowTab.overview) ...[
                      _buildOverviewView(),
                    ] else if (_selectedTab == CashflowTab.orderProfit) ...[
                      _buildOrderByOrderView(),
                    ] else ...[
                      _buildExpensesListView(),
                    ],

                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => _showAddOrEditExpenseModal(),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Add Expense', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _buildPeriodFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontal Scrollable Period Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildPeriodChip(PeriodFilter.today, 'TODAY'),
              const SizedBox(width: 6),
              _buildPeriodChip(PeriodFilter.thisWeek, 'THIS WEEK'),
              const SizedBox(width: 6),
              _buildPeriodChip(PeriodFilter.thisMonth, 'THIS MONTH'),
              const SizedBox(width: 6),
              _buildPeriodChip(PeriodFilter.allTime, 'ALL TIME'),
              const SizedBox(width: 6),
              _buildCalendarChip(),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Active Date Range Pill / Calendar Trigger
        InkWell(
          onTap: _pickCustomDateRange,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF059669)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getPeriodLabel(),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_orders.length} Orders • ${_manualExpenses.length} Expenses',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 12, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(
                        'CALENDAR',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodChip(PeriodFilter period, String label) {
    final isSel = _selectedPeriod == period;
    return InkWell(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() => _selectedPeriod = period);
        _fetchCashflowData();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF059669) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
              color: isSel ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarChip() {
    final isSel = _selectedPeriod == PeriodFilter.custom;
    return InkWell(
      onTap: _pickCustomDateRange,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF059669) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 12, color: isSel ? Colors.white : const Color(0xFF059669)),
            const SizedBox(width: 5),
            Text(
              '📅 CALENDAR',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSel ? Colors.white : const Color(0xFF047857),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTab(CashflowTab tab, IconData icon, String label) {
    final isSel = _selectedTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () {
          AppHaptics.selectionClick();
          setState(() => _selectedTab = tab);
        },
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSel ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                    color: isSel ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1. OVERVIEW VIEW ---

  Widget _buildOverviewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MASTER HERO CARD
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NET REALIZED BALANCE',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _netCashBalance >= 0 ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _netCashBalance >= 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2)),
                    ),
                    child: Text(
                      _netCashBalance >= 0 ? 'Delivered Surplus' : 'Procure & Ops Outflow',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _netCashBalance >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_netCashBalance >= 0 ? "+" : "-"}₹${_netCashBalance.abs().toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: _netCashBalance >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),

              // 2 PILLARS: TOTAL INFLOW vs TOTAL OUTFLOW (EQUAL HEIGHT)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xFF16A34A)),
                                const SizedBox(width: 4),
                                Text('TOTAL INFLOW', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₹${_totalRevenueIncome.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF15803D)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_deliveredOrdersCount Delivered Orders',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFEE2E2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward_rounded, size: 14, color: Color(0xFFDC2626)),
                                const SizedBox(width: 4),
                                Text('TOTAL OUTFLOW', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₹${_totalExpenses.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFFB91C1C)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Procure + Wages + Ops',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // PIPELINE PENDING NOTICE IF ANY ACTIVE ORDERS
              if (_waitingOrdersCount > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '⏳ Waiting for Delivery: ₹${_pendingPipelineInflow.toStringAsFixed(0)} ($_waitingOrdersCount in pipeline)',
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(height: 24, color: Color(0xFFF1F5F9)),

              // 2x2 METRIC GRID
              Row(
                children: [
                  Expanded(child: _buildMetricCard('🐟 Catch Buying', '₹${_totalProcurementCost.toStringAsFixed(0)}', const Color(0xFF2563EB), const Color(0xFFEFF6FF))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('🔪 Cutter Wages', '₹${_totalCutterWages.toStringAsFixed(0)}', const Color(0xFF7C3AED), const Color(0xFFF5F3FF))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildMetricCard('🚚 Rider Payouts', '₹${_totalDeliveryRiderWages.toStringAsFixed(0)}', const Color(0xFFD97706), const Color(0xFFFFFBEB))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('💵 Drawer Cash', '₹${_netDrawerCash.toStringAsFixed(0)}', const Color(0xFF059669), const Color(0xFFF0FDF4))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // MONEY HOLDINGS SECTION (ONLINE PAYMENT & EQUAL HEIGHT BOXES)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MONEY HOLDINGS (DELIVERED CASH & ONLINE)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: 0.4)),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '💵 CASH DRAWER',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_netDrawerCash.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w900, color: const Color(0xFF92400E)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Delivered COD Inflows',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '📱 ONLINE PAYMENT',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF1E40AF)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_onlinePaymentInflow.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w900, color: const Color(0xFF1E3A8A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Delivered Online Orders',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF1E40AF)),
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
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: textColor)),
        ],
      ),
    );
  }

  // --- 2. ORDER-BY-ORDER PROFIT VIEW (DATE & TIME + DELIVERED STATUS ENGINE) ---

  Widget _buildOrderByOrderView() {
    if (_orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text('No orders found for this period.', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
      );
    }

    return Column(
      children: _orders.map((o) {
        final customerName = o['customer_name'] ?? 'Customer';
        final grossInflow = _calculateOrderGrossInflow(o);
        final procurementCost = _calculateOrderProcurementCost(o);
        final cutterWage = _calculateOrderCutterWage(o);
        final netProfit = _calculateOrderNetProfit(o);
        final dateFormatted = formatDateTime(o['created_at']);

        final isDelivered = _isOrderDelivered(o);
        final isCancelled = _isOrderCancelled(o);
        final isWaiting = _isOrderWaitingForDelivery(o);

        final items = o['order_items'] as List<dynamic>? ?? [];
        final firstItem = items.isNotEmpty ? items.first : null;
        final fish = firstItem?['fish_items'] as Map<String, dynamic>?;
        final photoUrl = fish?['image_url'] as String?;
        final fishName = fish?['name'] ?? 'Fresh Fish';

        return InkWell(
          onTap: () => _showOrderDetailsSheet(o),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isCancelled ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER: ORDER REF + EXACT DATE & TIME
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatOrderRef(o['order_ref'], o['id']),
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                    ),
                    Text('📅 $dateFormatted', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 8),

                // 2. BODY: FISH THUMBNAIL + CUSTOMER + STATUS BADGE
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => _buildFallbackFishIcon(),
                            )
                          : _buildFallbackFishIcon(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customerName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text('$fishName ${items.length > 1 ? "+ ${items.length - 1} more" : ""}',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    if (isDelivered)
                      AppBadges.success('✅ DELIVERED (+₹${netProfit.toStringAsFixed(0)})')
                    else if (isWaiting)
                      AppBadges.capsule(
                        label: '⏳ WAITING FOR DELIVERY',
                        bgColor: const Color(0xFFFFFBEB),
                        borderColor: const Color(0xFFFDE68A),
                        textColor: const Color(0xFFB45309),
                        fontSize: 10,
                      )
                    else
                      AppBadges.capsule(
                        label: '🚫 CANCELLED',
                        bgColor: const Color(0xFFFEF2F2),
                        borderColor: const Color(0xFFFECACA),
                        textColor: const Color(0xFFDC2626),
                        fontSize: 10,
                      ),
                  ],
                ),
                const Divider(height: 16, color: Color(0xFFF1F5F9)),

                // 3. STATS ROW
                if (isCancelled)
                  Text('❌ Cancelled Order — Excluded from Inflow & Store Revenue',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626)))
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildOrderStat(isDelivered ? 'Selling Price' : 'Order Value', '₹${grossInflow.toStringAsFixed(0)}', isDelivered ? const Color(0xFF059669) : const Color(0xFF64748B)),
                      _buildOrderStat('Procure Cost', '-₹${procurementCost.toStringAsFixed(0)}', const Color(0xFF2563EB)),
                      _buildOrderStat('Cutter Wage', '-₹${cutterWage.toStringAsFixed(0)}', const Color(0xFF7C3AED)),
                      _buildOrderStat('Net Profit', isDelivered ? '+₹${netProfit.toStringAsFixed(0)}' : 'Pending', isDelivered ? const Color(0xFF059669) : const Color(0xFFD97706)),
                    ],
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFallbackFishIcon() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(9)),
      child: const Icon(Icons.set_meal_rounded, color: Color(0xFF2563EB), size: 20),
    );
  }

  Widget _buildOrderStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // --- 3. STORE EXPENSES LIST VIEW WITH DATE & TIME, ✏️ EDIT & 🗑️ DELETE ---

  Widget _buildExpensesListView() {
    if (_manualExpenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(36),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 44, color: Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text('No Store Expenses Recorded', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text('Tap "+ Add Expense" below to record Ice, packing boxes, or transport costs.',
                textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    return Column(
      children: _manualExpenses.map((e) {
        final category = e['category'] ?? 'Store Expense';
        final amount = (e['amount'] as num? ?? 0.0).toDouble();
        final vendor = e['vendor_name'] ?? e['description'] ?? 'Store Ops';
        final orderRef = e['order_ref']?.toString();
        final paymentMode = (e['payment_mode'] ?? 'cash_drawer').toString().replaceAll('_', ' ').toUpperCase();
        final dateFormatted = formatDateTime(e['created_at'] ?? e['date']);

        return InkWell(
          onTap: () => _showExpenseDetailsSheet(e),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.north_east_rounded, size: 17, color: Color(0xFFDC2626)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                      const SizedBox(height: 2),
                      Text('$vendor • $paymentMode', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                      const SizedBox(height: 3),
                      Text('📅 $dateFormatted', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8))),
                      if (orderRef != null && orderRef.isNotEmpty && orderRef != 'general') ...[
                        const SizedBox(height: 4),
                        AppBadges.capsule(
                          label: '#$orderRef',
                          bgColor: const Color(0xFFF1F5F9),
                          borderColor: const Color(0xFFE2E8F0),
                          textColor: const Color(0xFF334155),
                          fontSize: 9.5,
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('-₹${amount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626))),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // EDIT ICON
                        InkWell(
                          onTap: () => _showAddOrEditExpenseModal(existingExpense: e),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF2563EB)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // DELETE ICON
                        InkWell(
                          onTap: () => _confirmDeleteExpense(e),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ==========================================
// 1. ORDER FINANCIAL DETAIL SHEET (DATE & TIME + DELIVERED STATUS)
// ==========================================

class _OrderFinancialDetailSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDelivered;
  final bool isCancelled;
  final bool isWaiting;
  final double fishRevenue;
  final double cleaningInflow;
  final double deliveryInflow;
  final double grossInflow;
  final double procurementCost;
  final double cutterWage;
  final double riderWage;
  final double extraLinkedExpenses;
  final double totalCost;
  final double netProfit;
  final List<Map<String, dynamic>> manualExpenses;
  final Function(String orderRef, double currentWage) onEditCutterWage;
  final Function(String orderRef, double currentWage) onEditDeliveryWage;
  final Function(String orderRef) onAddExpenseTap;

  const _OrderFinancialDetailSheet({
    required this.order,
    required this.isDelivered,
    required this.isCancelled,
    required this.isWaiting,
    required this.fishRevenue,
    required this.cleaningInflow,
    required this.deliveryInflow,
    required this.grossInflow,
    required this.procurementCost,
    required this.cutterWage,
    required this.riderWage,
    required this.extraLinkedExpenses,
    required this.totalCost,
    required this.netProfit,
    required this.manualExpenses,
    required this.onEditCutterWage,
    required this.onEditDeliveryWage,
    required this.onAddExpenseTap,
  });

  @override
  Widget build(BuildContext context) {
    final orderRef = (order['order_ref'] ?? order['id']).toString();
    final customerName = order['customer_name'] ?? 'Customer';
    final phone = order['phone'] ?? 'N/A';
    final address = order['delivery_address'] ?? 'Customer Location';
    final paymentMethod = (order['payment_method'] ?? 'COD').toString().toUpperCase();
    final dateFormatted = _CashflowScreenState.formatDateTime(order['created_at']);
    final items = order['order_items'] as List<dynamic>? ?? [];
    final marginPct = grossInflow > 0 ? (netProfit / grossInflow * 100).clamp(0.0, 100.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$orderRef', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                    Text('📅 $dateFormatted', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  ],
                ),
                if (isDelivered)
                  AppBadges.capsule(
                    label: 'DELIVERED',
                    bgColor: const Color(0xFFF0FDF4),
                    borderColor: const Color(0xFFBBF7D0),
                    textColor: const Color(0xFF16A34A),
                  )
                else if (isWaiting)
                  AppBadges.capsule(
                    label: 'WAITING FOR DELIVERY',
                    bgColor: const Color(0xFFFFFBEB),
                    borderColor: const Color(0xFFFDE68A),
                    textColor: const Color(0xFFB45309),
                  )
                else
                  AppBadges.capsule(
                    label: 'CANCELLED',
                    bgColor: const Color(0xFFFEF2F2),
                    borderColor: const Color(0xFFFECACA),
                    textColor: const Color(0xFFDC2626),
                  ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),

            // STATUS BANNER NOTICE
            if (isWaiting)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This order is pending delivery. Revenue will be added to Total Inflows once marked Delivered / Completed.',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              )
            else if (isCancelled)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This order was cancelled and is completely excluded from store inflows and balance.',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),

            // Customer Summary Box
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
                      Text('👤 $customerName', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                      Text('📞 $phone', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2563EB))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('📍 $address', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('💳 Payment Mode: $paymentMethod', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Itemized Seafood List (WITH REAL PHOTOS)
            Text('SEAFOOD LINE ITEMS WEIGHED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.4)),
            const SizedBox(height: 8),
            ...items.map((item) {
              final qty = (item['quantity_kg'] as num? ?? 0.0).toDouble();
              final retailRate = (item['price_per_kg'] as num? ?? 0.0).toDouble();
              final fish = item['fish_items'] as Map<String, dynamic>?;
              final fishName = fish?['name'] ?? 'Fresh Catch';
              final photoUrl = fish?['image_url'] as String?;
              final buyRate = (fish?['buying_price'] as num?)?.toDouble() ?? (retailRate * 0.70);
              final withClean = item['with_cleaning'] == true;
              final cut = item['cutting_type'] ?? 'Standard Cut';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF2563EB)),
                              ),
                            )
                          : Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF2563EB)),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fishName, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text('${qty.toStringAsFixed(2)} kg • $cut • ${withClean ? 'Cleaned' : 'Raw'}',
                              style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Sell: ₹${(qty * retailRate).toStringAsFixed(0)}',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                        Text('Buy: ₹${(qty * buyRate).toStringAsFixed(0)}',
                            style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),

            // P&L BREAKDOWN TABLE (WITH EDITABLE CUTTER & DELIVERY WAGES)
            Text('ORDER P&L STATEMENT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildStatementRow('Fresh Fish Selling Price', '+₹${fishRevenue.toStringAsFixed(0)}', const Color(0xFF059669), isBold: true),
                  _buildStatementRow('Cleaning Charge Collected', '+₹${cleaningInflow.toStringAsFixed(0)}', const Color(0xFF059669)),
                  _buildStatementRow('Delivery Charge Collected', '+₹${deliveryInflow.toStringAsFixed(0)}', const Color(0xFF059669)),
                  const Divider(height: 14, color: Color(0xFFE2E8F0)),
                  _buildStatementRow('Total Customer Inflow', '+₹${grossInflow.toStringAsFixed(0)}', const Color(0xFF15803D), isBold: true),
                  const Divider(height: 14, color: Color(0xFFE2E8F0)),
                  _buildStatementRow('(-) Catch Buying Cost (Wholesale)', '-₹${procurementCost.toStringAsFixed(0)}', const Color(0xFFDC2626)),

                  // EDITABLE CUTTER WAGE ROW
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '(-) Cutter Labor Wage',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => onEditCutterWage(orderRef, cutterWage),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F3FF),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFDDD6FE)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_rounded, size: 10, color: Color(0xFF7C3AED)),
                                      const SizedBox(width: 2),
                                      Text('Edit', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFF7C3AED))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('-₹${cutterWage.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626))),
                      ],
                    ),
                  ),

                  // EDITABLE DELIVERY RIDER WAGE ROW
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '(-) Delivery Partner Payout',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => onEditDeliveryWage(orderRef, riderWage),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_rounded, size: 10, color: Color(0xFFD97706)),
                                      const SizedBox(width: 2),
                                      Text('Edit', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('-₹${riderWage.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626))),
                      ],
                    ),
                  ),

                  if (extraLinkedExpenses > 0)
                    _buildStatementRow('(-) Extra Linked Expenses (Box/Ice)', '-₹${extraLinkedExpenses.toStringAsFixed(0)}', const Color(0xFFDC2626)),
                  const Divider(height: 14, color: Color(0xFFE2E8F0)),
                  _buildStatementRow('Total Direct Order Costs', '-₹${totalCost.toStringAsFixed(0)}', const Color(0xFFB91C1C), isBold: true),
                  const Divider(height: 14, color: Color(0xFFCBD5E1)),
                  _buildStatementRow(
                    isDelivered ? 'Realized Net Profit' : 'Estimated Net Profit (Pending)',
                    '+₹${netProfit.toStringAsFixed(0)} (${marginPct.toStringAsFixed(1)}%)',
                    isDelivered ? const Color(0xFF059669) : const Color(0xFFD97706),
                    isBold: true,
                    fontSize: 13,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // BUTTON: ADD EXTRA EXPENSE TO THIS ORDER
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => onAddExpenseTap(orderRef),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text('Add Extra Expense to Order #$orderRef', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildStatementRow(String title, String amount, Color color, {bool isBold = false, double fontSize = 12}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(fontSize: fontSize, fontWeight: isBold ? FontWeight.w800 : FontWeight.w500, color: const Color(0xFF334155)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(amount, style: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}

// ==========================================
// 2. EXPENSE DETAIL SHEET (WITH DATE & TIME)
// ==========================================

class _ExpenseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> expense;
  final VoidCallback onEditTap;
  final VoidCallback onDeleteTap;

  const _ExpenseDetailSheet({
    required this.expense,
    required this.onEditTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = expense['category'] ?? 'Store Expense';
    final amount = (expense['amount'] as num? ?? 0.0).toDouble();
    final vendor = expense['vendor_name'] ?? 'N/A';
    final desc = expense['description'] ?? 'No notes recorded.';
    final paymentMode = (expense['payment_mode'] ?? 'cash_drawer').toString().replaceAll('_', ' ').toUpperCase();
    final orderRef = expense['order_ref']?.toString();
    final staff = expense['staff_name'] ?? 'Store Staff';
    final dateFormatted = _CashflowScreenState.formatDateTime(expense['created_at'] ?? expense['date']);
    final billUrl = expense['bill_proof_url']?.toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Expense Details', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
              Text('₹${amount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626))),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          _buildInfoRow('Category', category),
          _buildInfoRow('Vendor / Recipient', vendor),
          _buildInfoRow('Payment Mode', paymentMode),
          _buildInfoRow('Linked Order', orderRef != null && orderRef.isNotEmpty && orderRef != 'general' ? '#$orderRef' : 'General Store Ops'),
          _buildInfoRow('Logged By Staff', staff),
          _buildInfoRow('Date & Time', dateFormatted),
          _buildInfoRow('Remarks', desc),
          if (billUrl != null && billUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Receipt / Bill Proof:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(billUrl, height: 120, width: double.infinity, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 20),

          // ACTION BUTTONS: EDIT & DELETE
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onDeleteTap,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onEditTap,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text('Edit Expense', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

// ==========================================
// 3. ADD OR EDIT EXPENSE MODAL
// ==========================================

class _AddOrEditExpenseModal extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> activeOrders;
  final Map<String, dynamic>? existingExpense;
  final String? initialOrderRef;
  final String? initialCategory;
  final double? initialAmount;

  const _AddOrEditExpenseModal({
    required this.activeOrders,
    this.existingExpense,
    this.initialOrderRef,
    this.initialCategory,
    this.initialAmount,
  });

  @override
  ConsumerState<_AddOrEditExpenseModal> createState() => _AddOrEditExpenseModalState();
}

class _AddOrEditExpenseModalState extends ConsumerState<_AddOrEditExpenseModal> {
  final SoundService _soundService = SoundService();
  bool _isSubmitting = false;

  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _selectedCategory = 'Ice & Cooling';
  String _paymentMode = 'cash_drawer';
  String? _selectedOrderRef;
  String? _billPhotoUrl;

  final List<String> _categories = [
    'Ice & Cooling',
    'Packing Materials',
    'Transport & Fuel',
    'Porter & Loading',
    'Cleaning & Supplies',
    'Tea & Refreshments',
    'Cutter Labor Wage',
    'Delivery Partner Payout',
    'Direct Seafood Buying',
    'Other Store Expenses',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingExpense != null) {
      final e = widget.existingExpense!;
      _selectedCategory = e['category'] ?? 'Ice & Cooling';
      if (!_categories.contains(_selectedCategory)) {
        _categories.add(_selectedCategory);
      }
      _amountCtrl.text = (e['amount'] as num? ?? 0.0).toStringAsFixed(0);
      _vendorCtrl.text = e['vendor_name'] ?? '';
      _descCtrl.text = e['description'] ?? '';
      _paymentMode = e['payment_mode'] ?? 'cash_drawer';
      _selectedOrderRef = e['order_ref'] ?? 'general';
      _billPhotoUrl = e['bill_proof_url'];
    } else {
      _selectedOrderRef = widget.initialOrderRef ?? 'general';
      if (widget.initialCategory != null && _categories.contains(widget.initialCategory)) {
        _selectedCategory = widget.initialCategory!;
      }
      if (widget.initialAmount != null && widget.initialAmount! > 0) {
        _amountCtrl.text = widget.initialAmount!.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBillImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked != null && mounted) {
      final uploadedUrl = await showDialog<String>(
        context: context,
        builder: (ctx) => ImageCropDialog(imageFile: File(picked.path), bucketName: 'fish-images'),
      );
      if (uploadedUrl != null && mounted) {
        setState(() => _billPhotoUrl = uploadedUrl);
      }
    }
  }

  Future<void> _submitExpense() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0) {
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid expense amount!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    AppHaptics.mediumImpact();

    try {
      final authState = ref.read(authNotifierProvider);
      final profile = authState.staffProfile;
      final staffName = profile?['name'] ?? 'Store Staff';
      final staffId = profile?['id']?.toString() ?? profile?['auth_id']?.toString();

      final db = Supabase.instance.client;
      final now = DateTime.now();

      int? linkedOrderId;
      if (_selectedOrderRef != null && _selectedOrderRef != 'general') {
        final match = widget.activeOrders.firstWhere(
          (o) => (o['order_ref'] ?? o['id']).toString() == _selectedOrderRef,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          linkedOrderId = match['id'] as int?;
        }
      }

      final expenseType = _selectedCategory == 'Cutter Labor Wage'
          ? 'labour_wage'
          : _selectedCategory == 'Delivery Partner Payout'
              ? 'delivery_payout'
              : 'store_operational';

      if (widget.existingExpense != null) {
        // UPDATE EXISTING
        await db.from('expenses').update({
          'category': _selectedCategory,
          'expense_type': expenseType,
          'amount': amount,
          'order_ref': _selectedOrderRef != 'general' ? _selectedOrderRef : null,
          'order_id': linkedOrderId,
          'vendor_name': _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : null,
          'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
          'payment_mode': _paymentMode,
          'bill_proof_url': _billPhotoUrl,
          'staff_name': staffName,
          'staff_id': staffId,
          'created_at': now.toIso8601String(),
        }).eq('id', widget.existingExpense!['id']);
      } else {
        // INSERT NEW
        await db.from('expenses').insert({
          'category': _selectedCategory,
          'expense_type': expenseType,
          'amount': amount,
          'order_ref': _selectedOrderRef != 'general' ? _selectedOrderRef : null,
          'order_id': linkedOrderId,
          'vendor_name': _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : null,
          'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
          'payment_mode': _paymentMode,
          'bill_proof_url': _billPhotoUrl,
          'staff_name': staffName,
          'staff_id': staffId,
          'branch_location': profile?['branch_location'] ?? 'Pulicat Central Store',
          'date': now.toIso8601String().substring(0, 10),
        });
      }

      _soundService.playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.existingExpense != null
                      ? 'Expense updated successfully!'
                      : 'Expense of ₹${amount.toStringAsFixed(0)} Logged in Ledger!',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save expense error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingExpense != null;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Edit Expense Entry' : 'Add Expense Entry',
                    style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ORDER LINKER
            DropdownButtonFormField<String>(
              initialValue: _selectedOrderRef ?? 'general',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Link Expense to Order ID',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
              items: [
                DropdownMenuItem(
                  value: 'general',
                  child: Text('General Store Operation (No Order Link)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                ),
                ...widget.activeOrders.map((o) {
                  final ref = (o['order_ref'] ?? o['id']).toString();
                  final cust = o['customer_name'] ?? 'Customer';
                  return DropdownMenuItem(
                    value: ref,
                    child: Text('Order #$ref — $cust', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                  );
                }),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedOrderRef = val);
              },
            ),
            const SizedBox(height: 12),

            // EXPENSE CATEGORY
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Expense Category',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.inter(fontSize: 13)))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: 12),

            // AMOUNT
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
              decoration: InputDecoration(
                labelText: 'Total Amount (₹)',
                prefixText: '₹ ',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),

            // VENDOR
            TextField(
              controller: _vendorCtrl,
              decoration: InputDecoration(
                labelText: 'Vendor / Recipient Name',
                hintText: 'e.g. Kasimedu Ice Plant / Cutter / Rider',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),

            // PAYMENT MODE
            Text('PAYMENT SOURCE:', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      AppHaptics.selectionClick();
                      setState(() => _paymentMode = 'cash_drawer');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _paymentMode == 'cash_drawer' ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _paymentMode == 'cash_drawer' ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                      ),
                      child: Center(
                        child: Text(
                          '💵 Cash Drawer',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: _paymentMode == 'cash_drawer' ? FontWeight.w900 : FontWeight.w600,
                            color: _paymentMode == 'cash_drawer' ? const Color(0xFFB45309) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      AppHaptics.selectionClick();
                      setState(() => _paymentMode = 'online_upi');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _paymentMode == 'online_upi' ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _paymentMode == 'online_upi' ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
                      ),
                      child: Center(
                        child: Text(
                          '📱 Store UPI / GPay',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: _paymentMode == 'online_upi' ? FontWeight.w900 : FontWeight.w600,
                            color: _paymentMode == 'online_upi' ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // NOTES
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes / Remarks (Optional)',
                hintText: 'Add details...',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),

            // PHOTO
            InkWell(
              onTap: _pickBillImage,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(_billPhotoUrl != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined,
                        color: _billPhotoUrl != null ? const Color(0xFF059669) : const Color(0xFF64748B), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _billPhotoUrl != null ? 'Receipt Attached ✅' : 'Attach Receipt Photo (Optional)',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SUBMIT
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _isSubmitting ? null : _submitExpense,
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        isEdit ? 'Save Changes' : 'Save to Cashflow Ledger',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
