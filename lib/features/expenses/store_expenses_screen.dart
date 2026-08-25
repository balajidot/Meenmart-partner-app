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

enum ExpenseTypeFilter { all, procurement, operations }
enum PeriodFilter { today, thisWeek, thisMonth, allTime, custom }

class StoreExpensesScreen extends ConsumerStatefulWidget {
  const StoreExpensesScreen({super.key});

  @override
  ConsumerState<StoreExpensesScreen> createState() => _StoreExpensesScreenState();
}

class _StoreExpensesScreenState extends ConsumerState<StoreExpensesScreen> {
  ExpenseTypeFilter _selectedFilter = ExpenseTypeFilter.all;
  PeriodFilter _selectedPeriod = PeriodFilter.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isLoading = true;

  List<Map<String, dynamic>> _expenses = [];

  double get _totalExpenses {
    double sum = 0.0;
    for (var e in _expenses) {
      sum += (e['amount'] as num? ?? 0.0).toDouble();
    }
    return sum;
  }

  double get _procurementExpenses {
    double sum = 0.0;
    for (var e in _expenses) {
      if (e['expense_type'] == 'fish_procurement' || e['category'] == 'Fish Purchase') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  double get _operationsExpenses {
    double sum = 0.0;
    for (var e in _expenses) {
      if (e['expense_type'] != 'fish_procurement' && e['category'] != 'Fish Purchase') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  double get _cashDrawerExpenses {
    double sum = 0.0;
    for (var e in _expenses) {
      if (e['payment_mode'] == 'cash_drawer' || e['payment_mode'] == 'cash') {
        sum += (e['amount'] as num? ?? 0.0).toDouble();
      }
    }
    return sum;
  }

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
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
      _fetchExpenses();
    }
  }

  Future<void> _fetchExpenses() async {
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

      var query = db.from('expenses').select('*');
      if (filterStart != null) {
        query = query.gte('created_at', filterStart.toUtc().toIso8601String());
      }
      if (filterEnd != null) {
        query = query.lte('created_at', filterEnd.toUtc().toIso8601String());
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(500)
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        setState(() {
          _expenses = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch expenses error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    if (_selectedFilter == ExpenseTypeFilter.procurement) {
      return _expenses.where((e) => e['expense_type'] == 'fish_procurement' || e['category'] == 'Fish Purchase').toList();
    } else if (_selectedFilter == ExpenseTypeFilter.operations) {
      return _expenses.where((e) => e['expense_type'] != 'fish_procurement' && e['category'] != 'Fish Purchase').toList();
    }
    return _expenses;
  }

  void _showAddExpenseDialog() {
    AppHaptics.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddExpenseModal(),
    ).then((added) {
      if (added == true) {
        _fetchExpenses();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
          'Store & Packer Expenses',
          style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            tooltip: 'Refresh Expenses',
            onPressed: _fetchExpenses,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _fetchExpenses,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 0. PERIOD FILTER BAR (TODAY, THIS WEEK, THIS MONTH, ALL-TIME, CALENDAR)
                    _buildPeriodFilterSection(),
                    const SizedBox(height: 14),

                    // 1. EXPENSES SUMMARY KPI CARD
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TOTAL STORE EXPENSES',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.4),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${_totalExpenses.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
                                  ),
                                ],
                              ),
                              AppBadges.warning('₹${_cashDrawerExpenses.toStringAsFixed(0)} CASH DRAWER', icon: Icons.point_of_sale_rounded),
                            ],
                          ),
                          const Divider(height: 24, color: Color(0xFFF1F5F9)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMiniKpi('Fish Procurement', '₹${_procurementExpenses.toStringAsFixed(0)}', const Color(0xFF2563EB)),
                              _buildMiniKpi('Daily Store Ops', '₹${_operationsExpenses.toStringAsFixed(0)}', const Color(0xFFD97706)),
                              _buildMiniKpi('Records', '${_expenses.length} Entries', const Color(0xFF0F172A)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. FILTER TABS
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          _buildFilterTab(ExpenseTypeFilter.all, 'ALL EXPENSES'),
                          _buildFilterTab(ExpenseTypeFilter.procurement, 'FISH BUYING'),
                          _buildFilterTab(ExpenseTypeFilter.operations, 'STORE OPS'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. EXPENSES LIST
                    if (_filteredExpenses.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            const Icon(Icons.receipt_outlined, size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text(
                              'No Expenses Recorded Yet',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap "+ Add New Expense" to record purchases or operating costs.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._filteredExpenses.map((e) => _buildExpenseCard(e)),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _showAddExpenseDialog,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Add New Expense',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildFilterTab(ExpenseTypeFilter filter, String label) {
    final isSel = _selectedFilter == filter;
    return Expanded(
      child: InkWell(
        onTap: () {
          AppHaptics.selectionClick();
          setState(() => _selectedFilter = filter);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? const Color(0xFFE2E8F0) : Colors.transparent),
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                color: isSel ? const Color(0xFF059669) : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
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
                              '${_expenses.length} Store Expenses Recorded',
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
        _fetchExpenses();
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

  Widget _buildMiniKpi(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> e) {
    final category = e['category']?.toString() ?? 'General';
    final amount = (e['amount'] as num? ?? 0.0).toDouble();
    final description = e['description']?.toString() ?? '';
    final itemName = e['item_name']?.toString() ?? '';
    final weight = (e['weight_kg'] as num?)?.toDouble();
    final rate = (e['rate_per_kg'] as num?)?.toDouble();
    final vendor = e['vendor_name']?.toString() ?? '';
    final paymentMode = (e['payment_mode'] ?? 'cash_drawer').toString();
    final isProcurement = e['expense_type'] == 'fish_procurement' || category == 'Fish Purchase';
    final isCashDrawer = paymentMode == 'cash_drawer' || paymentMode == 'cash';

    IconData icon;
    Color iconBg;
    Color iconColor;

    if (isProcurement) {
      icon = Icons.set_meal_rounded;
      iconBg = const Color(0xFFEFF6FF);
      iconColor = const Color(0xFF2563EB);
    } else if (category.contains('Ice')) {
      icon = Icons.ac_unit_rounded;
      iconBg = const Color(0xFFF0FDFA);
      iconColor = const Color(0xFF0F766E);
    } else if (category.contains('Pack')) {
      icon = Icons.inventory_2_outlined;
      iconBg = const Color(0xFFF5F3FF);
      iconColor = const Color(0xFF7C3AED);
    } else if (category.contains('Transport') || category.contains('Auto')) {
      icon = Icons.local_shipping_outlined;
      iconBg = const Color(0xFFFFFBEB);
      iconColor = const Color(0xFFD97706);
    } else if (category.contains('Porter') || category.contains('Coolie')) {
      icon = Icons.fitness_center_rounded;
      iconBg = const Color(0xFFFEF2F2);
      iconColor = const Color(0xFFDC2626);
    } else {
      icon = Icons.receipt_rounded;
      iconBg = const Color(0xFFF1F5F9);
      iconColor = const Color(0xFF475569);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProcurement && itemName.isNotEmpty ? itemName : category,
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (vendor.isNotEmpty)
                      Text(
                        'Vendor: $vendor',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              Text(
                '₹${amount.toStringAsFixed(0)}',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
              ),
            ],
          ),
          if (weight != null && rate != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${weight.toStringAsFixed(1)} kg', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                  Text('@ ₹${rate.toStringAsFixed(0)}/kg', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                  Text('₹${(weight * rate).toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                ],
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isCashDrawer)
                AppBadges.warning('CASH DRAWER')
              else
                AppBadges.info('UPI / ONLINE'),
              if (e['staff_name'] != null)
                AppBadges.capsule(
                  label: 'Staff: ${e['staff_name']}',
                  bgColor: const Color(0xFFF8FAFC),
                  borderColor: const Color(0xFFE2E8F0),
                  textColor: const Color(0xFF475569),
                  fontSize: 9.5,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddExpenseModal extends ConsumerStatefulWidget {
  const _AddExpenseModal();

  @override
  ConsumerState<_AddExpenseModal> createState() => _AddExpenseModalState();
}

class _AddExpenseModalState extends ConsumerState<_AddExpenseModal> {
  final SoundService _soundService = SoundService();
  bool _isProcurementMode = false;
  bool _isSubmitting = false;

  final _itemNameCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _selectedCategory = 'Ice & Cooling';
  String _paymentMode = 'cash_drawer';
  String? _billPhotoUrl;

  final List<String> _opCategories = [
    'Ice & Cooling',
    'Packing Materials',
    'Transport & Fuel',
    'Porter & Loading',
    'Cleaning & Supplies',
    'Tea & Refreshments',
    'Other Store Supplies',
  ];

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _weightCtrl.dispose();
    _rateCtrl.dispose();
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _calculateProcurementAmount() {
    final w = double.tryParse(_weightCtrl.text) ?? 0.0;
    final r = double.tryParse(_rateCtrl.text) ?? 0.0;
    if (w > 0 && r > 0) {
      _amountCtrl.text = (w * r).toStringAsFixed(0);
      setState(() {});
    }
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

      await db.from('expenses').insert({
        'category': _isProcurementMode ? 'Fish Purchase' : _selectedCategory,
        'expense_type': _isProcurementMode ? 'fish_procurement' : 'daily_ops',
        'amount': amount,
        'item_name': _isProcurementMode ? _itemNameCtrl.text.trim() : null,
        'weight_kg': _isProcurementMode ? double.tryParse(_weightCtrl.text) : null,
        'rate_per_kg': _isProcurementMode ? double.tryParse(_rateCtrl.text) : null,
        'vendor_name': _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : null,
        'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        'payment_mode': _paymentMode,
        'bill_proof_url': _billPhotoUrl,
        'staff_name': staffName,
        'staff_id': staffId,
        'branch_location': profile?['branch_location'] ?? 'Pulicat Central Store',
        'date': now.toIso8601String().substring(0, 10),
      });

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
                Text('Expense of ₹${amount.toStringAsFixed(0)} Recorded!', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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
            // Modal Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header (Zero Overflow)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Store Expense',
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
            const SizedBox(height: 14),

            // TYPE TOGGLE: STORE OPS VS FISH BUYING
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        AppHaptics.selectionClick();
                        setState(() => _isProcurementMode = false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: !_isProcurementMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: !_isProcurementMode ? const Color(0xFFE2E8F0) : Colors.transparent),
                          boxShadow: !_isProcurementMode
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            'Store Operations',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: !_isProcurementMode ? FontWeight.w800 : FontWeight.w600,
                              color: !_isProcurementMode ? const Color(0xFF059669) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        AppHaptics.selectionClick();
                        setState(() => _isProcurementMode = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _isProcurementMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _isProcurementMode ? const Color(0xFFE2E8F0) : Colors.transparent),
                          boxShadow: _isProcurementMode
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            'Fish Procurement',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: _isProcurementMode ? FontWeight.w800 : FontWeight.w600,
                              color: _isProcurementMode ? const Color(0xFF059669) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (_isProcurementMode) ...[
              // FISH PROCUREMENT FORM
              TextField(
                controller: _itemNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Seafood Item Name',
                  hintText: 'e.g. Vanjaram, Tiger Prawn, Crab...',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calculateProcurementAmount(),
                      decoration: InputDecoration(
                        labelText: 'Weight (kg)',
                        hintText: '0.0',
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
                      controller: _rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calculateProcurementAmount(),
                      decoration: InputDecoration(
                        labelText: 'Rate / kg (₹)',
                        hintText: '0',
                        prefixText: '₹ ',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              // STORE OPERATIONS CATEGORY DROPDOWN
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
                items: _opCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.inter(fontSize: 13)))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 12),
            ],

            // TOTAL AMOUNT FIELD
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

            // VENDOR / SUPPLIER NAME
            TextField(
              controller: _vendorCtrl,
              decoration: InputDecoration(
                labelText: 'Vendor / Supplier Name',
                hintText: 'e.g. Kasimedu Boat 4 / Ice Plant',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),

            // PAYMENT MODE SELECTOR
            Text(
              'PAYMENT SOURCE:',
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
            ),
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

            // NOTES / REMARKS
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes / Remarks (Optional)',
                hintText: 'Add any details...',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 12),

            // BILL PHOTO BUTTON
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
                        _billPhotoUrl != null ? 'Bill / Voucher Photo Attached ✅' : 'Attach Bill / Receipt Photo (Optional)',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SUBMIT BUTTON
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
                    : Text('Save Expense to Cloud', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
