import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TrackingState {
  idle,
  requestingPermission,
  permissionDenied,
  gpsDisabled,
  broadcasting,
  error,
}

class TrackingStatus {
  final TrackingState state;
  final Position? position;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  const TrackingStatus({
    required this.state,
    this.position,
    this.lastSyncTime,
    this.errorMessage,
  });

  bool get isBroadcasting => state == TrackingState.broadcasting;
}

class DeliveryTrackingService {
  static final DeliveryTrackingService _instance = DeliveryTrackingService._internal();
  static DeliveryTrackingService get instance => _instance;
  DeliveryTrackingService._internal();

  final ValueNotifier<TrackingStatus> statusNotifier = ValueNotifier(
    const TrackingStatus(state: TrackingState.idle),
  );

  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  int? _activePartnerId;
  Position? _lastReportedPosition;
  DateTime? _lastReportedTime;
  // When the device last produced a REAL GPS fix (not a heartbeat resend).
  DateTime? _lastFixTime;

  // A heartbeat must never make an old position look live to the customer.
  static const Duration _maxFixAgeForHeartbeat = Duration(minutes: 2);

  // Bumped by stopTracking(). A start that is still waiting for its first GPS
  // fix when the rider goes Offline must not go on to open the stream.
  int _generation = 0;
  Future<bool>? _startInFlight;

  bool get isTracking => _positionSubscription != null;
  Position? get currentPosition => _lastReportedPosition;

  /// Starts live location streaming and broadcasting to Supabase delivery_partners table.
  Future<bool> startTracking({required int partnerId}) {
    // The delivery screen calls this every time it is rebuilt (drawer
    // navigation disposes and recreates it). Restarting a live stream meant
    // a fresh 8s GPS fix, an extra DB write and a foreground-service restart
    // each time, for no change.
    if (isTracking && _activePartnerId == partnerId) return Future.value(true);
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    late final Future<bool> started;
    started = _start(partnerId).whenComplete(() {
      if (identical(_startInFlight, started)) _startInFlight = null;
    });
    return _startInFlight = started;
  }

  Future<bool> _start(int partnerId) async {
    final generation = _generation;
    bool stopped() => generation != _generation;
    _activePartnerId = partnerId;

    try {
      // 1. Check if location services are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        statusNotifier.value = const TrackingStatus(
          state: TrackingState.gpsDisabled,
          errorMessage: 'Location services are disabled on this device.',
        );
        return false;
      }

      // 2. Check and request location permissions
      statusNotifier.value = const TrackingStatus(state: TrackingState.requestingPermission);
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          statusNotifier.value = const TrackingStatus(
            state: TrackingState.permissionDenied,
            errorMessage: 'Location permission was denied by the user.',
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        statusNotifier.value = const TrackingStatus(
          state: TrackingState.permissionDenied,
          errorMessage: 'Location permission permanently denied. Enable in Settings.',
        );
        return false;
      }

