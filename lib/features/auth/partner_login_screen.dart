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

  final SoundService _soundService = SoundService();

  // Premium Dark Navy Theme Palette
  static const Color _navyBgStart = Color(0xFF0A1128);
  static const Color _navyBgMid = Color(0xFF0E1A38);
  static const Color _navyBgEnd = Color(0xFF162544);
  static const Color _brandEmerald = Color(0xFF059669);
  static const Color _brandEmeraldLight = Color(0xFF10B981);

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
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

      // Refresh and fetch staff profile with roles from database
      await ref.read(authNotifierProvider.notifier).refreshProfile();
      final authState = ref.read(authNotifierProvider);
      final roles = authState.staffProfile?['roles'] as List<dynamic>? ?? [];
      final rolesList = roles.map((e) => e.toString()).toList();

      if (!mounted) return;
      setState(() => _isLoading = false);

      // AUTOMATIC ROLE-BASED ROUTING:
      // 1. Delivery Partner -> /delivery-dashboard
      // 2. Marketing Executive -> /marketing-dashboard
      // 3. Store Manager / Admin -> /store-dashboard
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
          _errorMessage = cleanMsg.isNotEmpty ? cleanMsg : 'Login failed. Please check credentials.';
        });
        AppHaptics.error();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyBgStart,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_navyBgStart, _navyBgMid, _navyBgEnd],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. BRAND HERO HEADER (DARK NAVY WITH GLOWING LOGO + REFINED TYPOGRAPHY)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                child: Column(
                  children: [
                    // Floating Logo with Ambient Emerald Glow
                    Hero(
                      tag: 'store_logo',
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _brandEmerald.withValues(alpha: 0.32),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/icons/store_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Brand Title with Refined Plus Jakarta Sans
                    Text(
                      'MeenMart Partner',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),

                  ],
                ),
              ),

              // 2. WHITE CURVED SINGLE LOGIN FORM SECTION
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 18,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Portal Login Header with Refined Modern Typography
                        Text(
                          'Staff Login',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enter your credentials to access your dashboard',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Error Banner if Login Fails
                        if (_errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 20, color: Color(0xFFDC2626)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      color: const Color(0xFFDC2626),
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // USER ID / EMAIL LABEL
                        Text(
                          'USER ID / EMAIL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF334155),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _userIdCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                              size: 21,
                              color: _brandEmerald,
                            ),
                            hintText: 'e.g. manager@meenmart.com',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _brandEmerald, width: 2.0),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // PASSWORD LABEL
                        Text(
                          'PASSWORD',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF334155),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 21,
                              color: _brandEmerald,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: const Color(0xFF64748B),
                              ),
                              onPressed: () {
                                AppHaptics.selectionClick();
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            hintText: 'Enter your password',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _brandEmerald, width: 2.0),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),

                        // DEEPLY OPTIMIZED PROMINENT LOGIN BUTTON (LARGER TEXT, NO ARROW, VIBRANT GRADIENT & GLOW)
                        Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_brandEmerald, _brandEmeraldLight],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _brandEmerald.withValues(alpha: 0.38),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _handleLogin,
                              borderRadius: BorderRadius.circular(14),
                              splashColor: Colors.white.withValues(alpha: 0.25),
                              highlightColor: Colors.white.withValues(alpha: 0.15),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.8,
                                        ),
                                      )
                                    : Text(
                                        'LOGIN TO PORTAL',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
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
}
