import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_status_pipeline.dart';
import '../services/order_repository.dart';
import '../services/sound_service.dart';
import '../services/haptic_service.dart';
import '../services/notification_service.dart';

class OrdersState {
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> deliveryPartners;
  final bool isLoading;
  final OrderStatusPipeline selectedStage;
  final String searchQuery;
  final bool isSoundMuted;
  final List<Map<String, dynamic>> recentNotifications;
  final Map<String, dynamic>? latestNotification;
  final int unreadNotificationCount;

  const OrdersState({
    this.orders = const [],
    this.deliveryPartners = const [],
    this.isLoading = true,
    this.selectedStage = OrderStatusPipeline.newOrder,
    this.searchQuery = '',
    this.isSoundMuted = false,
    this.recentNotifications = const [],
    this.latestNotification,
    this.unreadNotificationCount = 0,
  });

  OrdersState copyWith({
    List<Map<String, dynamic>>? orders,
    List<Map<String, dynamic>>? deliveryPartners,
    bool? isLoading,
    OrderStatusPipeline? selectedStage,
    String? searchQuery,
    bool? isSoundMuted,
    List<Map<String, dynamic>>? recentNotifications,
    Map<String, dynamic>? latestNotification,
    int? unreadNotificationCount,
  }) {
    return OrdersState(
      orders: orders ?? this.orders,
      deliveryPartners: deliveryPartners ?? this.deliveryPartners,
      isLoading: isLoading ?? this.isLoading,
      selectedStage: selectedStage ?? this.selectedStage,
      searchQuery: searchQuery ?? this.searchQuery,
      isSoundMuted: isSoundMuted ?? this.isSoundMuted,
      recentNotifications: recentNotifications ?? this.recentNotifications,
      latestNotification: latestNotification ?? this.latestNotification,
      unreadNotificationCount: unreadNotificationCount ?? this.unreadNotificationCount,
    );
  }
}

class OrdersNotifier extends Notifier<OrdersState> {
  final OrderRepository _repo = OrderRepository();
  final SoundService _soundService = SoundService();
  RealtimeChannel? _realtimeChannel;

  @override
  OrdersState build() {
    ref.onDispose(() {
      _realtimeChannel?.unsubscribe();
    });

    // Schedule initial async fetch
    Future.microtask(() => init());

    return const OrdersState();
  }

  Future<void> init() async {
    await fetchAll();
    _setupRealtime();
  }

  static String _extractLocation(Map<String, dynamic> o) {
    final city = (o['city'] ?? '').toString().trim();
    if (city.isNotEmpty) return city;
    final addr = (o['delivery_address'] ?? o['address'] ?? o['location'] ?? '').toString().trim();
    if (addr.isNotEmpty) {
      final parts = addr.split(',');
      return parts.first.trim();
    }
    final village = (o['village'] ?? o['area'] ?? o['landmark'] ?? '').toString().trim();
    if (village.isNotEmpty) return village;
    return 'Pazhaverkadu';
  }

  static String _extractItemsSummary(Map<String, dynamic> o) {
    final items = o['order_items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return 'மீன் பொருட்கள்';
    final list = <String>[];
    for (var item in items) {
      final fish = item['fish_items'] is Map ? item['fish_items'] : {};
      final name = (fish['tamil_name'] ?? fish['name'] ?? item['item_name'] ?? 'மீன்').toString();
      final qty = (item['quantity_kg'] as num? ?? 1.0).toDouble();
      final cutting = (item['cutting_type'] ?? '').toString().toLowerCase();
      final withCleaning = item['with_cleaning'] == true;

      final qtyStr = qty < 1.0
          ? '${(qty * 1000).toInt()}g'
          : '${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} kg';

      final cleanStr = withCleaning ? 'சுத்தம்: ஆம்' : 'சுத்தம்: இல்லை';
      String cuttingClean = '';
      if (cutting.contains('curry')) {
        cuttingClean = 'குழம்பு கட்';
      } else if (cutting.contains('fry')) {
        cuttingClean = 'வறுவல் கட்';
      } else if (cutting.contains('whole')) {
        cuttingClean = 'முழு மீன்';
      } else if (cutting.contains('slice')) {
        cuttingClean = 'ஸ்லைஸ்';
      } else if (cutting.contains('fillet')) {
        cuttingClean = 'ஃபில்லட்';
      } else if (cutting.contains('biryani')) {
        cuttingClean = 'பிரியாணி கட்';
      } else if (cutting.isNotEmpty && cutting != 'none' && cutting != 'raw') {
        cuttingClean = cutting.replaceAll('_', ' ');
      }

      if (cuttingClean.isNotEmpty) {
        list.add('$name ($qtyStr • $cuttingClean • $cleanStr)');
      } else {
        list.add('$name ($qtyStr • $cleanStr)');
      }
    }
    return list.join(', ');
  }

  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true);
    final partners = await _repo.fetchDeliveryPartners();
    final orders = await _repo.fetchLiveOrders(limit: 80);

