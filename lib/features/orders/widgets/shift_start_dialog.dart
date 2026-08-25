import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/utils/shift_prefs.dart';

class ShiftStartDialog extends StatefulWidget {
  final String staffName;
  final String staffId;
  final VoidCallback onShiftStarted;

  const ShiftStartDialog({
    super.key,
    required this.staffName,
    required this.staffId,
    required this.onShiftStarted,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String staffName,
    required String staffId,
    required VoidCallback onShiftStarted,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ShiftStartDialog(
        staffName: staffName,
        staffId: staffId,
        onShiftStarted: onShiftStarted,
      ),
    );
  }

  @override
  State<ShiftStartDialog> createState() => _ShiftStartDialogState();
}

class _ShiftStartDialogState extends State<ShiftStartDialog> {
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _isUploading = false;
  bool _isLocationPermissionGranted = false;
  bool _isCheckingLocation = true;

  double? _realLat;
  double? _realLng;
  String _locationStatusText = 'Fetching GPS...';
  final String _shiftWindow = '07:00 AM - 05:00 PM';

  @override
  void initState() {
    super.initState();
    _fetchRealGpsLocation();
  }

  Future<void> _fetchRealGpsLocation() async {
    setState(() {
      _isCheckingLocation = true;
      _locationStatusText = 'Fetching GPS...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationStatusText = 'Please turn on Device GPS';
            _isLocationPermissionGranted = false;
            _isCheckingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationStatusText = 'Location permission denied (Tap to allow)';
              _isLocationPermissionGranted = false;
              _isCheckingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationStatusText = 'Please enable location in App Settings';
            _isLocationPermissionGranted = false;
            _isCheckingLocation = false;
          });
        }
        return;
      }

      // Real Device GPS Coordinates
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      if (mounted) {
        setState(() {
          _realLat = position.latitude;
          _realLng = position.longitude;
          _isLocationPermissionGranted = true;
          _locationStatusText = '${position.latitude.toStringAsFixed(4)}° N, ${position.longitude.toStringAsFixed(4)}° E';
          _isCheckingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Real GPS error: $e');
      // Fallback to last known position if current times out
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
          setState(() {
            _realLat = lastPos.latitude;
            _realLng = lastPos.longitude;
            _isLocationPermissionGranted = true;
            _locationStatusText = '${lastPos.latitude.toStringAsFixed(4)}° N, ${lastPos.longitude.toStringAsFixed(4)}° E';
            _isCheckingLocation = false;
          });
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isCheckingLocation = false;
          _locationStatusText = 'GPS unavailable (Tap to retry)';
        });
      }
    }
  }

  Future<void> _takeMarketPhoto() async {
    AppHaptics.selectionClick();
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 60,
      );

      if (photo != null && mounted) {
        setState(() {
          _capturedImage = File(photo.path);
        });
        AppHaptics.lightImpact();
      }
    } catch (e) {
      debugPrint('Camera capture error: $e');
    }
  }

  Future<void> _submitShiftStart() async {
    if (!_isLocationPermissionGranted || _realLat == null) {
      await _fetchRealGpsLocation();
      if (!_isLocationPermissionGranted || _realLat == null) {
        if (!mounted) return;
        AppHaptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Live GPS location is required to start shift! Please turn ON device GPS.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (_capturedImage == null) {
      if (!mounted) return;
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Live store/market photo is required to start shift!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    AppHaptics.mediumImpact();

    try {
      final client = Supabase.instance.client;
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final isOnTime = now.hour < 7 || (now.hour == 7 && now.minute <= 15);

      final cleanId = widget.staffId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'shift_checkin_${cleanId}_${now.millisecondsSinceEpoch}.jpg';

      final bytes = await _capturedImage!.readAsBytes();
      var uploadBytes = bytes;
      try {
        // Ultra-compression for lightning fast uploads and minimal storage
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 600,
          minHeight: 600,
          quality: 50,
          format: CompressFormat.jpeg,
        );
        if (compressed.isNotEmpty) {
          uploadBytes = Uint8List.fromList(compressed);
        }
      } catch (_) {}

      String? photoUrl;
      try {
        await client.storage.from('staff-checkins').uploadBinary(
          fileName,
          uploadBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '3600', upsert: true),
        );
        photoUrl = client.storage.from('staff-checkins').getPublicUrl(fileName);
      } catch (stErr) {
        debugPrint('Storage checkin upload notice: $stErr');
      }

      try {
        final authUser = client.auth.currentUser;
        final finalLat = _realLat ?? 13.4217;
        final finalLng = _realLng ?? 80.3228;
        final locationLabel = 'Live GPS (${finalLat.toStringAsFixed(4)}° N, ${finalLng.toStringAsFixed(4)}° E)';

        await client.from('staff_attendance').insert({
          'auth_id': authUser?.id ?? widget.staffId,
          'staff_name': widget.staffName,
          'date': dateStr,
          'shift_window': _shiftWindow,
          'check_in_time': now.toIso8601String(),
          'status': 'present',
          'is_on_time': isOnTime,
          'photo_url': photoUrl,
          'live_photo_url': photoUrl,
          'latitude': finalLat,
          'longitude': finalLng,
          'location_name': locationLabel,
          'created_at': now.toIso8601String(),
        });
      } catch (dbErr) {
        debugPrint('DB attendance insert notice: $dbErr');
      }

      // Persist locally so it NEVER prompts again today on app launch / restart
      try {
        final authId = client.auth.currentUser?.id ?? widget.staffId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(ShiftPrefs.startedDateKey(authId), dateStr);
        await prefs.setString(ShiftPrefs.checkInTimeKey(authId), now.toIso8601String());
        await prefs.setString(ShiftPrefs.formattedTimeKey(authId), DateFormat('hh:mm a').format(now));
      } catch (_) {}

      // Background cleanup of expired operational media
      try {
        await client.rpc('clean_expired_3day_operational_photos');
      } catch (_) {}

      SoundService().playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        widget.onShiftStarted();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Shift start error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayFormatted = DateFormat('dd MMM yyyy (EEE)').format(now);
    final currentTimeStr = DateFormat('hh:mm a').format(now);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. CLEAN HEADER (TITLE & CLOSE BUTTON)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🌅 Morning Shift Clock-In',
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daily Morning Check-in (07:00 AM – 05:00 PM)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. TIMING & DATE PILL
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text(
                          todayFormatted,
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF047857)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.access_time_filled_rounded, size: 13, color: Color(0xFF059669)),
                        const SizedBox(width: 5),
                        Text(
                          currentTimeStr,
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w900, color: const Color(0xFF047857)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3. MANAGER & REAL GPS LOCATION CARD
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Row 1: Manager
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFF059669),
                          child: Text(
                            widget.staffName.isNotEmpty ? widget.staffName[0].toUpperCase() : 'M',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.staffName} (Store Manager)',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),
                    // Row 2: Real GPS Location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: _isLocationPermissionGranted ? const Color(0xFF059669) : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _isCheckingLocation
                              ? Row(
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Fetching GPS...',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                )
                              : Text(
                                  _locationStatusText,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _isLocationPermissionGranted ? const Color(0xFF334155) : const Color(0xFFB45309),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        const SizedBox(width: 6),
                        if (_isLocationPermissionGranted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: Text(
                              '🟢 Live GPS',
                              style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                            ),
                          )
                        else
                          InkWell(
                            onTap: _fetchRealGpsLocation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text(
                                'REFRESH GPS',
                                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: const Color(0xFFD97706)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. MARKET PHOTO CARD
              Text(
                'Store / Market Photo Proof',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),

              _buildPhotoCard(),
              const SizedBox(height: 16),

              // 5. START SHIFT BUTTON
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF047857)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isUploading ? null : _submitShiftStart,
                    child: Center(
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Start Morning Shift',
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
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
    );
  }

  Widget _buildPhotoCard() {
    if (_capturedImage != null) {
      return Stack(
        alignment: Alignment.bottomRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              _capturedImage!,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: InkWell(
              onTap: _takeMarketPhoto,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Retake Photo',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: _takeMarketPhoto,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF059669), size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to Capture Live Photo',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Morning fresh seafood stock or store photo',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
