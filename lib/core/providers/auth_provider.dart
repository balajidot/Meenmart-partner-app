import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/inventory_repository.dart';
import '../services/order_repository.dart';
import '../services/notification_service.dart';
import '../services/delivery_tracking_service.dart';
import '../widgets/secure_staff_image.dart';

class AuthState {
  final User? user;
  final Map<String, dynamic>? staffProfile;
  final bool isLoading;

  AuthState({this.user, this.staffProfile, this.isLoading = true});

  AuthState copyWith({
    User? user,
    Map<String, dynamic>? staffProfile,
    bool? isLoading,
    bool clearProfile = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      staffProfile: clearProfile ? null : (staffProfile ?? this.staffProfile),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final session = Supabase.instance.client.auth.currentSession;

    final sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        await refreshProfile();
      } else if (event == AuthChangeEvent.signedOut) {
        // Stop live GPS so a signed-out phone never keeps broadcasting.
        unawaited(DeliveryTrackingService.instance.stopTracking());
        clearSecureStaffImageCache();
        OrderRepository().clearCache();
        InventoryRepository().clearCache();
        state = AuthState(user: null, staffProfile: null, isLoading: false);
      }
    });

    ref.onDispose(() {
      sub.cancel();
    });

    if (session != null) {
      Future.microtask(() => refreshProfile());
      return AuthState(user: session.user, isLoading: true);
    }

    return AuthState(isLoading: false);
  }

  Future<void> refreshProfile() async {
    state = state.copyWith(isLoading: true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      state = AuthState(user: null, staffProfile: null, isLoading: false);
      return;
    }

    var profile = await AuthService().getCurrentStaffProfile();
    // Brief retry in case of momentary connection latency
    if (profile == null) {
      await Future.delayed(const Duration(milliseconds: 600));
      profile = await AuthService().getCurrentStaffProfile();
    }

    if (profile == null) {
      // A valid Supabase account alone is not permission to use this staff app.
      await AuthService().signOut();
      state = AuthState(user: null, staffProfile: null, isLoading: false);
      return;
    }

    state = AuthState(user: user, staffProfile: profile, isLoading: false);
    unawaited(NotificationService().syncCurrentToken());
  }

  Future<void> signOut() async {
    // Mark the rider offline while the session is still valid (RLS needs it).
    await _setDeliveryOffline();
    await DeliveryTrackingService.instance.stopTracking();
    await AuthService().signOut();
  }

  Future<void> _setDeliveryOffline() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('delivery_partners')
          .update({'duty_status': 'offline', 'is_available': false})
          .eq('user_id', uid);
    } catch (_) {}
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
