import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryRepository {
  static final InventoryRepository _instance = InventoryRepository._internal();
  factory InventoryRepository() => _instance;
  InventoryRepository._internal();

  SupabaseClient get _db => Supabase.instance.client;

  List<String> _cachedCategories = [];
  List<Map<String, dynamic>> _cachedInventory = [];

  List<String> get cachedCategories => _cachedCategories;
  List<Map<String, dynamic>> get cachedInventory => _cachedInventory;

  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCategories.isNotEmpty) {
      return _cachedCategories;
    }
    try {
      final rows = await _db
          .from('categories')
          .select('name, is_active')
          .order('id', ascending: true);

      final active = List<Map<String, dynamic>>.from(rows)
          .where((c) => c['is_active'] != false)
          .map((c) => (c['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toList();

      final categorySet = {'All', ...active};
      _cachedCategories = categorySet.toList();
      return _cachedCategories;
    } catch (e) {
      debugPrint('Categories fetch error: $e');
      if (_cachedCategories.isEmpty) {
        _cachedCategories = ['All', 'Fish', 'Prawns', 'Crab', 'Squid', 'Lobster', 'Dry Fish'];
      }
      return _cachedCategories;
    }
  }

  Future<List<Map<String, dynamic>>> fetchInventory({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedInventory.isNotEmpty) {
      return _cachedInventory;
    }
    try {
      final rows = await _db
          .from('fish_items')
          .select('id, name, tamil_name, category, price_per_kg, stock_kg, available, image_url, min_order_kg, badge, has_cleaning, cleaning_charge, allowed_cutting_types, display_order')
          .eq('is_deleted', false)
          .order('display_order', ascending: true);

      _cachedInventory = List<Map<String, dynamic>>.from(rows);
      return _cachedInventory;
    } catch (e) {
      debugPrint('Inventory fetch error: $e');
      return _cachedInventory;
    }
  }

  Future<bool> updateItemStockOrPrice({
    required int itemId,
    double? stockKg,
    double? pricePerKg,
    bool? isAvailable,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (stockKg != null) updateData['stock_kg'] = stockKg;
      if (pricePerKg != null) updateData['price_per_kg'] = pricePerKg;
      // FIX: DB column is 'available', not 'is_available'
      if (isAvailable != null) updateData['available'] = isAvailable;

      if (updateData.isEmpty) return true; // Nothing to update

      await _db.from('fish_items').update(updateData).eq('id', itemId);

      // Mutate local cache — sync both 'available' and legacy 'is_available' keys
      final idx = _cachedInventory.indexWhere((it) => it['id'] == itemId);
      if (idx != -1) {
        _cachedInventory[idx] = {
          ..._cachedInventory[idx],
          ...updateData,
        };
      }
      return true;
    } catch (e) {
      debugPrint('Update fish item error: $e');
      return false;
    }
  }
}
