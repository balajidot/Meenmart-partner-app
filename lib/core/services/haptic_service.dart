import 'package:flutter/services.dart';

class AppHaptics {
  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  static void selectionClick() {
    HapticFeedback.selectionClick();
  }

  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    HapticFeedback.heavyImpact();
  }

  static void success() {
    HapticFeedback.heavyImpact();
  }

  static void warning() {
    HapticFeedback.mediumImpact();
  }

  static void error() {
    HapticFeedback.heavyImpact();
  }
}

class HapticService {
  static void lightImpact() => AppHaptics.lightImpact();
  static void selectionClick() => AppHaptics.selectionClick();
  static void mediumImpact() => AppHaptics.mediumImpact();
  static void heavyImpact() => AppHaptics.heavyImpact();
  static void success() => AppHaptics.success();
  static void warning() => AppHaptics.warning();
  static void error() => AppHaptics.error();
}
