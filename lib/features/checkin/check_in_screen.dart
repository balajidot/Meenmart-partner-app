import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/optimized_image.dart';
import '../drawer/partner_drawer.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final AttendanceRepository _repository = AttendanceRepository();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isPunching = false;

  AttendanceRecord? _todayRecord;
  List<AttendanceRecord> _historyRecords = [];
  AttendanceStats _stats = AttendanceStats.empty();

  String _filterTab = 'all'; // 'all', 'week', 'month'
  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _startLiveClock();
    _loadAttendanceData();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startLiveClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _loadAttendanceData() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final today = await _repository.getTodayAttendance(userId);
      final history = await _repository.getAttendanceHistory(userId);
      final stats = _repository.calculateStats(history);

      if (mounted) {
        setState(() {
          _todayRecord = today;
          _historyRecords = history;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<AttendanceRecord> get _filteredHistory {
    final now = DateTime.now();
    if (_filterTab == 'week') {
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      return _historyRecords.where((r) {
        if (r.checkInDateTime != null) {
          return r.checkInDateTime!.isAfter(sevenDaysAgo);
        }
        return true;
      }).toList();
    } else if (_filterTab == 'month') {
      return _historyRecords.where((r) {
        if (r.checkInDateTime != null) {
          return r.checkInDateTime!.month == now.month && r.checkInDateTime!.year == now.year;
        }
        return true;
      }).toList();
    }
    return _historyRecords;
  }

  String _calculateLiveWorkingDuration() {
    if (_todayRecord == null || _todayRecord!.checkInDateTime == null) {
      return '0h 00m';
    }
    final inTime = _todayRecord!.checkInDateTime!;
    final outTime = _todayRecord!.checkOutDateTime ?? _currentTime;
    final diff = outTime.difference(inTime);
    if (diff.isNegative) return '0h 00m';
    final hours = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    final secs = diff.inSeconds.remainder(60);
    if (_todayRecord!.isPunchedOut) {
      return '${hours}h ${mins.toString().padLeft(2, '0')}m';
    }
    return '${hours}h ${mins.toString().padLeft(2, '0')}m ${secs.toString().padLeft(2, '0')}s';
  }

  // 1. CLOCK IN
  Future<void> _startPunchInFlow() async {
    AppHaptics.selectionClick();

    double? lat;
    double? lng;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 5)),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }
    } catch (_) {}

    File? selfie;
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 65,
      );
      if (photo != null) {
        selfie = File(photo.path);
      } else {
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera Access Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() => _isPunching = true);
    AppHaptics.mediumImpact();

    try {
      final authState = ref.read(authNotifierProvider);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Your session has expired. Please sign in again.');
      final staffName = authState.staffProfile?['name'] ?? 'Store Partner';

      final record = await _repository.recordPunchIn(
        userId: userId,
        staffName: staffName,
        selfiePhoto: selfie,
        latitude: lat,
        longitude: lng,
        locationLabel: 'Pazhaverkadu Store Hub',
      );

      SoundService().playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        setState(() {
          _todayRecord = record;
          _isPunching = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clocked in successfully at ${record.checkInTimeFormatted}',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );

        await _loadAttendanceData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPunching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clock in: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 2. CLOCK OUT
  Future<void> _showPunchOutConfirmation() async {
    if (_todayRecord == null) return;
    AppHaptics.selectionClick();

    final duration = _calculateLiveWorkingDuration();

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End Today\'s Shift',
                        style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Confirm your clock-out time',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Clock In', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_todayRecord!.checkInTimeFormatted, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Shift Duration', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(duration, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: Text('CLOCK OUT NOW', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (confirm == true) {
      setState(() => _isPunching = true);
      AppHaptics.mediumImpact();

      try {
        final authState = ref.read(authNotifierProvider);
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId == null) throw StateError('Your session has expired. Please sign in again.');
        final staffName = authState.staffProfile?['name'] ?? 'Store Partner';

        final updated = await _repository.recordPunchOut(
          todayRecord: _todayRecord!,
          userId: userId,
          staffName: staffName,
        );

        SoundService().playSuccessChime();
        AppHaptics.success();

        if (mounted) {
          setState(() {
            _todayRecord = updated;
            _isPunching = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text(
                'Shift ended successfully at ${updated.checkOutTimeFormatted}',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          );

          await _loadAttendanceData();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isPunching = false);
        }
      }
    }
  }

  // 3. FULL PHOTO PREVIEW
  void _showSelfieModal(AttendanceRecord record) {
    AppHaptics.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.staffName,
                        style: GoogleFonts.plusJakartaSans(fontSize: 15.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        '${record.date} • ${record.checkInTimeFormatted}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: record.photoUrl != null && record.photoUrl!.isNotEmpty
                    ? OptimizedImage(
                        imageUrl: record.photoUrl!,
                        width: 260,
                        height: 260,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 260,
                        height: 200,
                        color: const Color(0xFFF1F5F9),
                        child: const Icon(Icons.no_photography_rounded, size: 48, color: Color(0xFF94A3B8)),
                      ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF059669)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Pazhaverkadu Store Hub',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF475569), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final profile = authState.staffProfile;
    final staffName = profile?['name'] ?? 'Store Partner';

    final isPunchedIn = _todayRecord != null;
    final isPunchedOut = _todayRecord?.isPunchedOut == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A), size: 24),
            onPressed: () {
              AppHaptics.selectionClick();
              Scaffold.of(ctx).openDrawer();
            },
          ),
        ),
        title: Text(
          'Staff Attendance',
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: -0.2),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF059669)),
            tooltip: 'Refresh Records',
            onPressed: () {
              AppHaptics.selectionClick();
              _loadAttendanceData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              color: const Color(0xFF059669),
              onRefresh: _loadAttendanceData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. TODAY'S SHIFT STATUS CARD
                    _buildTodayShiftCard(staffName, isPunchedIn, isPunchedOut),

                    const SizedBox(height: 18),

                    // 2. MONTHLY SUMMARY (CLEAN 3-CARD STATS)
                    _buildMonthlyOverviewSection(),

                    const SizedBox(height: 22),

                    // 3. PUNCH HISTORY & FILTER TABS
                    _buildHistoryHeaderAndTabs(),

                    const SizedBox(height: 12),

                    // 4. TIMELINE LIST OF LOGS
                    _buildHistoryList(),
                  ],
                ),
              ),
            ),
    );
  }

  // --- 1. HERO TODAY'S SHIFT CARD ---
  Widget _buildTodayShiftCard(String staffName, bool isPunchedIn, bool isPunchedOut) {
    final timeStr = DateFormat('hh:mm:ss a').format(_currentTime);
    final dateStr = DateFormat('EEEE, dd MMM yyyy').format(_currentTime);

    Color statusBgColor = const Color(0xFFFEF3C7);
    Color statusTextColor = const Color(0xFFD97706);
    String statusLabel = 'NOT CLOCKED IN';
    IconData statusIcon = Icons.schedule_rounded;

    if (isPunchedOut) {
      statusBgColor = const Color(0xFFEFF6FF);
      statusTextColor = const Color(0xFF2563EB);
      statusLabel = 'SHIFT COMPLETED';
      statusIcon = Icons.verified_rounded;
    } else if (isPunchedIn) {
      statusBgColor = const Color(0xFFECFDF5);
      statusTextColor = const Color(0xFF059669);
      statusLabel = 'ACTIVE ON SHIFT';
      statusIcon = Icons.fiber_manual_record_rounded;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 10, color: statusTextColor),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: statusTextColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        staffName,
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        'Shift: 07:00 AM – 05:00 PM',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                // Clock
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: GoogleFonts.firaCode(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        dateStr.split(',').first,
                        style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF34D399), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 2 Column Clock In / Clock Out Cards (Ample Space, No Truncation)
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeBox(
                        title: 'Clock In',
                        value: _todayRecord?.checkInTimeFormatted ?? '--:--',
                        icon: Icons.login_rounded,
                        color: const Color(0xFF059669),
                        isActive: isPunchedIn,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTimeBox(
                        title: 'Clock Out',
                        value: _todayRecord?.checkOutTimeFormatted ?? (isPunchedIn && !isPunchedOut ? 'In Progress' : '--:--'),
                        icon: Icons.logout_rounded,
                        color: isPunchedOut ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        isActive: isPunchedOut,
                      ),
                    ),
                  ],
                ),

                // Active Hours Banner
                if (isPunchedIn) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF059669)),
                            const SizedBox(width: 6),
                            Text(
                              isPunchedOut ? 'Total Shift Time' : 'Working Time Today',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
                            ),
                          ],
                        ),
                        Text(
                          _calculateLiveWorkingDuration(),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                ],

                // Location & Photo Row
                if (_todayRecord != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        if (_todayRecord?.photoUrl != null) ...[
                          GestureDetector(
                            onTap: () => _showSelfieModal(_todayRecord!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: OptimizedImage(
                                imageUrl: _todayRecord!.photoUrl!,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pazhaverkadu Store Hub',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                              ),
                              Text(
                                'GPS Location Verified',
                                style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        if (_todayRecord?.photoUrl != null)
                          TextButton(
                            onPressed: () => _showSelfieModal(_todayRecord!),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('View Photo', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action Button
                _buildActionButton(isPunchedIn, isPunchedOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isActive ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(bool isPunchedIn, bool isPunchedOut) {
    if (_isPunching) {
      return Container(
        height: 48,
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
        child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF059669)))),
      );
    }

    if (!isPunchedIn) {
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _startPunchInFlow,
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: Text('CLOCK IN (TAKE SELFIE)', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
        ),
      );
    }

    if (!isPunchedOut) {
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _showPunchOutConfirmation,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text('CLOCK OUT (END SHIFT)', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 18),
          const SizedBox(width: 8),
          Text(
            'Shift Completed for Today',
            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF374151)),
          ),
        ],
      ),
    );
  }

  // --- 2. MONTHLY OVERVIEW (CLEAN 3 TILES WITH NO TRUNCATION) ---
  Widget _buildMonthlyOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'MONTHLY OVERVIEW',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: 'Days Present',
                value: '${_stats.daysPresent} Days',
                icon: Icons.calendar_today_rounded,
                color: const Color(0xFF059669),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                title: 'Punctuality',
                value: '${_stats.punctualityRate}%',
                icon: Icons.speed_rounded,
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                title: 'Total Hours',
                value: '${_stats.totalHoursWorked.toStringAsFixed(0)} hrs',
                icon: Icons.access_time_rounded,
                color: const Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- 3. PUNCH HISTORY HEADER & SEGMENTED TABS ---
  Widget _buildHistoryHeaderAndTabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attendance History',
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_filteredHistory.length} Records',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF4B5563)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Tabs
        Container(
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: _buildFilterTab('all', 'All Records')),
              Expanded(child: _buildFilterTab('week', 'This Week')),
              Expanded(child: _buildFilterTab('month', 'This Month')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String key, String label) {
    final isSelected = _filterTab == key;
    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() => _filterTab = key);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))] : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }

  // --- 4. HISTORY LIST ---
  Widget _buildHistoryList() {
    final list = _filteredHistory;

    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            const Icon(Icons.history_toggle_off_rounded, size: 40, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 8),
            Text(
              'No Attendance Logs Found',
              style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF374151)),
            ),
            const SizedBox(height: 2),
            Text(
              'No records for this selected period.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final record = list[index];
        return _buildHistoryCard(record);
      },
    );
  }

  Widget _buildHistoryCard(AttendanceRecord record) {
    Color badgeColor = const Color(0xFF059669);
    String badgeText = record.isOnTime ? 'ON TIME' : 'PRESENT';
    if (record.status.contains('LATE')) {
      badgeColor = const Color(0xFFD97706);
      badgeText = 'LATE';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      record.date,
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.plusJakartaSans(fontSize: 9.5, fontWeight: FontWeight.w900, color: badgeColor),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF3F4F6)),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.login_rounded, size: 13, color: Color(0xFF059669)),
                          const SizedBox(width: 5),
                          Text('In: ${record.checkInTimeFormatted}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF374151))),
                          const SizedBox(width: 14),
                          const Icon(Icons.logout_rounded, size: 13, color: Color(0xFF2563EB)),
                          const SizedBox(width: 5),
                          Text(
                            'Out: ${record.checkOutTimeFormatted ?? 'In Progress'}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: record.checkOutTimeFormatted != null ? const Color(0xFF374151) : const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Text(
                            'Duration: ${record.workDuration}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF6B7280), fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Pazhaverkadu Hub',
                              style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: const Color(0xFF6B7280)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Selfie preview thumbnail
                if (record.photoUrl != null && record.photoUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showSelfieModal(record),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: OptimizedImage(
                          imageUrl: record.photoUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 90,
                          memCacheHeight: 90,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
