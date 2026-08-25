import 'package:flutter/material.dart';

enum OrderStatusPipeline {
  inventoryUpdate, // 1. INVENTORY UPDATE
  marketUpdated,   // 2. MARKET UPDATED
  newOrder,        // 3. NEW ORDER
  weightConfirmed, // 4. WEIGHT CONFIRMED
  cleaning,        // 5. CLEANING / CUTTING
  packed,          // 6. PACKED
  handedOver,      // 7. HANDED OVER / DISPATCH
  completed,       // 8. COMPLETED
  cancelled,       // 9. CANCELLED
}

extension OrderStatusPipelineExt on OrderStatusPipeline {
  String get code {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return 'inventory_update';
      case OrderStatusPipeline.marketUpdated:
        return 'market_updated';
      case OrderStatusPipeline.newOrder:
        return 'new_order';
      case OrderStatusPipeline.weightConfirmed:
        return 'weight_confirmed';
      case OrderStatusPipeline.cleaning:
        return 'cleaning';
      case OrderStatusPipeline.packed:
        return 'packed';
      case OrderStatusPipeline.handedOver:
        return 'out_for_delivery';
      case OrderStatusPipeline.completed:
        return 'delivered';
      case OrderStatusPipeline.cancelled:
        return 'cancelled';
    }
  }

  String get labelEnglish {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return '1. INVENTORY UPDATE';
      case OrderStatusPipeline.marketUpdated:
        return '2. MARKET UPDATED';
      case OrderStatusPipeline.newOrder:
        return '3. NEW ORDER';
      case OrderStatusPipeline.weightConfirmed:
        return '4. WEIGHT CONFIRMED';
      case OrderStatusPipeline.cleaning:
        return '5. CLEANING';
      case OrderStatusPipeline.packed:
        return '6. PACKED';
      case OrderStatusPipeline.handedOver:
        return '7. HANDED OVER';
      case OrderStatusPipeline.completed:
        return '8. COMPLETED';
      case OrderStatusPipeline.cancelled:
        return '9. CANCELLED';
    }
  }

  String get labelTamil {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return '1. Inventory Update';
      case OrderStatusPipeline.marketUpdated:
        return '2. Market Updated';
      case OrderStatusPipeline.newOrder:
        return '3. New Order Received';
      case OrderStatusPipeline.weightConfirmed:
        return '4. Net Weight Confirmed';
      case OrderStatusPipeline.cleaning:
        return '5. Cleaning / Cutting';
      case OrderStatusPipeline.packed:
        return '6. Packed';
      case OrderStatusPipeline.handedOver:
        return '7. Handed to Delivery';
      case OrderStatusPipeline.completed:
        return '8. Delivered';
      case OrderStatusPipeline.cancelled:
        return '9. Cancelled';
    }
  }

  IconData get icon {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return Icons.edit_note_rounded;
      case OrderStatusPipeline.marketUpdated:
        return Icons.storefront_rounded;
      case OrderStatusPipeline.newOrder:
        return Icons.shopping_bag_rounded;
      case OrderStatusPipeline.weightConfirmed:
        return Icons.scale_rounded;
      case OrderStatusPipeline.cleaning:
        return Icons.content_cut_rounded;
      case OrderStatusPipeline.packed:
        return Icons.inventory_2_rounded;
      case OrderStatusPipeline.handedOver:
        return Icons.delivery_dining_rounded;
      case OrderStatusPipeline.completed:
        return Icons.task_alt_rounded;
      case OrderStatusPipeline.cancelled:
        return Icons.cancel_rounded;
    }
  }

  Color get color {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return const Color(0xFF4F46E5); // Indigo Bold
      case OrderStatusPipeline.marketUpdated:
        return const Color(0xFF6366F1); // Indigo
      case OrderStatusPipeline.newOrder:
        return const Color(0xFF3B82F6); // Blue
      case OrderStatusPipeline.weightConfirmed:
        return const Color(0xFF10B981); // Emerald
      case OrderStatusPipeline.cleaning:
        return const Color(0xFFF59E0B); // Amber
      case OrderStatusPipeline.packed:
        return const Color(0xFF14B8A6); // Teal
      case OrderStatusPipeline.handedOver:
        return const Color(0xFFEC4899); // Pink
      case OrderStatusPipeline.completed:
        return const Color(0xFF22C55E); // Green
      case OrderStatusPipeline.cancelled:
        return const Color(0xFFEF4444); // Red
    }
  }

  OrderStatusPipeline? get nextStage {
    switch (this) {
      case OrderStatusPipeline.inventoryUpdate:
        return OrderStatusPipeline.marketUpdated;
      case OrderStatusPipeline.marketUpdated:
        return OrderStatusPipeline.newOrder;
      case OrderStatusPipeline.newOrder:
        return OrderStatusPipeline.weightConfirmed;
      case OrderStatusPipeline.weightConfirmed:
        return OrderStatusPipeline.cleaning;
      case OrderStatusPipeline.cleaning:
        return OrderStatusPipeline.packed;
      case OrderStatusPipeline.packed:
        return OrderStatusPipeline.handedOver;
      case OrderStatusPipeline.handedOver:
      case OrderStatusPipeline.completed:
      case OrderStatusPipeline.cancelled:
        return null;
    }
  }

  static OrderStatusPipeline fromCode(String rawCode) {
    final clean = rawCode.toLowerCase().trim();
    if (clean == 'inventory_update') return OrderStatusPipeline.inventoryUpdate;
    if (clean == 'market_updated') return OrderStatusPipeline.marketUpdated;
    if (clean == 'new_order' || clean == 'received' || clean == 'pending' || clean == 'placed' || clean == 'order_placed' || clean == 'created' || clean == 'new') return OrderStatusPipeline.newOrder;
    if (clean == 'weight_confirmed' || clean == 'weight_updated' || clean == 'weighted' || clean == 'weighed' || clean == 'sourced') return OrderStatusPipeline.weightConfirmed;
    if (clean == 'cleaning' || clean == 'cutting') return OrderStatusPipeline.cleaning;
    if (clean == 'packed' || clean == 'packing' || clean == 'verified') return OrderStatusPipeline.packed;
    if (clean == 'handed_over' || clean == 'out_for_delivery' || clean == 'dispatched' || clean == 'on_the_way' || clean == 'assigned') return OrderStatusPipeline.handedOver;
    if (clean == 'completed' || clean == 'delivered' || clean == 'success' || clean == 'done') return OrderStatusPipeline.completed;
    if (clean == 'cancelled' || clean == 'canceled' || clean == 'rejected' || clean == 'declined' || clean == 'void') return OrderStatusPipeline.cancelled;

    return OrderStatusPipeline.values.firstWhere(
      (e) => e.code == clean || e.labelEnglish.toLowerCase() == clean.replaceAll('_', ' '),
      orElse: () => OrderStatusPipeline.newOrder,
    );
  }
}
