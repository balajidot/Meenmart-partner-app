import 'dart:async';
import 'package:flutter/material.dart';
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

  // Current build specifications of MeenMart Partner App
  static const int currentVersionCode = 2;
  static const String currentVersionName = '2.1.0';

  AppUpdateInfo? _cachedUpdateInfo;
  AppUpdateInfo? get cachedUpdateInfo => _cachedUpdateInfo;

  RealtimeChannel? _realtimeChannel;
  bool _isChecking = false;
  bool _dialogShownThisSession = false;

  /// Fetches the latest store app update settings from Supabase
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (_isChecking) return _cachedUpdateInfo;
    _isChecking = true;

    try {
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

  /// Automatically checks for update and prompts user if a new version is available
  Future<void> checkAndPrompt(BuildContext context, {bool isManual = false}) async {
    if (!context.mounted) return;

    final info = await checkForUpdate();
    if (!context.mounted) return;

    if (info != null && info.isUpdateAvailable) {
      if (isManual || !_dialogShownThisSession || info.isForceUpdate) {
        _dialogShownThisSession = true;
        AppHaptics.heavyImpact();
        SoundService().playNewOrderChime();
        await AppUpdateDialog.show(context, info);
      }
    } else if (isManual) {
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

  /// Subscribes to Realtime changes on settings to broadcast updates instantly to active workers
  void subscribeRealtime(BuildContext context) {
    if (_realtimeChannel != null) {
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = null;
    }

    try {
      final db = Supabase.instance.client;
      _realtimeChannel = db.channel('store-app-updates-realtime').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'settings',
        callback: (payload) async {
          final newRec = payload.newRecord;
          final key = newRec['key']?.toString();
          if (key != null && key.startsWith('store_')) {
            _cachedUpdateInfo = null; // Invalidate cache
            if (context.mounted) {
              await checkAndPrompt(context, isManual: true);
            }
          }
        },
      );
      _realtimeChannel?.subscribe();
    } catch (e) {
      debugPrint('Realtime update subscription notice: $e');
    }
  }

  void dispose() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }
}
