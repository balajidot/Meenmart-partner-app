import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/providers/auth_provider.dart';

class PartnerLoginScreen extends ConsumerStatefulWidget {
  const PartnerLoginScreen({super.key});

  @override
  ConsumerState<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends ConsumerState<PartnerLoginScreen> {
  final _userIdCtrl = TextEditingController(text: 'manager@meenmart.com');
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  String _selectedRole = 'store_manager';
  final SoundService _soundService = SoundService();

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _selectRolePreset(String role, String userId) {
    AppHaptics.selectionClick();
    setState(() {
      _selectedRole = role;
      _userIdCtrl.text = userId;
      _errorMessage = null;
    });
  }

  Future<void> _handleLogin() async {
    final rawUserId = _userIdCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (rawUserId.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both User ID and Password';
      });
      AppHaptics.error();
      return;
    }

    // Auto-resolve simple username to email domain if omitted
    final effectiveEmail = rawUserId.contains('@') ? rawUserId : '$rawUserId@meenmart.com';

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    AppHaptics.mediumImpact();

    try {
      final client = Supabase.instance.client;
      final res = await client.auth.signInWithPassword(
        email: effectiveEmail,
        password: password,
      );

      if (res.user == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid User ID or Password';
          });
          AppHaptics.error();
        }
        return;
      }

      _soundService.playSuccessChime();
      AppHaptics.success();

      try {
        await NotificationService().init();
      } catch (_) {}

      await ref.read(authNotifierProvider.notifier).refreshProfile();
      final authState = ref.read(authNotifierProvider);
      final roles = authState.staffProfile?['roles'] as List<dynamic>? ?? [];
      final rolesList = roles.map((e) => e.toString()).toList();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (rolesList.contains('delivery_partner') && !rolesList.contains('store_manager') && !rolesList.contains('admin')) {
        context.go('/delivery-dashboard');
      } else if ((rolesList.contains('marketing_executive') || rolesList.contains('marketing')) && !rolesList.contains('store_manager') && !rolesList.contains('admin')) {
        context.go('/marketing-dashboard');
      } else {
        context.go('/store-dashboard');
      }
    } catch (e) {
      if (mounted) {
        final rawMsg = e.toString();
        final cleanMsg = rawMsg
            .replaceAll('AuthException:', '')
            .replaceAll('Exception:', '')
            .trim();
        setState(() {
          _isLoading = false;
          _errorMessage = cleanMsg.isNotEmpty ? cleanMsg : 'Login failed. Please try again.';
        });
        AppHaptics.error();
      }
    }
  }

  Color get _rolePrimaryColor {
    switch (_selectedRole) {
      case 'delivery_partner':
        return const Color(0xFF0284C7); // Clean Delivery Blue
      case 'marketing_executive':
        return const Color(0xFFD97706); // Clean Amber
      default:
        return const Color(0xFF059669); // Clean Emerald
    }
  }

  Color get _roleGradientEnd {
    switch (_selectedRole) {
      case 'delivery_partner':
        return const Color(0xFF0369A1);
      case 'marketing_executive':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF047857);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rolePrimaryColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_rolePrimaryColor, _roleGradientEnd],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. BRAND HERO HEADER (FLOATING LOGO + CLEAN TYPOGRAPHY)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  children: [
                    // Floating Logo Card
                    Hero(
                      tag: 'store_logo',
                      child: Container(
                        width: 90,
                        height: 90,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/icons/store_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Brand Title
                    Text(
                      'MeenMart Partner',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // Frosted Capsule
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        'OPERATIONS & DELIVERY PORTAL',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. WHITE CURVED FORM SECTION
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ROLE SELECTOR TABS WITH ROBUST ADAPTIVE LAYOUT
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              _buildRoleTab(
                                roleKey: 'store_manager',
                                icon: Icons.storefront_rounded,
                                label: 'Store Manager',
                                userId: 'manager@meenmart.com',
                              ),
                              _buildRoleTab(
                                roleKey: 'delivery_partner',
                                icon: Icons.moped_rounded,
                                label: 'Delivery',
                                userId: 'delivery@meenmart.com',
                              ),
                              _buildRoleTab(
                                roleKey: 'marketing_executive',
                                icon: Icons.campaign_rounded,
                                label: 'Marketing',
                                userId: 'marketing@meenmart.com',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Error Banner if Login Fails
                        if (_errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFFDC2626),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // USER ID INPUT BOX
                        Text(
                          'User ID',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _userIdCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(Icons.person_outline_rounded, size: 20, color: _rolePrimaryColor),
                            hintText: 'Enter User ID (e.g. manager)',
                            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _rolePrimaryColor, width: 1.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // PASSWORD INPUT BOX
                        Text(
                          'Password',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: _rolePrimaryColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 19,
                                color: const Color(0xFF94A3B8),
                              ),
                              onPressed: () {
                                AppHaptics.selectionClick();
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            hintText: 'Enter your password',
                            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _rolePrimaryColor, width: 1.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // HIGH-TOUCH LOGIN BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _rolePrimaryColor,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: _rolePrimaryColor.withValues(alpha: 0.35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'LOGIN TO PORTAL',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 18),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ENCRYPTED ACCESS FOOTER
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF64748B)),
                                const SizedBox(width: 5),
                                Text(
                                  'Authorized Staff Only • MeenMart v2.4',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleTab({
    required String roleKey,
    required IconData icon,
    required String label,
    required String userId,
  }) {
    final isSelected = _selectedRole == roleKey;
    return Expanded(
      child: InkWell(
        onTap: () => _selectRolePreset(roleKey, userId),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? _rolePrimaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _rolePrimaryColor.withValues(alpha: 0.25),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
