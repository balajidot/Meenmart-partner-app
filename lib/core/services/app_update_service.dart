import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_update_info.dart';
import '../widgets/app_update_dialog.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  // The installed build, read from the APK itself. These used to be
  // hard-coded and had to be bumped by hand with pubspec on every release;
  // forgetting made the new build offer itself as an update forever.
  static int currentVersionCode = 0;
  static String currentVersionName = '';

  static Future<void> _loadInstalledVersion() async {
    if (currentVersionName.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber) ?? 0;
      // `flutter build apk --split-per-abi` stores abi * 1000 + build number
      // (arm64 build 2 -> 2002). The settings row holds the plain pubspec
      // build number, so compare against that part only.
      currentVersionCode = code >= 1000 ? code % 1000 : code;
      currentVersionName = info.version;
    } catch (e) {
      debugPrint('Package info notice: $e');
    }
  }

  AppUpdateInfo? _cachedUpdateInfo;
  AppUpdateInfo? get cachedUpdateInfo => _cachedUpdateInfo;

  RealtimeChannel? _realtimeChannel;
  bool _isChecking = false;

  /// Fetches the latest store app update settings from Supabase
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (_isChecking) return _cachedUpdateInfo;
    _isChecking = true;

    try {
      await _loadInstalledVersion();
      // Unknown installed version: never claim an update is available.
      if (currentVersionName.isEmpty) return null;
      final db = Supabase.instance.client;
      final rows = await db
          .from('settings')
          .select('key, value')
          .like('key', 'store_%')
          .timeout(const Duration(seconds: 4));

      final map = <String, String>{};
      for (var r in rows) {
        final k = r['key']?.toString();
        final v = r['value']?.toString();
        if (k != null && v != null) {
          map[k] = v;
        }
      }

      final info = AppUpdateInfo.fromSettingsMap(
        map,
        currentCode: currentVersionCode,
        currentName: currentVersionName,
      );

      _cachedUpdateInfo = info;
      return info;
    } catch (e) {
      debugPrint('App update check notice: $e');
      return _cachedUpdateInfo;
    } finally {
      _isChecking = false;
    }
  }

  /// Checks for update. ONLY prompts if isManual is true (user explicitly tapped "Check for Updates")
  Future<void> checkAndPrompt(BuildContext context, {bool isManual = false}) async {
    // Only proceed if explicitly requested by the user via manual check
    if (!isManual) return;
    if (!context.mounted) return;

    final info = await checkForUpdate();
    if (!context.mounted) return;

    if (info != null && info.isUpdateAvailable) {
      AppHaptics.heavyImpact();
      SoundService().playNewOrderChime();
      await AppUpdateDialog.show(context, info);
    } else {
      AppHaptics.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🎉 App is up to date (v$currentVersionName - Latest)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Realtime listener (disabled from automatic popups per user requirement)
  void subscribeRealtime(BuildContext context) {
    // No automatic background popup
  }

  void dispose() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }
}
