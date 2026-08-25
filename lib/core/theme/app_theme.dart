import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF059669); // Emerald Speed Green (Swiggy / Blinkit Partner)
  static const Color primaryDark = Color(0xFF047857);
  static const Color accent = Color(0xFF10B981); // Bright Mint Green
  static const Color indigoAccent = Color(0xFF4F46E5); // Electric Indigo
  static const Color warning = Color(0xFFF59E0B); // Amber Gold
  static const Color danger = Color(0xFFEF4444); // Coral Red
  static const Color navyBlue = Color(0xFF0F172A); // Dark Slate 900
  static const Color border = Color(0xFFE2E8F0); // Soft Slate 200
  static const Color background = Color(0xFFF8FAFC); // Light Crisp Clean Background
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);

  // Role Colors
  static const Color partnerGold = Color(0xFFD97706); // Marketing
  static const Color deliveryBlue = Color(0xFF0284C7); // Delivery
  
  // Premium Zero-Glow Subtle Box Shadows
  static const BoxShadow _softBoxShadow = BoxShadow(
    color: Color(0x08000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static const BoxShadow _cardBoxShadow = BoxShadow(
    color: Color(0x06000000),
    blurRadius: 6,
    offset: Offset(0, 2),
  );

  static const List<BoxShadow> softShadow = [_softBoxShadow];
  static const List<BoxShadow> cardShadow = [_cardBoxShadow];
}

class AppBadges {
  static Widget capsule({
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    IconData? icon,
    double fontSize = 10.5,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // Preset Modern Pastel Badges (Swiggy / Blinkit style)
  static Widget success(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFFBBF7D0),
        textColor: const Color(0xFF15803D),
      );

  static Widget info(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFF0F9FF),
        borderColor: const Color(0xFFBAE6FD),
        textColor: const Color(0xFF0369A1),
      );

  static Widget purple(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFF5F3FF),
        borderColor: const Color(0xFFDDD6FE),
        textColor: const Color(0xFF6D28D9),
      );

  static Widget warning(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFFFFBEB),
        borderColor: const Color(0xFFFDE68A),
        textColor: const Color(0xFFB45309),
      );

  static Widget teal(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFF0FDFA),
        borderColor: const Color(0xFF99F6E4),
        textColor: const Color(0xFF0F766E),
      );

  static Widget danger(String label, {IconData? icon}) => capsule(
        label: label,
        icon: icon,
        bgColor: const Color(0xFFFFF1F2),
        borderColor: const Color(0xFFFECDD3),
        textColor: const Color(0xFFBE123C),
      );
}

class AppTextStyles {
  // Swiggy-style crisp, punchy, geometric typography (Plus Jakarta Sans)
  static final TextStyle h1 = GoogleFonts.plusJakartaSans(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: AppColors.navyBlue,
    letterSpacing: -0.6,
  );

  static final TextStyle h2 = GoogleFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.navyBlue,
    letterSpacing: -0.4,
  );

  static final TextStyle h3 = GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.navyBlue,
    letterSpacing: -0.2,
  );

  static final TextStyle bodyLarge = GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
  );

  static final TextStyle bodyMedium = GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static final TextStyle bodySmall = GoogleFonts.plusJakartaSans(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static final TextStyle caption = GoogleFonts.plusJakartaSans(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static final TextStyle badge = GoogleFonts.plusJakartaSans(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
  );

  static final TextStyle price = GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static final TextStyle code = GoogleFonts.firaCode(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navyBlue,
        iconTheme: const IconThemeData(color: AppColors.navyBlue),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.navyBlue,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textHint, fontSize: 13.5),
      ),
    );
  }
}