    // Initial notifications if empty
    final initialNotifs = <Map<String, dynamic>>[];
    for (var o in orders.take(8)) {
      final orderRef = o['order_ref'] ?? '#${o['id']}';
      final customerName = o['customer_name'] ?? 'Customer';
      final totalPrice = (o['total_price'] as num? ?? 0).toDouble();
      final loc = _extractLocation(o);
      final items = _extractItemsSummary(o);

      initialNotifs.add({
        'id': o['id'],
        'title': 'Order $orderRef • ₹${totalPrice.toStringAsFixed(0)}',
        'body': '$customerName • $loc • $items',
        'time_str': o['created_at']?.toString(),
        'order_ref': orderRef,
        'status': o['status'] ?? 'new_order',
        'location': loc,
        'items': items,
      });
    }

    state = state.copyWith(
      orders: orders,
      deliveryPartners: partners,
      isLoading: false,
      recentNotifications: initialNotifs,
      latestNotification: initialNotifs.isNotEmpty ? initialNotifs.first : null,
    );
  }

  void _setupRealtime() {
    try {
      final db = Supabase.instance.client;
      _realtimeChannel = db.channel('store-orders-realtime-engine').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (payload) {
          _handleRealtimePayload(payload);
        },
      );
      _realtimeChannel?.subscribe((status, [error]) {
        debugPrint('Orders Realtime subscription status: $status');
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Realtime orders channel active!');
        }
      });
    } catch (e) {
      debugPrint('Realtime setup error: $e');
    }
  }

  void _handleRealtimePayload(PostgresChangePayload payload) async {
    final newRec = payload.newRecord;
    final eventType = payload.eventType;
    final dynamic orderId = newRec['id'] ?? payload.oldRecord['id'];

    if (orderId == null) {
      await fetchAll();
      return;
    }

    if (eventType == PostgresChangeEvent.delete) {
      final currentList = List<Map<String, dynamic>>.from(state.orders);
      currentList.removeWhere((o) => o['id'] == orderId);
      state = state.copyWith(orders: currentList);
      return;
    }

    // In-memory incremental delta update: fetch ONLY this single updated order with full items
    final updatedSingle = await _repo.fetchSingleOrder(orderId);

    if (updatedSingle != null) {
      final currentList = List<Map<String, dynamic>>.from(state.orders);
      final existingIdx = currentList.indexWhere((o) => o['id'] == orderId);

      if (eventType == PostgresChangeEvent.insert || existingIdx == -1) {
        currentList.insert(0, updatedSingle);
      } else if (eventType == PostgresChangeEvent.update) {
        currentList[existingIdx] = updatedSingle;
      }

      final isInsert = eventType == PostgresChangeEvent.insert;
      final status = (updatedSingle['status'] as String? ?? 'new_order').toLowerCase();
      final oldStatus = (payload.oldRecord['status'] ?? '').toString().toLowerCase();
      final isNewOrder = (isInsert || existingIdx == -1 || (oldStatus == 'pending_payment' && status != 'pending_payment')) &&
          (status == 'new_order' || status == 'pending' || status == 'placed' || status == 'confirmed');
      final isCancelled = status == 'cancelled' && oldStatus != 'cancelled';

      // NOTIFICATIONS ONLY FOR: 1. NEW ORDERS & 2. CANCELLED ORDERS
      if (isNewOrder || isCancelled) {
        AppHaptics.heavyImpact();
        if (!state.isSoundMuted) {
          if (isCancelled) {
            _soundService.playAlertChime();
          } else {
            _soundService.playNewOrderChime();
          }
        }

        final orderRef = updatedSingle['order_ref'] ?? '#$orderId';
        final totalPrice = (updatedSingle['total_price'] as num? ?? 0).toDouble();
        final customerName = updatedSingle['customer_name'] ?? 'Customer';
        final location = _extractLocation(updatedSingle);
        final itemsSummary = _extractItemsSummary(updatedSingle);
        final cancelReason = (updatedSingle['cancel_reason'] ?? updatedSingle['cancellation_reason'] ?? 'Cancelled by Store / Customer').toString();

        final notif = {
          'id': orderId,
          'title': isCancelled
              ? '❌ Order Cancelled: $orderRef'
              : '🚨 New Order $orderRef • ₹${totalPrice.toStringAsFixed(0)}',
          'body': isCancelled
              ? '$customerName • $cancelReason • ₹${totalPrice.toStringAsFixed(0)}'
              : '$customerName • $location • $itemsSummary',
          'time_str': DateTime.now().toIso8601String(),
          'order_ref': orderRef,
          'status': status,
          'location': location,
          'items': itemsSummary,
        };

        try {
          if (isCancelled) {
            await NotificationService().showCancelledOrderNotification(
              orderId: orderId,
              orderRef: orderRef.toString(),
              totalPrice: totalPrice,
              customerName: customerName.toString(),
              location: location,
              reason: cancelReason,
            );
          } else {
            await NotificationService().showNewOrderNotification(
              orderId: orderId,
              orderRef: orderRef.toString(),
              totalPrice: totalPrice,
              customerName: customerName.toString(),
              location: location,
              itemsSummary: itemsSummary,
            );
          }
        } catch (nErr) {
          debugPrint('Local notification trigger error: $nErr');
        }

        final updatedNotifs = List<Map<String, dynamic>>.from(state.recentNotifications);
        updatedNotifs.insert(0, notif);

        state = state.copyWith(
          orders: currentList,
          recentNotifications: updatedNotifs,
          latestNotification: notif,
          unreadNotificationCount: state.unreadNotificationCount + 1,
          selectedStage: isNewOrder ? OrderStatusPipeline.newOrder : state.selectedStage,
        );
      } else {
        // Silent update for all other workflow stages (e.g. weight, clean, pack, dispatch, deliver)
        state = state.copyWith(
          orders: currentList,
        );
      }
    } else {
      await fetchAll();
    }
  }

  void setSelectedStage(OrderStatusPipeline stage) {
    if (stage != state.selectedStage) {
      AppHaptics.selectionClick();
      state = state.copyWith(selectedStage: stage);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query.trim().toLowerCase());
  }

  void toggleSound() {
    AppHaptics.lightImpact();
    state = state.copyWith(isSoundMuted: !state.isSoundMuted);
  }

  void clearUnreadNotifications() {
    state = state.copyWith(unreadNotificationCount: 0);
  }

  Future<bool> updateStatus(
    dynamic orderId,
    String newStatus, {
    String? reason,
    Map<String, dynamic>? extraData,
  }) async {
    // Optimistic in-memory mutation for instant UI response
    final currentList = List<Map<String, dynamic>>.from(state.orders);
    final idx = currentList.indexWhere((o) => o['id'] == orderId);
    if (idx != -1) {
      final old = currentList[idx];
      final nowStr = DateTime.now().toIso8601String();
      currentList[idx] = {
        ...old,
        'status': newStatus,
        'updated_at': nowStr,
        if (newStatus == 'cancelled') ...{
          'cancelled_at': nowStr,
          'cancel_reason': reason ?? old['cancel_reason'],
          'status_message': reason ?? old['status_message'],
        },
        if (newStatus == 'packed') ...{
          'packed_at': nowStr,
        },
        ...?extraData,
      };
      state = state.copyWith(orders: currentList);
    }

    final success = await _repo.updateOrderStatus(
      orderId,
      newStatus,
      reason: reason,
      extraData: extraData,
    );
    if (!success) {
      // Revert or reload if failed
      fetchAll();
    }
    return success;
  }

  Future<bool> updateWeight({
    required dynamic orderId,
    required double confirmedWeight,
    required double finalPrice,
    double? originalWeight,
    String? weightProofUrl,
  }) async {
    final success = await _repo.updateOrderWeight(
      orderId: orderId,
      confirmedWeight: confirmedWeight,
      finalPrice: finalPrice,
      originalWeight: originalWeight,
      weightProofUrl: weightProofUrl,
    );
    if (success) {
      final isWeightChanged = originalWeight != null && (confirmedWeight - originalWeight).abs() > 0.02;
      final currentList = List<Map<String, dynamic>>.from(state.orders);
      final idx = currentList.indexWhere((o) => o['id'] == orderId);
      if (idx != -1) {
        currentList[idx] = {
          ...currentList[idx],
          'confirmed_weight_kg': confirmedWeight,
          'total_price': finalPrice,
          'is_weight_adjusted': isWeightChanged,
          'proposed_total_price': finalPrice,
          'weight_update_status': isWeightChanged ? 'pending_approval' : 'approved',
          'status': 'weight_confirmed',
        };
        if (weightProofUrl != null) {
          currentList[idx]['weight_proof_url'] = weightProofUrl;
        }
        state = state.copyWith(orders: currentList);
      }
    }
    return success;
  }

  Future<bool> assignPartner(dynamic orderId, int partnerId) async {
    final success = await _repo.assignDeliveryPartner(orderId, partnerId);
    if (success) {
      final partner = state.deliveryPartners.firstWhere(
        (p) => p['id'] == partnerId,
        orElse: () => {},
      );
      final currentList = List<Map<String, dynamic>>.from(state.orders);
      final idx = currentList.indexWhere((o) => o['id'] == orderId);
      if (idx != -1) {
        currentList[idx] = {
          ...currentList[idx],
          'delivery_partner_id': partnerId,
          if (partner.isNotEmpty) ...{
            'delivery_partner_name': partner['name'],
            'delivery_partner_phone': partner['phone'],
            'delivery_partner_vehicle': partner['vehicle_number'],
          }
        };
        state = state.copyWith(orders: currentList);
      }
    }
    return success;
  }
}

