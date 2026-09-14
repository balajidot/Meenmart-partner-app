import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderRepository {
  static final OrderRepository _instance = OrderRepository._internal();
  factory OrderRepository() => _instance;
  OrderRepository._internal();

  SupabaseClient get _db => Supabase.instance.client;

  // Cached delivery partners list to avoid repeating fetches
  List<Map<String, dynamic>> _cachedDeliveryPartners = [];

  List<Map<String, dynamic>> get cachedDeliveryPartners => _cachedDeliveryPartners;

  /// Drops cached rows so a new session never sees the previous user's data.
  void clearCache() => _cachedDeliveryPartners = [];

  Future<List<Map<String, dynamic>>> fetchDeliveryPartners({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedDeliveryPartners.isNotEmpty) {
      return _cachedDeliveryPartners;
    }
    List<Map<String, dynamic>> results = [];
    try {
      final rows = await _db
          .from('delivery_partners')
          .select('*')
          .order('id', ascending: true);
      if (rows.isNotEmpty) {
        results = List<Map<String, dynamic>>.from(rows);
      }
    } catch (e) {
      debugPrint('Delivery partners fetch warning: $e');
    }

    // `delivery_partners` is the only source of truth here: the id is passed
    // straight to assign_and_dispatch_order, which looks it up in that table.
    // Deriving ids from store_staff would dispatch to the wrong partner.
    // An empty list lets the UI show its "No delivery partners found" state.

    _cachedDeliveryPartners = results;
    return _cachedDeliveryPartners;
  }

  /// Fetches orders with single optimized join and server-side limit
  Future<List<Map<String, dynamic>>> fetchLiveOrders({int limit = 80}) async {
    List<Map<String, dynamic>> items = [];
    try {
      final rows = await _db
          .from('orders')
          .select('*, order_items(*, fish_items(*))')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 5));
      items = List<Map<String, dynamic>>.from(rows);
    } catch (err) {
      debugPrint('Direct join query notice, executing bounded fallback fetch: $err');
      try {
        final orderRows = await _db
            .from('orders')
            .select('*')
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(const Duration(seconds: 4));
        items = List<Map<String, dynamic>>.from(orderRows);

        if (items.isNotEmpty) {
          final orderIds = items.map((o) => o['id']).where((id) => id != null).toList();
          
          // Bounded batch fetch for order_items
          final orderItemRows = await _db
              .from('order_items')
              .select('*')
              .inFilter('order_id', orderIds);

          final fishIds = orderItemRows
              .map((it) => it['fish_id'])
              .where((fid) => fid != null)
              .toSet()
              .toList();

          final fishItemRows = fishIds.isNotEmpty
              ? await _db.from('fish_items').select('*').inFilter('id', fishIds)
              : <dynamic>[];

          final fishMap = {for (var f in fishItemRows) f['id']: f};
          final itemsByOrder = <dynamic, List<Map<String, dynamic>>>{};

          for (var item in orderItemRows) {
            final orderId = item['order_id'];
            final fishId = item['fish_id'];
            item['fish_items'] = fishMap[fishId] ?? {};
            itemsByOrder.putIfAbsent(orderId, () => []).add(Map<String, dynamic>.from(item));
          }

          for (var order in items) {
            order['order_items'] = itemsByOrder[order['id']] ?? [];
          }
        }
      } catch (fallbackErr) {
        debugPrint('Fallback order items fetch error: $fallbackErr');
      }
    }

    // Attach delivery partner info from cache or memory map
    if (_cachedDeliveryPartners.isEmpty) {
      await fetchDeliveryPartners();
    }
    final partnerMap = {for (var p in _cachedDeliveryPartners) p['id']: p};
    for (var order in items) {
      final partnerId = order['delivery_partner_id'];
      if (partnerId != null && partnerMap.containsKey(partnerId)) {
        final pData = partnerMap[partnerId];
        if (pData != null) {
          order['delivery_partner_name'] = pData['name'];
          order['delivery_partner_phone'] = pData['phone'];
          order['delivery_partner_vehicle'] = pData['vehicle_number'];
        }
      }
    }

    return items;
  }

  /// Single order fetch for incremental realtime updates
  Future<Map<String, dynamic>?> fetchSingleOrder(dynamic orderId) async {
    try {
      final rows = await _db
          .from('orders')
          .select('*, order_items(*, fish_items(*))')
          .eq('id', orderId)
          .limit(1);

      if (rows.isNotEmpty) {
        final order = Map<String, dynamic>.from(rows.first);
        final partnerId = order['delivery_partner_id'];
        if (partnerId != null) {
          if (_cachedDeliveryPartners.isEmpty) {
            await fetchDeliveryPartners();
          }
          final partnerMap = {for (var p in _cachedDeliveryPartners) p['id']: p};
          final pData = partnerMap[partnerId];
          if (pData != null) {
            order['delivery_partner_name'] = pData['name'];
            order['delivery_partner_phone'] = pData['phone'];
            order['delivery_partner_vehicle'] = pData['vehicle_number'];
          }
        }
        return order;
      }
    } catch (e) {
      debugPrint('Single order fetch warning: $e');
    }
    return null;
  }

  /// Updates order status with timestamp and contextual message
  Future<bool> updateOrderStatus(
    dynamic orderId,
    String newStatusCode, {
    String? reason,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      await _db.rpc('advance_store_order', params: {
        'p_order_id': orderId,
        'p_new_status': newStatusCode,
        'p_reason': reason,
        'p_packed_photo_url': extraData?['packed_photo_url'],
      });
      return true;
    } catch (e) {
      debugPrint('advance_store_order RPC failed: $e');
      return false;
    }
  }

  /// Updates confirmed net weight & recalculates totals with customer approval tracking
  Future<bool> updateOrderWeight({
    required dynamic orderId,
    required double confirmedWeight,
    required double finalPrice,
    double? originalWeight,
    String? weightProofUrl,
    List<Map<String, dynamic>>? itemUpdates,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final isWeightChanged = originalWeight != null && (confirmedWeight - originalWeight).abs() > 0.02;

      List<Map<String, dynamic>> proposalItems = [];
      if (itemUpdates != null && itemUpdates.isNotEmpty) {
        proposalItems = itemUpdates.map((u) {
          final oldQty = (u['old_quantity_kg'] as num? ?? u['quantity_kg'] as num?)?.toDouble() ?? 1.0;
          final newQty = (u['confirmed_quantity_kg'] as num? ?? u['proposed_quantity_kg'] as num? ?? oldQty).toDouble();
          final rawItemId = u['order_item_id'] ?? u['id'];
          final orderItemId = rawItemId is int ? rawItemId : (int.tryParse(rawItemId.toString()) ?? 0);
          return {
            'order_item_id': orderItemId,
            'name': u['name'] ?? 'Fish Item',
            'old_quantity_kg': oldQty,
            'proposed_quantity_kg': newQty,
            'old_with_cleaning': u['with_cleaning'] == true,
            'proposed_with_cleaning': u['with_cleaning'] == true,
            'old_cutting_type': (u['cutting_type'] ?? 'None').toString(),
            'proposed_cutting_type': (u['cutting_type'] ?? 'None').toString(),
            'price_per_kg': (u['price_per_kg'] as num?)?.toDouble() ?? 0.0,
            'cleaning_fee': (u['cleaning_fee'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
      } else if (isWeightChanged) {
        try {
          final items = await _db
              .from('order_items')
              .select('id, quantity_kg, price_per_kg, with_cleaning, cleaning_fee, cutting_type, fish_items(name)')
              .eq('order_id', orderId);
          final originalTotalWeight = items.fold<double>(
            0,
            (sum, item) => sum + ((item['quantity_kg'] as num?)?.toDouble() ?? 0),
          );
          if (originalTotalWeight > 0) {
            for (final item in items) {
              final fish = item['fish_items'] as Map<String, dynamic>?;
              final fishName = fish?['name'] ?? 'Fish Item';
              final oldQty = (item['quantity_kg'] as num? ?? originalWeight).toDouble();
              final pricePerKg = (item['price_per_kg'] as num? ?? (finalPrice / (confirmedWeight > 0 ? confirmedWeight : 1.0))).toDouble();
              final withCleaning = item['with_cleaning'] == true;
              final cleaningFee = (item['cleaning_fee'] as num? ?? 0.0).toDouble();
              final cutType = (item['cutting_type'] ?? 'None').toString();

              proposalItems.add({
                'order_item_id': item['id'],
                'name': fishName,
                'old_quantity_kg': oldQty,
                'proposed_quantity_kg': confirmedWeight * oldQty / originalTotalWeight,
                'old_with_cleaning': withCleaning,
                'proposed_with_cleaning': withCleaning,
                'old_cutting_type': cutType,
                'proposed_cutting_type': cutType,
                'price_per_kg': pricePerKg,
                'cleaning_fee': cleaningFee,
              });
            }
          }
        } catch (fetchErr) {
          debugPrint('Failed to fetch order items for proposal: $fetchErr');
        }
      }

      final updatePayload = <String, dynamic>{
        'confirmed_weight_kg': confirmedWeight,
        'total_price': finalPrice,
        'is_weight_adjusted': isWeightChanged,
        'proposed_total_price': finalPrice,
        'weight_update_status': isWeightChanged ? 'pending_approval' : 'approved',
        'status': 'weight_confirmed',
        'status_message': isWeightChanged
            ? 'Weight updated to ${confirmedWeight.toStringAsFixed(2)}kg (₹${finalPrice.toStringAsFixed(0)}) — awaiting customer approval.'
            : 'Weight confirmed: ${confirmedWeight.toStringAsFixed(2)}kg.',
        'updated_at': now,
      };
      if (isWeightChanged && proposalItems.isNotEmpty) {
        updatePayload['pending_item_updates'] = proposalItems;
      }
      if (weightProofUrl != null && weightProofUrl.isNotEmpty) {
        updatePayload['weight_proof_url'] = weightProofUrl;
      }

      // Direct update to ensure columns are persisted immediately
      await _db.from('orders').update(updatePayload).eq('id', orderId);

      if (isWeightChanged && proposalItems.isNotEmpty) {
        try {
          await _db.rpc('propose_order_item_updates', params: {
            'p_order_id': orderId,
            'p_items': proposalItems.map((item) {
              final rawId = item['order_item_id'];
              final safeId = rawId is int ? rawId : (int.tryParse(rawId.toString()) ?? 0);
              return {
                'order_item_id': safeId,
                'new_quantity_kg': item['proposed_quantity_kg'],
                'new_with_cleaning': item['proposed_with_cleaning'],
                'new_cutting_type': item['proposed_cutting_type'],
              };
            }).toList(),
          });
        } catch (rpcErr) {
          debugPrint('propose_order_item_updates rpc notice: $rpcErr');
        }
      } else if (proposalItems.isNotEmpty) {
        for (final item in proposalItems) {
          final itemId = item['order_item_id'];
          final newQty = item['proposed_quantity_kg'];
          if (itemId != null && newQty != null) {
            try {
              await _db.from('order_items').update({'quantity_kg': newQty}).eq('id', itemId);
            } catch (itErr) {
              debugPrint('Direct order item quantity sync notice: $itErr');
            }
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('Order weight update error: $e');
      return false;
    }
  }

  /// Assigns delivery partner to order
  Future<bool> assignDeliveryPartner(dynamic orderId, int partnerId) async {
    try {
      await _db.rpc('assign_and_dispatch_order', params: {
        'p_order_id': orderId,
        'p_partner_id': partnerId,
      });
      return true;
    } catch (e) {
      debugPrint('Delivery partner assignment RPC failed: $e');
      return false;
    }
  }
}
