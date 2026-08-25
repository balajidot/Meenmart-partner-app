import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();

  void _init() {
    try {
      _player.setVolume(1.0);
      _player.setPlayerMode(PlayerMode.lowLatency);
      _player.setReleaseMode(ReleaseMode.release);
    } catch (_) {}
  }

  Future<void> playSuccessChime() async {
    try {
      await _player.play(AssetSource('sounds/success_ding.wav'));
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Sound error: $e');
    }
  }

  Future<void> playSuccessSound() => playSuccessChime();

  Future<void> playNewOrderChime() async {
    try {
      await _player.play(AssetSource('sounds/new_order.wav'));
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('Sound error: $e');
    }
  }

  Future<void> playNewOrderAlert() => playNewOrderChime();

  Future<void> playAlertChime() async {
    try {
      await _player.play(AssetSource('sounds/new_alert.wav'));
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Sound error: $e');
    }
  }

  Future<void> playStepTransition() async {
    try {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('System sound notice: $e');
    }
  }
}