final ordersNotifierProvider = NotifierProvider<OrdersNotifier, OrdersState>(OrdersNotifier.new);

/// Memoized provider for orders matching the selected stage and search query
final filteredOrdersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final state = ref.watch(ordersNotifierProvider);
  final allOrders = state.orders;
  final stage = state.selectedStage;
  final query = state.searchQuery;

  return allOrders.where((order) {
    final rawStatus = (order['status'] as String? ?? 'new_order');
    final orderStage = OrderStatusPipelineExt.fromCode(rawStatus);
    
    // Status Stage Match
    if (stage == OrderStatusPipeline.inventoryUpdate || stage == OrderStatusPipeline.marketUpdated) {
      return false;
    }

    if (orderStage != stage) {
      return false;
    }

    // Search Query Filter
    if (query.isNotEmpty) {
      final refStr = (order['order_ref'] ?? '').toString().toLowerCase();
      final nameStr = (order['customer_name'] ?? '').toString().toLowerCase();
      final phoneStr = (order['customer_phone'] ?? order['phone'] ?? '').toString().toLowerCase();
      final idStr = (order['id'] ?? '').toString().toLowerCase();

      return refStr.contains(query) ||
          nameStr.contains(query) ||
          phoneStr.contains(query) ||
          idStr.contains(query);
    }

    return true;
  }).toList();
});

/// Memoized provider for counts per stage
final orderStageCountsProvider = Provider<Map<OrderStatusPipeline, int>>((ref) {
  final orders = ref.watch(ordersNotifierProvider.select((s) => s.orders));
  final counts = <OrderStatusPipeline, int>{
    for (var s in OrderStatusPipeline.values) s: 0,
  };

  for (var order in orders) {
    final rawStatus = (order['status'] as String? ?? 'new_order');
    final stage = OrderStatusPipelineExt.fromCode(rawStatus);
    counts[stage] = (counts[stage] ?? 0) + 1;
  }

  return counts;
});
