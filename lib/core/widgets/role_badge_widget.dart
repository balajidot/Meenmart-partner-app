import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class RoleBadgeWidget extends StatelessWidget {
  final String role;
  
  const RoleBadgeWidget({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String label;
    IconData icon;

    switch (role) {
      case 'store_manager':
        badgeColor = AppColors.accent;
        label = 'Store Manager';
        icon = Icons.storefront;
        break;
      case 'delivery_partner':
        badgeColor = AppColors.deliveryBlue;
        label = 'Delivery';
        icon = Icons.moped;
        break;
      case 'marketing_executive':
        badgeColor = AppColors.partnerGold;
        label = 'Marketing';
        icon = Icons.campaign;
        break;
      default:
        badgeColor = AppColors.textSecondary;
        label = 'Staff';
        icon = Icons.person;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
