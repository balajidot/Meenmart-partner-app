import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/widgets/optimized_image.dart';
import '../drawer/partner_drawer.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final profile = authState.staffProfile;
    final userName = profile?['name'] ?? 'Store Manager';
    final userPhone = profile?['phone'] ?? '9876543210';
    final branch = profile?['branch_location'] ?? 'Pulicat Central Store';
    final upiId = (profile?['upi_id'] as String?)?.isNotEmpty == true ? profile!['upi_id'] : 'Not Configured';
    final rawShift = profile?['shift_timing'] as String?;
    final shiftTiming = (rawShift != null && rawShift.isNotEmpty) ? rawShift : '07:00 AM - 05:00 PM (Morning Shift)';
    final avatarUrl = profile?['avatar_url'] as String?;
    final rawId = profile?['id']?.toString() ?? '102';
    final staffId = rawId.length > 8 ? 'EMP-${rawId.substring(0, 6).toUpperCase()}' : 'EMP-${rawId.padLeft(4, '0')}';

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            AppHaptics.selectionClick();
            if (context.canPop()) {
              context.pop();
            } else {
              final roles = (authState.staffProfile?['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
              final home = roles.contains('delivery_partner') && !roles.contains('store_manager') && !roles.contains('admin')
                  ? '/delivery-dashboard'
                  : (roles.contains('marketing_executive') || roles.contains('marketing')) && !roles.contains('store_manager') && !roles.contains('admin')
                      ? '/marketing-dashboard'
                      : '/store-dashboard';
              context.go(home);
            }
          },
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            tooltip: 'Edit Profile',
            onPressed: () {
              AppHaptics.selectionClick();
              context.push('/profile-setup');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TOP PROFILE HEADER CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFF059669), width: 2.5),
                        ),
                        child: ClipOval(
                          child: (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? OptimizedImage(
                                  imageUrl: avatarUrl,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 180,
                                  memCacheHeight: 180,
                                )
                              : const Icon(Icons.person_rounded, size: 48, color: Color(0xFF64748B)),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    userName,
                    style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    userPhone,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'STORE MANAGER',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          staffId,
                          style: GoogleFonts.firaCode(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 2. CLEAN & PROPER DETAILS LIST (FULL LABELS & VALUES, NO TRUNCATION)
            Text(
              'Work & Account Details',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildDetailItem(
                    icon: Icons.storefront_rounded,
                    label: 'Store Branch',
                    value: branch,
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _buildDetailItem(
                    icon: Icons.schedule_rounded,
                    label: 'Shift Timing',
                    value: shiftTiming,
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _buildDetailItem(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Payout UPI ID',
                    value: upiId,
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _buildDetailItem(
                    icon: Icons.location_on_rounded,
                    label: 'Work Location',
                    value: 'Pulicat Central HQ, Tamil Nadu',
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _buildDetailItem(
                    icon: Icons.verified_user_rounded,
                    label: 'Account Status',
                    value: 'Active • Verified Staff',
                    valueColor: const Color(0xFF059669),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. IN-APP LIVE SUPPORT CHAT
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  AppHaptics.selectionClick();
                  context.push('/support-chat');
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live Support & Operations Chat',
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'Realtime Support • 06:00 AM - 10:00 PM',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 15),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. LOGOUT BUTTON
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFECACA), width: 1.2),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  AppHaptics.mediumImpact();
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  'LOGOUT ACCOUNT',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF475569)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
