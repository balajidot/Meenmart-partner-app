import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/widgets/optimized_image.dart';
import '../../core/theme/app_theme.dart';

class PartnerDrawer extends ConsumerWidget {
  const PartnerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final profile = authState.staffProfile;
    final roles = List<String>.from(profile?['roles'] ?? []);

    final userName = profile?['name'] ?? 'Store Manager';
    final userPhone = profile?['phone'] ?? '9876543210';
    final avatarUrl = profile?['avatar_url'] as String?;
    final rawId = profile?['id']?.toString() ?? '102';
    final staffId = rawId.length > 8 ? 'EMP-${rawId.substring(0, 6).toUpperCase()}' : 'EMP-${rawId.padLeft(4, '0')}';

    String primaryRoleLabel = 'STORE MANAGER';
    Color roleColor = AppColors.primary;

    if (roles.contains('delivery_partner')) {
      primaryRoleLabel = 'DELIVERY PARTNER';
      roleColor = AppColors.deliveryBlue;
    } else if (roles.contains('marketing_executive')) {
      primaryRoleLabel = 'MARKETING HUB';
      roleColor = AppColors.partnerGold;
    }

    String currentRoute = '';
    try {
      currentRoute = GoRouterState.of(context).matchedLocation;
    } catch (_) {}

    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. CLEAN EXECUTIVE USER PROFILE CARD (ZERO OVERFLOW)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    AppHaptics.selectionClick();
                    Navigator.pop(context);
                    Future.microtask(() {
                      if (context.mounted) {
                        try {
                          context.go('/account');
                        } catch (_) {}
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Avatar with Status Ring
                        Stack(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFF1F5F9),
                                border: Border.all(color: roleColor, width: 2.2),
                              ),
                              child: ClipOval(
                                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? OptimizedImage(
                                        imageUrl: avatarUrl,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 140,
                                        memCacheHeight: 140,
                                      )
                                    : const Icon(Icons.person_rounded, size: 28, color: Color(0xFF64748B)),
                              ),
                            ),
                            Positioned(
                              right: 1,
                              bottom: 1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),

                        // Name, Phone & Badges (Wrap protects against overflow)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userPhone,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 5,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  AppBadges.capsule(
                                    label: primaryRoleLabel,
                                    bgColor: const Color(0xFFF5F3FF),
                                    borderColor: const Color(0xFFDDD6FE),
                                    textColor: const Color(0xFF6D28D9),
                                    fontSize: 9,
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  ),
                                  AppBadges.capsule(
                                    label: staffId,
                                    bgColor: const Color(0xFFF8FAFC),
                                    borderColor: const Color(0xFFE2E8F0),
                                    textColor: const Color(0xFF475569),
                                    fontSize: 9,
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // 2. DYNAMIC ROLE-AWARE NAVIGATION LIST
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                children: [
                  // SECTION: OPERATIONS
                  _buildSectionHeader('OPERATIONS'),
                  const SizedBox(height: 6),

                  // Store Manager & Admin Operations
                  if (roles.contains('admin') || roles.contains('store_manager')) ...[
                    _buildNavItem(
                      context: context,
                      icon: Icons.inventory_2_rounded,
                      title: 'Live Orders',
                      route: '/store-dashboard',
                      isSelected: currentRoute == '/store-dashboard' || currentRoute.isEmpty || currentRoute == '/',
                      color: const Color(0xFF059669),
                    ),
                    const SizedBox(height: 6),
                    _buildNavItem(
                      context: context,
                      icon: Icons.set_meal_rounded,
                      title: 'Stock & Availability',
                      route: '/stock-update',
                      isSelected: currentRoute == '/stock-update',
                      color: const Color(0xFF0D9488),
                    ),
                    const SizedBox(height: 6),
                    _buildNavItem(
                      context: context,
                      icon: Icons.bar_chart_rounded,
                      title: 'Analytics',
                      route: '/analytics',
                      isSelected: currentRoute == '/analytics',
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(height: 6),
                    _buildNavItem(
                      context: context,
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Cashflow & Ledger',
                      route: '/cashflow',
                      isSelected: currentRoute == '/cashflow' || currentRoute == '/expenses',
                      color: const Color(0xFF059669),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Delivery Hub (For Delivery Heroes, Multi-role, and Admins)
                  if (roles.contains('delivery_partner') || roles.contains('admin')) ...[
                    _buildNavItem(
                      context: context,
                      icon: Icons.delivery_dining_rounded,
                      title: 'Delivery Hub',
                      route: '/delivery-dashboard',
                      isSelected: currentRoute == '/delivery-dashboard',
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Marketing Hub (For Marketing Executives and Admins)
                  if (roles.contains('marketing_executive') || roles.contains('marketing') || roles.contains('admin')) ...[
                    _buildNavItem(
                      context: context,
                      icon: Icons.campaign_rounded,
                      title: 'Marketing Hub',
                      route: '/marketing-dashboard',
                      isSelected: currentRoute == '/marketing-dashboard',
                      color: const Color(0xFFD97706),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Common to all roles: Attendance & Shifts
                  _buildNavItem(
                    context: context,
                    icon: Icons.fingerprint_rounded,
                    title: 'Attendance & Shifts',
                    route: '/check-in',
                    isSelected: currentRoute == '/check-in',
                    color: const Color(0xFF0D9488),
                  ),
                  const SizedBox(height: 18),

                  // SECTION: ACCOUNT & SYSTEM
                  _buildSectionHeader('ACCOUNT'),
                  const SizedBox(height: 6),
                  _buildNavItem(
                    context: context,
                    icon: Icons.person_outline_rounded,
                    title: 'My Profile',
                    route: '/account',
                    isSelected: currentRoute == '/account',
                    color: const Color(0xFF4F46E5),
                  ),
                  const SizedBox(height: 6),
                  _buildNavItem(
                    context: context,
                    icon: Icons.support_agent_rounded,
                    title: 'Store Support',
                    route: '/support',
                    isSelected: currentRoute == '/support' || currentRoute == '/support-chat',
                    color: const Color(0xFF059669),
                  ),
                  const SizedBox(height: 6),
                  _buildNavItem(
                    context: context,
                    icon: Icons.system_update_rounded,
                    title: 'Check for Updates',
                    route: '',
                    isSelected: false,
                    color: const Color(0xFF059669),
                    onCustomTap: () => AppUpdateService().checkAndPrompt(context, isManual: true),
                  ),
                ],
              ),
            ),

            // 3. CLEAN LOGOUT FOOTER
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.2)),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        AppHaptics.mediumImpact();
                        await ref.read(authNotifierProvider.notifier).signOut();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'LOGOUT',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFDC2626),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'MeenMart Partner v2.0',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 2),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String route,
    required bool isSelected,
    required Color color,
    VoidCallback? onCustomTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selectionClick();
          Navigator.pop(context);
          if (onCustomTap != null) {
            Future.microtask(onCustomTap);
          } else if (!isSelected) {
            Future.microtask(() {
              if (context.mounted) {
                try {
                  context.go(route);
                } catch (_) {}
              }
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.09) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: color.withValues(alpha: 0.25)) : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? color : const Color(0xFF0F172A),
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
