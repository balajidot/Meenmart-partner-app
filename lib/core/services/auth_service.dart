import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _supabase = Supabase.instance.client;

  // Roles
  static const String roleManager = 'store_manager';
  static const String roleDelivery = 'delivery_partner';
  static const String roleMarketing = 'marketing_executive';

  // Get current user ID
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // Get staff details
  Future<Map<String, dynamic>?> getCurrentStaffProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      // 1. Try by auth_id
      var data = await _supabase
          .from('store_staff')
          .select()
          .eq('auth_id', user.id)
          .maybeSingle();

      // A staff record and its role must be provisioned by an administrator.
      // Never infer authorization from an email address or link records by phone:
      // both behaviours could grant an authenticated user unintended access.
      if (data == null || data['status']?.toString().toLowerCase() != 'active') {
        return null;
      }

      final rawRoles = data['roles'];
      var rolesList = <String>[];
      if (rawRoles is List) {
        rolesList = rawRoles.map((e) => e.toString()).toList();
      } else if (rawRoles is String && rawRoles.isNotEmpty) {
        rolesList = [rawRoles];
      } else if (data['role'] != null && data['role'].toString().isNotEmpty) {
        rolesList = [data['role'].toString()];
      }

      if (rolesList.isEmpty) return null;
      data['roles'] = rolesList;
      return data;
    } catch (e) {
      debugPrint('Error fetching staff profile: $e');
      return null;
    }
  }

  // Check role
  bool hasRole(Map<String, dynamic> staffData, String role) {
    if (staffData['roles'] == null) return false;
    final roles = List<String>.from(staffData['roles']);
    return roles.contains(role);
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
  }
}
