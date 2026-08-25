import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/order_status_pipeline.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/order_repository.dart';
import '../../core/providers/order_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/workflow_stepper_widget.dart';
import '../../core/widgets/animated_search_hint.dart';
import '../market/market_updater_widget.dart';
import '../drawer/partner_drawer.dart';
import 'weight_confirmation_dialog.dart';
import 'packing_verification_dialog.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/shift_prefs.dart';
import 'widgets/shift_start_dialog.dart';
import 'widgets/order_card_widget.dart';
import 'widgets/order_empty_view.dart';
import '../support/store_support_chat_screen.dart';

class OrderPipelineScreen extends ConsumerStatefulWidget {
  const OrderPipelineScreen({super.key});

  @override
  ConsumerState<OrderPipelineScreen> createState() => _OrderPipelineScreenState();
}

class _OrderPipelineScreenState extends ConsumerState<OrderPipelineScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SoundService _soundService = SoundService();
  Timer? _searchDebounce;

  // Smooth Directional Swipe & Stage Switching State
  bool _isMovingForward = true;
  double _horizontalDragAccumulated = 0;
  bool _isHeaderVisible = true;

  // Daily Morning Shift Start (07:00 AM - 06:00 PM) State
  bool _hasShiftStartedToday = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPrompt(context);
        AppUpdateService().subscribeRealtime(context);
        _checkAndPromptMorningShiftStart(forcePrompt: false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _searchDebounce?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(ordersNotifierProvider.notifier).fetchAll();
    }
  }

  Future<void> _checkAndPromptMorningShiftStart({bool forcePrompt = false}) async {
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      if (authUserId == null || authUserId.isEmpty) return;

      // 1. FAST PATH: Check local storage first (instant zero-delay, zero-popup)
      try {
        final prefs = await SharedPreferences.getInstance();
        final localShiftDate = prefs.getString(ShiftPrefs.startedDateKey(authUserId));
        if (localShiftDate == todayStr) {
          if (mounted) {
            setState(() {
              _hasShiftStartedToday = true;
            });
          }
          if (!forcePrompt) return; // Shift already started today! Do NOT pop up.
        }
      } catch (_) {}

      // 2. BACKEND SYNC: Check cloud attendance record for this user only
      final client = Supabase.instance.client;
      final row = await client
          .from('staff_attendance')
          .select('id, check_in_time, status')
          .eq('date', todayStr)
          .eq('auth_id', authUserId)
          .maybeSingle();

      if (row != null) {
        final dtStr = row['check_in_time']?.toString();
        String formattedTime = '07:00 AM';
        if (dtStr != null) {
          try {
            formattedTime = DateFormat('hh:mm a').format(DateTime.parse(dtStr).toLocal());
          } catch (_) {}
        }

        // Cache locally so future app launches never prompt again today
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(ShiftPrefs.startedDateKey(authUserId), todayStr);
          await prefs.setString(ShiftPrefs.formattedTimeKey(authUserId), formattedTime);
        } catch (_) {}

        if (mounted) {
          setState(() {
            _hasShiftStartedToday = true;
          });
        }
        if (!forcePrompt) return;
      }

      // 3. PROMPT MODAL ONLY IF EXPLICITLY REQUESTED (MANUAL TAP)
      if (forcePrompt) {
        if (mounted) {
          final authState = ref.read(authNotifierProvider);
          final profile = authState.staffProfile;
          final staffName = profile?['name'] ?? 'Store Manager';
          final staffId = profile?['id']?.toString();
          if (staffId == null || staffId.isEmpty) return;

          await ShiftStartDialog.show(
            context,
            staffName: staffName,
            staffId: staffId,
            onShiftStarted: () {
              if (mounted) {
                setState(() {
                  _hasShiftStartedToday = true;
                });
              }
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Check shift start notice: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _switchToStage(OrderStatusPipeline newStage) {
    final currentStage = ref.read(ordersNotifierProvider).selectedStage;
    if (newStage == currentStage) return;

    final stages = OrderWorkflowStepperWidget.workflowStages;
    final oldIdx = stages.indexOf(currentStage);
    final newIdx = stages.indexOf(newStage);

    setState(() {
      _isMovingForward = newIdx >= oldIdx;
      _isHeaderVisible = true;
    });

    ref.read(ordersNotifierProvider.notifier).setSelectedStage(newStage);
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openOrderChat(String phone, String orderRef, [Map<String, dynamic>? order]) {
    AppHaptics.selectionClick();
    final customerUserId = order?['user_id']?.toString() ?? '';
    final orderId = (order?['id'] as num?)?.toInt();
    final customerName = (order?['customer_name'] ?? order?['name'])?.toString();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreSupportChatScreen(
          customerUserId: customerUserId,
          orderId: orderId,
          orderRef: orderRef,
          customerName: customerName,
          customerPhone: phone,
        ),
      ),
    );
  }

  void _showOrderCompletedCelebrationDialog(Map<String, dynamic> order) {
    final orderRef = order['order_ref'] ?? 'ORDER #${order['id']}';
    final customerName = order['customer_name'] ?? 'Customer';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration_rounded, color: AppColors.accent, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              '🎉 ORDER COMPLETED!',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: 6),
            Text(
              '$orderRef for $customerName has been successfully fulfilled & delivered!',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Order completed successfully! 🌟',
                style: AppTextStyles.badge.copyWith(fontSize: 12, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text('GREAT! DONE', style: AppTextStyles.badge.copyWith(fontSize: 13, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

    double _calculateDefaultCleaningWageFromInventory(Map<String, dynamic> o) {
    final items = o['order_items'] as List? ?? [];
    double totalCleaning = 0.0;
    for (var item in items) {
      final fee = (item['cleaning_fee'] as num?)?.toDouble() ?? 0.0;
      if (fee > 0) {
        totalCleaning += fee;
      } else {
        final fish = item['fish_items'] as Map<String, dynamic>?;
        final defClean = (fish?['cleaning_charge'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity_kg'] as num? ?? 1.0).toDouble();
        if (item['with_cleaning'] == true || defClean > 0) {
          totalCleaning += (defClean > 0 ? (defClean * qty) : (30.0 * qty));
        }
      }
    }
    return totalCleaning > 0 ? totalCleaning : 25.0;
  }

  void _showCleaningWageEntryDialog({
    required Map<String, dynamic> order,
    required double defaultWage,
    required VoidCallback onProceed,
  }) {
    final ctrl = TextEditingController(text: defaultWage.toStringAsFixed(0));
    final orderRef = order['order_ref'] ?? 'ORDER #${order['id']}';
    final customerName = order['customer_name'] ?? 'Customer';
    final items = order['order_items'] as List? ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.content_cut_rounded, color: Color(0xFF7C3AED), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cleaning & Cutter Wage', style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                  Text('$orderRef • $customerName', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDCFCE7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pre-filled from Inventory Cleaning setup (₹${defaultWage.toStringAsFixed(0)})',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (items.isNotEmpty) ...[
              ...items.map((item) {
                final fish = item['fish_items'] as Map<String, dynamic>?;
                final name = fish?['name'] ?? 'Fresh Fish';
                final qty = (item['quantity_kg'] as num? ?? 1.0).toDouble();
                final cut = item['cutting_type'] ?? 'Slice Cut';
                final photoUrl = fish?['image_url'] as String?;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (photoUrl != null && photoUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(photoUrl, width: 28, height: 28, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF2563EB))),
                        )
                      else
                        const Icon(Icons.set_meal_rounded, size: 20, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$name (${qty.toStringAsFixed(1)}kg) — $cut',
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
            Text('CONFIRM CUTTER WAGE PAID (₹):', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF7C3AED)),
              decoration: InputDecoration(
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
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              final enteredAmt = double.tryParse(ctrl.text) ?? defaultWage;
              Navigator.pop(ctx);

              try {
                final db = Supabase.instance.client;
                final profile = ref.read(authNotifierProvider).staffProfile;
                final staffName = profile?['name'] ?? 'Store Staff';
                final staffId = profile?['id']?.toString() ?? profile?['auth_id']?.toString();
                final now = DateTime.now();

                await db.from('expenses').insert({
                  'category': 'Cutter Labor Wage',
                  'expense_type': 'labour_wage',
                  'amount': enteredAmt,
                  'order_ref': order['order_ref'],
                  'order_id': order['id'],
                  'description': 'Cleaning & Cutting wage confirmed in order pipeline',
                  'payment_mode': 'cash_drawer',
                  'staff_name': staffName,
                  'staff_id': staffId,
                  'branch_location': profile?['branch_location'] ?? 'Pulicat Central Store',
                  'date': now.toIso8601String().substring(0, 10),
                });
              } catch (e) {
                debugPrint('Save cleaning wage error: $e');
              }

              onProceed();
            },
            child: Text('Confirm Wage (₹)', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showWeightConfirmation(
    Map<String, dynamic> order,
    OrderStatusPipeline nextStage,
    OrdersNotifier notifier,
    bool isSoundMuted,
  ) {
    final orderItems = order['order_items'] as List? ?? [];
    double totalWeight = 0.0;
    for (final it in orderItems) {
      totalWeight += ((it['quantity_kg'] as num?)?.toDouble() ?? 1.0);
    }
    if (totalWeight <= 0) totalWeight = 1.0;

    final totalPrice = (order['total_price'] as num? ?? (totalWeight * 500.0)).toDouble();
    final avgPricePerKg = totalWeight > 0 ? (totalPrice / totalWeight) : 500.0;

    showDialog(
      context: context,
      builder: (ctx) => WeightConfirmationDialog(
        orderRef: order['order_ref'] ?? 'ORDER #${order['id']}',
        orderedWeightKg: totalWeight,
        pricePerKg: avgPricePerKg,
        orderedTotalPrice: totalPrice,
        orderItems: orderItems,
        themeColor: OrderCardWidget.getStageLiveColor(nextStage),
        onConfirmed: (confirmedWeight, finalPrice, weightProofUrl) async {
          await notifier.updateWeight(
            orderId: order['id'],
            confirmedWeight: confirmedWeight,
            finalPrice: finalPrice,
            originalWeight: totalWeight,
            weightProofUrl: weightProofUrl,
          );
          notifier.setSelectedStage(nextStage);
          AppHaptics.success();
          if (!isSoundMuted) {
            _soundService.playSuccessChime();
          }
          if (mounted) {
            final isChanged = (confirmedWeight - totalWeight).abs() > 0.02;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isChanged
                      ? '⚖️ ${order['order_ref']} Weight updated (${confirmedWeight.toStringAsFixed(2)}kg - ₹${finalPrice.toStringAsFixed(0)}) — sent for customer approval.'
                      : '✅ ${order['order_ref']} Weight confirmed (${confirmedWeight.toStringAsFixed(2)}kg - ₹${finalPrice.toStringAsFixed(0)})',
                ),
                backgroundColor: isChanged ? const Color(0xFFD97706) : const Color(0xFF059669),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _advanceOrderStage(Map<String, dynamic> order) async {
    final currentStatusCode = (order['status'] as String? ?? 'new_order');
    final currentStage = OrderStatusPipelineExt.fromCode(currentStatusCode);
    final isCleaningRequired = OrderCardWidget.isCleaningRequiredForOrder(order);

    final nextStage = currentStage == OrderStatusPipeline.weightConfirmed
        ? (isCleaningRequired ? OrderStatusPipeline.cleaning : OrderStatusPipeline.packed)
        : currentStage.nextStage;

    if (nextStage == null) return;

    final notifier = ref.read(ordersNotifierProvider.notifier);
    final isSoundMuted = ref.read(ordersNotifierProvider).isSoundMuted;

    final isWeightAdjusted = order['is_weight_adjusted'] == true;
    final weightStatus = (order['weight_update_status'] as String? ?? '').toLowerCase().trim();
    final isWaitingApproval = isWeightAdjusted && (weightStatus == 'pending_approval' || weightStatus == 'pending');
    final isRejected = isWeightAdjusted && (weightStatus == 'rejected' || weightStatus == 'declined');

    // If waiting for customer approval, block advancement and inform staff
    if (currentStage == OrderStatusPipeline.weightConfirmed && isWaitingApproval) {
      AppHaptics.warning();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⏳ Waiting for customer to accept weight adjustment.'),
            backgroundColor: const Color(0xFFEA580C),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Re-weigh',
              textColor: Colors.white,
              onPressed: () => _showWeightConfirmation(order, currentStage, notifier, isSoundMuted),
            ),
          ),
        );
      }
      return;
    }

    // If customer rejected weight, reopen weight confirmation
    if (currentStage == OrderStatusPipeline.weightConfirmed && isRejected) {
      AppHaptics.error();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Customer rejected the weight adjustment. Please re-confirm the weight.'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 4),
          ),
        );
      }
      _showWeightConfirmation(order, currentStage, notifier, isSoundMuted);
      return;
    }

    // 1. Moving from New Order -> Weight Confirmed (Scale & Weight Confirmation Dialog)
    if (nextStage == OrderStatusPipeline.weightConfirmed) {
      _showWeightConfirmation(order, nextStage, notifier, isSoundMuted);
      return;
    }

    // 2. Moving from Weight Confirmed -> Cleaning (Enter Cleaning Wage Dialog)
    if (nextStage == OrderStatusPipeline.cleaning) {
      final defaultWage = _calculateDefaultCleaningWageFromInventory(order);
      _showCleaningWageEntryDialog(
        order: order,
        defaultWage: defaultWage,
        onProceed: () async {
          await notifier.updateStatus(order['id'], nextStage.code);
          notifier.setSelectedStage(nextStage);
          AppHaptics.success();
          if (!isSoundMuted) {
            _soundService.playSuccessChime();
          }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✂️ ${order['order_ref']} Moved to Cleaning & Cutting'),
                  backgroundColor: OrderCardWidget.getStageLiveColor(nextStage),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
        },
      );
      return;
    }

    if (nextStage == OrderStatusPipeline.packed) {
      showDialog(
        context: context,
        builder: (ctx) => PackingVerificationDialog(
          order: order,
          themeColor: OrderCardWidget.getStageLiveColor(nextStage),
          onConfirmed: () async {
            await notifier.updateStatus(order['id'], nextStage.code);
            notifier.setSelectedStage(nextStage);
            AppHaptics.success();
            if (!isSoundMuted) {
              _soundService.playSuccessChime();
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📦 ${order['order_ref']} Verified & Shifted to PACKED'),
                  backgroundColor: OrderCardWidget.getStageLiveColor(nextStage),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      );
    } else if (nextStage == OrderStatusPipeline.handedOver) {
      var partners = ref.read(ordersNotifierProvider).deliveryPartners;
      if (partners.isEmpty) {
        partners = await OrderRepository().fetchDeliveryPartners(forceRefresh: true);
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: OrderCardWidget.getStageLiveColor(nextStage).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.delivery_dining_rounded, color: OrderCardWidget.getStageLiveColor(nextStage), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assign Delivery Partner',
                            style: AppTextStyles.h3,
                          ),
                          Text(
                            'Select delivery partner (Order ${order['order_ref'] ?? "MM00001"})',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 24),
                ...partners.map((partner) {
                  final pName = (partner['name'] ?? 'Delivery Partner').toString();
                  final pPhone = (partner['phone'] ?? '').toString();
                  final pVehicle = (partner['vehicle_number'] ?? '').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: OrderCardWidget.getStageLiveColor(nextStage).withValues(alpha: 0.12),
                          child: Icon(Icons.person_pin_rounded, color: OrderCardWidget.getStageLiveColor(nextStage), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pName,
                                style: AppTextStyles.bodyLarge.copyWith(fontSize: 14.5, fontWeight: FontWeight.w900),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '📞 $pPhone  •  🏍️ ${pVehicle.isNotEmpty ? pVehicle : "N/A"}',
                                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OrderCardWidget.getStageLiveColor(nextStage),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            AppHaptics.success();
                            _soundService.playSuccessChime();
                            final dispatched = await notifier.assignPartner(order['id'], partner['id']);
                            if (!dispatched) return;
                            notifier.setSelectedStage(nextStage);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✅ ${order['order_ref']} Handed Over to $pName ($pPhone)'),
                                  backgroundColor: OrderCardWidget.getStageLiveColor(nextStage),
                                ),
                              );
                            }
                          },
                          child: Text('ASSIGN', style: AppTextStyles.badge.copyWith(fontSize: 11, color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyBlue,
                      side: BorderSide(color: AppColors.navyBlue.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      AppHaptics.mediumImpact();
                      _soundService.playStepTransition();
                      await notifier.updateStatus(order['id'], nextStage.code);
                      notifier.setSelectedStage(nextStage);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('➡️ Shifted to HANDED OVER (Partner assign later)'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.fast_forward_rounded, size: 18, color: AppColors.navyBlue),
                    label: Text(
                      'SKIP / ASSIGN LATER',
                      style: AppTextStyles.badge.copyWith(fontSize: 11.5, color: AppColors.navyBlue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      AppHaptics.heavyImpact();
      if (!isSoundMuted) {
        if (nextStage == OrderStatusPipeline.completed) {
          _soundService.playSuccessChime();
        } else {
          _soundService.playStepTransition();
        }
      }
      if (nextStage == OrderStatusPipeline.completed) {
        _showOrderCompletedCelebrationDialog(order);
      }

      await notifier.updateStatus(order['id'], nextStage.code);
      notifier.setSelectedStage(nextStage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('➡️ ${order['order_ref']} shifted to ${nextStage.labelEnglish}'),
            backgroundColor: nextStage == OrderStatusPipeline.completed ? const Color(0xFF059669) : nextStage.color,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showCancelOrderDialog(Map<String, dynamic> order) {
    final orderRef = order['order_ref'] ?? 'ORDER #${order['id']}';
    final customerName = order['customer_name'] ?? 'Customer';
    final reasons = [
      '🐟 Out of Stock',
      '❌ Customer Requested Cancellation',
      '⏱️ Store Closing / Cannot Fulfill',
      '⚖️ Weight / Price Discrepancy',
      '⚠️ Delivery Partner Unavailable',
    ];

    String selectedReason = reasons.first;
    final otherReasonCtrl = TextEditingController();
    bool isOther = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
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
                child: const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cancel Order?', style: AppTextStyles.h3),
                    Text('$orderRef • $customerName', style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select reason for cancellation:', style: AppTextStyles.bodyMedium),
                const SizedBox(height: 10),
                ...reasons.map((reason) {
                  final isSelected = !isOther && selectedReason == reason;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () {
                        setModalState(() {
                          isOther = false;
                          selectedReason = reason;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 16,
                              color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                reason,
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF991B1B) : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (isOther) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherReasonCtrl,
                    style: AppTextStyles.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Enter cancellation reason...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('NO, GO BACK', style: AppTextStyles.badge.copyWith(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final finalReason = isOther
                    ? (otherReasonCtrl.text.trim().isNotEmpty ? otherReasonCtrl.text.trim() : 'Store Cancelled')
                    : selectedReason;

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  AppHaptics.heavyImpact();
                  ref.read(ordersNotifierProvider.notifier).updateStatus(
                    order['id'],
                    OrderStatusPipeline.cancelled.code,
                    reason: finalReason,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ $orderRef Cancelled: $finalReason'),
                      backgroundColor: const Color(0xFFDC2626),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: Text('CONFIRM CANCEL', style: AppTextStyles.badge.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecentNotificationsSheet() {
    ref.read(ordersNotifierProvider.notifier).clearUnreadNotifications();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final notifs = ref.watch(ordersNotifierProvider.select((s) => s.recentNotifications));
            final isSoundMuted = ref.watch(ordersNotifierProvider.select((s) => s.isSoundMuted));

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF059669), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Recent Notifications', style: AppTextStyles.h3),
                              Text('Realtime Live Push Feed', style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            ref.read(ordersNotifierProvider.notifier).toggleSound();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSoundMuted ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isSoundMuted ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSoundMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                  size: 15,
                                  color: isSoundMuted ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isSoundMuted ? 'Muted' : 'Sound ON',
                                  style: AppTextStyles.badge.copyWith(
                                    color: isSoundMuted ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Expanded(
                    child: notifs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.notifications_none_rounded, size: 48, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 8),
                                  Text('No new notifications', style: AppTextStyles.bodyLarge),
                                  const SizedBox(height: 4),
                                  Text('Realtime live sync is active.', style: AppTextStyles.caption),
                                  const SizedBox(height: 20),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () async {
                                      AppHaptics.mediumImpact();
                                      await NotificationService().sendTestNotification();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('🔔 Test Notification sent! Check your notification bar.'),
                                            backgroundColor: Color(0xFF059669),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.send_rounded, size: 16),
                                    label: Text(
                                      'TEST NOTIFICATION & SOUND',
                                      style: AppTextStyles.badge.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            itemCount: notifs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final notif = notifs[idx];
                              final title = notif['title'] as String? ?? 'Notification';
                              final body = notif['body'] as String? ?? '';
                              final status = notif['status'] as String? ?? 'new_order';
                              final stage = OrderStatusPipelineExt.fromCode(status);

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: stage.color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(stage.icon, color: stage.color, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 2),
                                          Text(body, style: AppTextStyles.caption),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderState = ref.watch(ordersNotifierProvider);
    final selectedFilter = orderState.selectedStage;
    final orderCountsMap = ref.watch(orderStageCountsProvider);
    final filteredOrders = ref.watch(filteredOrdersProvider);
    final activeStageColor = OrderCardWidget.getStageLiveColor(selectedFilter);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const PartnerDrawer(),
      body: Column(
        children: [
          // DYNAMIC STAGE BRAND HEADER (AUTO COLLAPSIBLE TOP SEARCH BAR, STICKY STEPPER)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            color: activeStageColor,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: _isHeaderVisible
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      AppHaptics.selectionClick();
                                      _scaffoldKey.currentState?.openDrawer();
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        if (!_searchFocusNode.hasFocus &&
                                            _searchController.text.isEmpty &&
                                            orderState.searchQuery.isEmpty)
                                          Positioned.fill(
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 38, right: 36),
                                              child: IgnorePointer(
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: AnimatedSearchHint(
                                                    hints: const [
                                                      'Search "Vanjaram / Fish"...',
                                                      'Search order #MM-08...',
                                                      'Search "Prawns / Crab"...',
                                                      'Search customer "Balaji"...',
                                                      'Search "Light House Kuppam"...',
                                                      'Search "Curry Cut / Slices"...',
                                                      'Search mobile "9876543210"...',
                                                    ],
                                                    style: GoogleFonts.plusJakartaSans(
                                                      color: const Color(0xFF64748B),
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          textAlignVertical: TextAlignVertical.center,
                                          cursorColor: activeStageColor,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF0F172A),
                                          ),
                                          textInputAction: TextInputAction.search,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            filled: false,
                                            fillColor: Colors.transparent,
                                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: activeStageColor),
                                            prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                            hintText: (_searchFocusNode.hasFocus && _searchController.text.isEmpty)
                                                ? 'Search order, fish or customer...'
                                                : null,
                                            hintStyle: GoogleFonts.plusJakartaSans(
                                              color: const Color(0xFF94A3B8),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            suffixIcon: (_searchController.text.isNotEmpty || orderState.searchQuery.isNotEmpty)
                                                ? IconButton(
                                                    icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                    onPressed: () {
                                                      _searchController.clear();
                                                      ref.read(ordersNotifierProvider.notifier).setSearchQuery('');
                                                      setState(() {});
                                                    },
                                                  )
                                                : (_searchFocusNode.hasFocus
                                                    ? IconButton(
                                                        icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                        onPressed: () {
                                                          _searchFocusNode.unfocus();
                                                        },
                                                      )
                                                    : null),
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 0),
                                          ),
                                          onChanged: (val) {
                                            _searchDebounce?.cancel();
                                            _searchDebounce = Timer(const Duration(milliseconds: 150), () {
                                              if (mounted) {
                                                ref.read(ordersNotifierProvider.notifier).setSearchQuery(val);
                                                setState(() {});
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      AppHaptics.selectionClick();
                                      _showRecentNotificationsSheet();
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
                                          if (orderState.unreadNotificationCount > 0)
                                            Positioned(
                                              top: 10,
                                              right: 10,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 1.5),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),

                  // Prompt banner ONLY when Morning Shift is pending (Auto-hides once activated)
                  if (_isHeaderVisible && !_hasShiftStartedToday)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: InkWell(
                        onTap: () {
                          _checkAndPromptMorningShiftStart(forcePrompt: true);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFBBF24),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'MORNING SHIFT PENDING • CLOCK IN NOW',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'TAP TO START 📸',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // PINNED STICKY Workflow Stepper Bar (Isolated RepaintBoundary)
                  RepaintBoundary(
                    child: OrderWorkflowStepperWidget(
                      currentStage: selectedFilter,
                      isInteractive: true,
                      orderCounts: orderCountsMap,
                      onStageSelected: (stage) => _switchToStage(stage),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // MAIN CONTENT BODY WITH SMOOTH DIRECTIONAL SWIPE & AUTO-COLLAPSE ON SCROLL
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo is UserScrollNotification) {
                  if (scrollInfo.direction == ScrollDirection.reverse) {
                    if (_isHeaderVisible && scrollInfo.metrics.pixels > 25) {
                      setState(() => _isHeaderVisible = false);
                    }
                  } else if (scrollInfo.direction == ScrollDirection.forward) {
                    if (!_isHeaderVisible) {
                      setState(() => _isHeaderVisible = true);
                    }
                  }
                } else if (scrollInfo.metrics.pixels <= 10 && !_isHeaderVisible) {
                  setState(() => _isHeaderVisible = true);
                }
                return false;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => _horizontalDragAccumulated = 0,
                onHorizontalDragUpdate: (details) => _horizontalDragAccumulated += details.primaryDelta ?? 0,
                onHorizontalDragEnd: (details) {
                  final stages = OrderWorkflowStepperWidget.workflowStages;
                  final currentIdx = stages.indexOf(selectedFilter);
                  if (currentIdx == -1) return;

                  final velocity = details.primaryVelocity ?? 0;
                  final isSwipeLeft = velocity < -180 || _horizontalDragAccumulated < -45;
                  final isSwipeRight = velocity > 180 || _horizontalDragAccumulated > 45;

                  if (isSwipeLeft && currentIdx < stages.length - 1) {
                    _switchToStage(stages[currentIdx + 1]);
                  } else if (isSwipeRight && currentIdx > 0) {
                    _switchToStage(stages[currentIdx - 1]);
                  }
                  _horizontalDragAccumulated = 0;
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final inForward = _isMovingForward;
                    final slideIn = Tween<Offset>(
                      begin: Offset(inForward ? 0.08 : -0.08, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ));

                    return FadeTransition(
                      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                      child: SlideTransition(position: slideIn, child: child),
                    );
                  },
                  child: (selectedFilter == OrderStatusPipeline.inventoryUpdate || selectedFilter == OrderStatusPipeline.marketUpdated)
                      ? Column(
                          key: ValueKey<OrderStatusPipeline>(selectedFilter),
                          children: [
                            Expanded(
                              child: MarketUpdaterWidget(
                                onlyAvailableItems: selectedFilter == OrderStatusPipeline.marketUpdated,
                                themeColor: activeStageColor,
                              ),
                            ),
                          ],
                        )
                      : Builder(
                          key: ValueKey<OrderStatusPipeline>(selectedFilter),
                          builder: (context) {
                            if (orderState.isLoading) {
                              return const Center(
                                child: CircularProgressIndicator(color: AppColors.primary),
                              );
                            }

                            if (filteredOrders.isEmpty) {
                              return OrderEmptyView(
                                currentStage: selectedFilter,
                                searchQuery: orderState.searchQuery,
                                onRefresh: () => ref.read(ordersNotifierProvider.notifier).fetchAll(),
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: () => ref.read(ordersNotifierProvider.notifier).fetchAll(),
                              color: activeStageColor,
                              backgroundColor: Colors.white,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  10 + MediaQuery.paddingOf(context).bottom + 16,
                                ),
                                cacheExtent: 250,
                                addRepaintBoundaries: true,
                                addAutomaticKeepAlives: false,
                                itemCount: filteredOrders.length,
                                itemBuilder: (context, idx) {
                                  final o = filteredOrders[idx];
                                  return RepaintBoundary(
                                    child: OrderCardWidget(
                                      order: o,
                                      selectedFilter: selectedFilter,
                                      onAdvanceStage: _advanceOrderStage,
                                      onCancel: _showCancelOrderDialog,
                                      onCall: _makePhoneCall,
                                      onWhatsApp: (phone, refStr) => _openOrderChat(phone, refStr, o),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
