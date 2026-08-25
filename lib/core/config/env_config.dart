import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized environment configuration loader.
/// Loads variables from `.env` asset file with fallback to `--dart-define`.
class EnvConfig {
  static bool _isInitialized = false;

  /// Loads the `.env` file safely.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await dotenv.load(fileName: '.env');
      _isInitialized = true;
    } catch (e) {
      debugPrint('ℹ️ .env file load notice: $e (Falling back to dart-define if provided)');
    }
  }

  /// Supabase Project URL
  static String get supabaseUrl {
    if (_isInitialized && dotenv.maybeGet('SUPABASE_URL') != null && dotenv.get('SUPABASE_URL').trim().isNotEmpty) {
      return dotenv.get('SUPABASE_URL').trim();
    }
    return const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  }

  /// Supabase Anon / Publishable Key
  static String get supabaseAnonKey {
    if (_isInitialized && dotenv.maybeGet('SUPABASE_ANON_KEY') != null && dotenv.get('SUPABASE_ANON_KEY').trim().isNotEmpty) {
      return dotenv.get('SUPABASE_ANON_KEY').trim();
    }
    return const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  }
}
