import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/config/env_config.dart';
import 'core/services/notification_service.dart';
import 'features/orders/order_pipeline_screen.dart';
import 'features/delivery/delivery_home_screen.dart';
import 'features/marketing/marketing_home_screen.dart';
import 'features/checkin/check_in_screen.dart';
import 'features/profile/account_screen.dart';
import 'features/profile/profile_setup_screen.dart';
import 'features/profile/meenmart_onboarding_screen.dart';
import 'features/profile/first_time_welcome_screen.dart';
import 'features/analytics/performance_analytics_screen.dart';
import 'features/cashflow/cashflow_screen.dart';
import 'features/stock/stock_update_screen.dart';
import 'features/auth/partner_login_screen.dart';
import 'features/support/store_support_chat_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global Flutter framework error override
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };

    // Custom ErrorWidget.builder for widget rendering failures (renders safely within element tree)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _buildErrorCard(details.exceptionAsString(), details.stack.toString());
    };

    // Load environment configurations from .env
    await EnvConfig.initialize();

    final supabaseUrl = EnvConfig.supabaseUrl;
    final supabaseAnonKey = EnvConfig.supabaseAnonKey;

    var backendReady = false;
    try {
      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(
          url: supabaseUrl,
          publishableKey: supabaseAnonKey,
        );
        backendReady = true;
      } else {
        debugPrint('⚠️ Supabase credentials missing in .env or environment');
      }
    } catch (e) {
      debugPrint('Supabase initialize notice: $e');
    }

    // Run the app immediately so the UI renders without blocking
    runApp(ProviderScope(child: MeenMartStoreApp(isBackendReady: backendReady)));

    // Initialize Firebase Cloud Messaging & Local Notifications in background
    if (backendReady) {
      unawaited(NotificationService().init().catchError((e) {
        debugPrint('NotificationService init notice: $e');
      }));
    }
  }, (error, stack) {
    debugPrint('GLOBAL ASYNC ERROR CAUGHT: $error\n$stack');
  });
}

Widget _buildErrorCard(String errorMsg, String stackTrace) {
  return Material(
    color: const Color(0xFFFEF2F2),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bug_report_rounded, color: AppColors.danger, size: 56),
            const SizedBox(height: 12),
            Text(
              'CRASH DIAGNOSTIC DETECTED',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navyBlue, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Exact Error Root Cause:',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      errorMsg,
                      style: GoogleFonts.firaCode(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.danger),
                    ),
                    if (stackTrace.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        stackTrace,
                        style: GoogleFonts.firaCode(fontSize: 9.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                runApp(const ProviderScope(child: MeenMartStoreApp(isBackendReady: true)));
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('RESTART APP', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    ),
  );
}

class AppRouterNotifier extends ChangeNotifier {
  final Ref _ref;
  AppRouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authNotifierProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  return AppRouterNotifier(ref);
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final routerNotifier = ref.watch(appRouterNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: routerNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final isLoggingIn = state.matchedLocation == '/login';
      final isLoading = authState.isLoading;

      if (isLoading) return null;

      final user = authState.user;
      if (user == null) {
        return isLoggingIn ? null : '/login';
      }

      final roles = (authState.staffProfile?['roles'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      final home = _dashboardForRoles(roles);
      if (home == null) return '/login';
      if (isLoggingIn) return home;

      if (!_isRouteAllowedForRoles(state.matchedLocation, roles)) return home;

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const PartnerLoginScreen(),
      ),
      GoRoute(
        path: '/store-dashboard',
        builder: (context, state) => const OrderPipelineScreen(),
      ),
      GoRoute(
        path: '/delivery-dashboard',
        builder: (context, state) => const DeliveryHomeScreen(),
      ),
      GoRoute(
        path: '/marketing-dashboard',
        builder: (context, state) => const MarketingHomeScreen(),
      ),
      GoRoute(
        path: '/check-in',
        builder: (context, state) => const CheckInScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (context, state) => const PerformanceAnalyticsScreen(),
      ),
      GoRoute(
        path: '/cashflow',
        builder: (context, state) => const CashflowScreen(),
      ),
      GoRoute(
        path: '/expenses',
        redirect: (context, state) => '/cashflow',
      ),
      GoRoute(
        path: '/stock-update',
        builder: (context, state) => const StockUpdateScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const MeenMartOnboardingScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const FirstTimeWelcomeScreen(),
      ),
      GoRoute(
        path: '/support-chat',
        builder: (context, state) => const StoreSupportChatScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const StoreSupportChatScreen(),
      ),
    ],
  );
});

String? _dashboardForRoles(Set<String> roles) {
  if (roles.contains('admin') || roles.contains('store_manager')) return '/store-dashboard';
  if (roles.contains('delivery_partner')) return '/delivery-dashboard';
  if (roles.contains('marketing_executive') || roles.contains('marketing')) return '/marketing-dashboard';
  return null;
}

bool _isRouteAllowedForRoles(String route, Set<String> roles) {
  // Admins have universal access across all operational screens
  if (roles.contains('admin')) {
    return true;
  }

  // Common screens available to all authenticated partners
  const commonRoutes = {
    '/check-in',
    '/account',
    '/profile-setup',
    '/support',
    '/support-chat',
    '/onboarding',
    '/welcome',
  };
  if (commonRoutes.contains(route)) return true;

  // Store Manager routes
  if (roles.contains('store_manager')) {
    const storeRoutes = {
      '/store-dashboard',
      '/analytics',
      '/cashflow',
      '/expenses',
      '/stock-update',
      '/delivery-dashboard',
      '/marketing-dashboard',
    };
    if (storeRoutes.contains(route)) return true;
  }

  // Delivery Partner routes
  if (roles.contains('delivery_partner')) {
    if (route == '/delivery-dashboard') return true;
  }

  // Marketing Executive routes
  if (roles.contains('marketing_executive') || roles.contains('marketing')) {
    if (route == '/marketing-dashboard') return true;
  }

  return false;
}

class MeenMartStoreApp extends ConsumerWidget {
  const MeenMartStoreApp({super.key, required this.isBackendReady});

  final bool isBackendReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isBackendReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const _ConfigurationErrorScreen(),
      );
    }
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'MeenMart Partner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}

class _ConfigurationErrorScreen extends StatelessWidget {
  const _ConfigurationErrorScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text('Configuration required', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('This app cannot connect securely. Ask your administrator to configure Supabase and restart the app.', textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
}