      // 3. Immediately get one accurate fix and broadcast to DB
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (stopped()) return false;
        await _broadcastLocationToSupabase(initialPos, partnerId, isFreshFix: true);
      } catch (e) {
        debugPrint('Initial GPS fix error: $e');
        // A last-known position may be old; show it once but don't treat it
        // as a fresh fix for heartbeats.
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && !stopped()) {
          await _broadcastLocationToSupabase(lastKnown, partnerId, isFreshFix: false);
        }
      }

      if (stopped()) return false;

      // 4. Cancel any prior subscriptions
      await _positionSubscription?.cancel();
      _heartbeatTimer?.cancel();
      if (stopped()) return false;

      // 5. Start continuous position stream (updates every 5 meters of movement).
      // On Android this runs as a FOREGROUND SERVICE (ongoing notification), so
      // updates keep flowing while the rider is inside Google Maps navigation
      // or the screen is off. Without it Android throttles background GPS and
      // the customer's live map goes stale / disappears.
      final LocationSettings locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              // 0 = time-based fixes every intervalDuration even when standing
              // still, so "fresh fix" stays true while waiting at a signal.
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'MeenMart Delivery — Live location ON',
                notificationText: 'Customer-க்கு உங்கள் location பகிரப்படுகிறது. Offline ஆனால் நிற்கும்.',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) => _onNewPosition(position, partnerId),
        onError: (error) {
          debugPrint('Geolocator stream error: $error');
          statusNotifier.value = TrackingStatus(
            state: TrackingState.error,
            position: _lastReportedPosition,
            lastSyncTime: _lastReportedTime,
            errorMessage: error.toString(),
          );
        },
      );

      // 6. Stationary Heartbeat Timer (every 20 seconds):
      // Keeps the customer's "last_location_at" fresh even if the rider is waiting at a traffic signal.
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
        if (_lastReportedPosition != null && _activePartnerId != null) {
          final now = DateTime.now();
          // Only while the GPS is actually still producing fixes. If the last
          // real fix is old (GPS off / lost), stop refreshing last_location_at
          // so the customer map correctly treats the location as stale.
          final fixAge = _lastFixTime == null ? null : now.difference(_lastFixTime!);
          if (fixAge == null || fixAge > _maxFixAgeForHeartbeat) {
            statusNotifier.value = TrackingStatus(
              state: TrackingState.error,
              position: _lastReportedPosition,
              lastSyncTime: _lastReportedTime,
              errorMessage: 'No fresh GPS signal',
            );
            return;
          }
          // If no position update sent in the last 15 seconds, send heartbeat
          if (_lastReportedTime == null || now.difference(_lastReportedTime!).inSeconds >= 15) {
            await _broadcastLocationToSupabase(_lastReportedPosition!, _activePartnerId!, isFreshFix: false);
          }
        }
      });

      return true;
    } catch (e) {
      debugPrint('Error starting delivery tracking: $e');
      statusNotifier.value = TrackingStatus(
        state: TrackingState.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  void _onNewPosition(Position position, int partnerId) {
    final now = DateTime.now();
    _lastFixTime = now;
    // Throttle minimum interval to 3 seconds to avoid spamming the DB
    if (_lastReportedTime != null && now.difference(_lastReportedTime!).inMilliseconds < 3000) {
      _lastReportedPosition = position; // heartbeat will send the newest point
      return;
    }
    _broadcastLocationToSupabase(position, partnerId, isFreshFix: true);
  }

  Future<void> _broadcastLocationToSupabase(Position position, int partnerId, {required bool isFreshFix}) async {
    try {
      _lastReportedPosition = position;
      _lastReportedTime = DateTime.now();
      if (isFreshFix) _lastFixTime = _lastReportedTime;

      // RLS silently updates 0 rows if this login is not linked to the
      // partner row, so confirm the write actually happened.
      final rows = await Supabase.instance.client
          .from('delivery_partners')
          .update({
            'current_lat': position.latitude,
            'current_lng': position.longitude,
            'last_location_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', partnerId)
          .select('id');

      if (rows.isEmpty) {
        statusNotifier.value = TrackingStatus(
          state: TrackingState.error,
          position: position,
          lastSyncTime: _lastReportedTime,
          errorMessage: 'Location not saved: this login is not linked to the delivery partner record',
        );
        return;
      }

      statusNotifier.value = TrackingStatus(
        state: TrackingState.broadcasting,
        position: position,
        lastSyncTime: _lastReportedTime,
      );
    } catch (e) {
      debugPrint('Error syncing live GPS to Supabase: $e');
      statusNotifier.value = TrackingStatus(
        state: TrackingState.error,
        position: position,
        lastSyncTime: _lastReportedTime,
        errorMessage: 'Sync error: $e',
      );
    }
  }

  /// Stops tracking and releases GPS and timer resources.
  Future<void> stopTracking() async {
    _generation++;
    _startInFlight = null; // a later start must not reuse the cancelled one
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activePartnerId = null;
    _lastFixTime = null;

    statusNotifier.value = const TrackingStatus(state: TrackingState.idle);
  }

  /// Opens the device settings page for location permissions.
  Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }
}
