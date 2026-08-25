import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

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
    final profile = await AuthService().getCurrentStaffProfile();
    if (user != null && profile == null) {
      // A valid Supabase account alone is not permission to use this staff app.
      await AuthService().signOut();
      state = AuthState(user: null, staffProfile: null, isLoading: false);
      return;
    }
    state = AuthState(user: user, staffProfile: profile, isLoading: false);
    if (user != null && profile != null) {
      unawaited(NotificationService().syncCurrentToken());
    }
  }

  Future<void> signOut() async {
    await AuthService().signOut();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
