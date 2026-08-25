import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class AttendanceRecord {
  final String id;
  final String authId;
  final String staffName;
  final String date;
  final DateTime? checkInDateTime;
  final DateTime? checkOutDateTime;
  final String checkInTimeFormatted;
  final String? checkOutTimeFormatted;
  final String status;
  final bool isOnTime;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final String locationName;
  final String shiftWindow;

  AttendanceRecord({
    required this.id,
    required this.authId,
    required this.staffName,
    required this.date,
    this.checkInDateTime,
    this.checkOutDateTime,
    required this.checkInTimeFormatted,
    this.checkOutTimeFormatted,
    required this.status,
    required this.isOnTime,
    this.photoUrl,
    this.latitude,
    this.longitude,
    required this.locationName,
    this.shiftWindow = '07:00 AM - 05:00 PM',
  });

  String get workDuration {
    if (checkInDateTime == null) return '0 hrs 0 mins';
    final end = checkOutDateTime ?? (date == DateFormat('yyyy-MM-dd').format(DateTime.now()) ? DateTime.now() : checkInDateTime!.add(const Duration(hours: 10)));
    final diff = end.difference(checkInDateTime!);
    if (diff.isNegative) return '0 hrs';
    final hours = diff.inHours;
    final mins = diff.inMinutes.remainder(60);
    if (hours == 0) return '$mins mins';
    return '${hours}h ${mins}m';
  }

  bool get isPunchedOut => checkOutDateTime != null || checkOutTimeFormatted != null;

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    DateTime? inDt;
    DateTime? outDt;
    String inFmt = '07:00 AM';
    String? outFmt;

    final inRaw = map['check_in_time']?.toString() ?? map['created_at']?.toString();
    if (inRaw != null) {
      try {
        final parsed = DateTime.tryParse(inRaw);
        if (parsed != null) {
          inDt = parsed.toLocal();
          inFmt = DateFormat('hh:mm a').format(inDt);
        } else {
          inFmt = inRaw;
        }
      } catch (_) {
        inFmt = inRaw;
      }
    }

    final outRaw = map['check_out_time']?.toString();
    if (outRaw != null && outRaw.isNotEmpty) {
      try {
        final parsed = DateTime.tryParse(outRaw);
        if (parsed != null) {
          outDt = parsed.toLocal();
          outFmt = DateFormat('hh:mm a').format(outDt);
        } else {
          outFmt = outRaw;
        }
      } catch (_) {
        outFmt = outRaw;
      }
    }

    final createdAtStr = map['created_at']?.toString() ?? DateTime.now().toIso8601String();
    final dateVal = map['date']?.toString() ?? (createdAtStr.length >= 10 ? createdAtStr.substring(0, 10) : DateFormat('yyyy-MM-dd').format(DateTime.now()));

    return AttendanceRecord(
      id: map['id']?.toString() ?? 'att_${DateTime.now().millisecondsSinceEpoch}',
      authId: map['auth_id']?.toString() ?? '',
      staffName: map['staff_name']?.toString() ?? 'Store Partner',
      date: dateVal,
      checkInDateTime: inDt,
      checkOutDateTime: outDt,
      checkInTimeFormatted: inFmt,
      checkOutTimeFormatted: outFmt,
      status: (map['status']?.toString() ?? 'present').toUpperCase(),
      isOnTime: map['is_on_time'] == true || (map['status']?.toString().toLowerCase() == 'on time'),
      photoUrl: map['photo_url']?.toString() ?? map['live_photo_url']?.toString(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationName: map['location_name']?.toString() ?? 'Pazhaverkadu Hub',
      shiftWindow: map['shift_window']?.toString() ?? '07:00 AM - 05:00 PM',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'auth_id': authId,
      'staff_name': staffName,
      'date': date,
      'check_in_time': checkInDateTime?.toIso8601String() ?? checkInTimeFormatted,
      'check_out_time': checkOutDateTime?.toIso8601String() ?? checkOutTimeFormatted,
      'status': status,
      'is_on_time': isOnTime,
      'photo_url': photoUrl,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'shift_window': shiftWindow,
      'created_at': checkInDateTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }
}

class AttendanceStats {
  final int totalWorkingDays;
  final int daysPresent;
  final int lateDays;
  final int leaveDays;
  final double punctualityRate;
  final double totalHoursWorked;

  AttendanceStats({
    required this.totalWorkingDays,
    required this.daysPresent,
    required this.lateDays,
    required this.leaveDays,
    required this.punctualityRate,
    required this.totalHoursWorked,
  });

  factory AttendanceStats.empty() {
    return AttendanceStats(
      totalWorkingDays: 26,
      daysPresent: 0,
      lateDays: 0,
      leaveDays: 0,
      punctualityRate: 100.0,
      totalHoursWorked: 0.0,
    );
  }
}

class AttendanceRepository {
  static final AttendanceRepository _instance = AttendanceRepository._internal();
  factory AttendanceRepository() => _instance;
  AttendanceRepository._internal();

  SupabaseClient get _client => Supabase.instance.client;

  static const String _cacheKeyPrefix = 'attendance_logs_cache_';
  static const String _todayPunchPrefix = 'today_punch_cache_';

  // Fetch today's attendance record
  Future<AttendanceRecord?> getTodayAttendance(String userId) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final rows = await _client
          .from('staff_attendance')
          .select()
          .eq('auth_id', userId)
          .or('date.eq.$todayStr,created_at.gte.${todayStr}T00:00:00')
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final record = AttendanceRecord.fromMap(rows.first);
        await _saveTodayCache(userId, record);
        return record;
      }
    } catch (e) {
      debugPrint('Supabase getTodayAttendance fallback to local cache: $e');
    }

    // Fallback to local cache
    return _getTodayCache(userId);
  }

  // Fetch entire attendance history
  Future<List<AttendanceRecord>> getAttendanceHistory(String userId, {int limit = 60}) async {
    try {
      final rows = await _client
          .from('staff_attendance')
          .select()
          .eq('auth_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      if (rows.isNotEmpty) {
        final list = (rows as List).map((r) => AttendanceRecord.fromMap(r)).toList();
        await _saveHistoryCache(userId, list);
        return list;
      }
    } catch (e) {
      debugPrint('Supabase getAttendanceHistory fallback to local: $e');
    }

    // Return local cache if present, otherwise empty list
    final cached = await _getHistoryCache(userId);
    return cached;
  }

  // Calculate monthly stats from history
  AttendanceStats calculateStats(List<AttendanceRecord> records) {
    if (records.isEmpty) return AttendanceStats.empty();

    final now = DateTime.now();
    final currentMonthRecords = records.where((r) {
      if (r.checkInDateTime != null) {
        return r.checkInDateTime!.month == now.month && r.checkInDateTime!.year == now.year;
      }
      return r.date.startsWith(DateFormat('yyyy-MM').format(now));
    }).toList();

    final daysPresent = currentMonthRecords.length;
    final onTimeCount = currentMonthRecords.where((r) => r.isOnTime).length;
    final lateCount = daysPresent - onTimeCount;
    final totalWorkingDaysTillToday = now.day;
    final leaveDays = (totalWorkingDaysTillToday > daysPresent) ? (totalWorkingDaysTillToday - daysPresent) : 0;
    final punctualityRate = daysPresent > 0 ? ((onTimeCount / daysPresent) * 100).clamp(0.0, 100.0) : 100.0;

    double totalHours = 0;
    for (var r in currentMonthRecords) {
      if (r.checkInDateTime != null) {
        final end = r.checkOutDateTime ?? (r.date == DateFormat('yyyy-MM-dd').format(now) ? now : r.checkInDateTime!.add(const Duration(hours: 8)));
        final diff = end.difference(r.checkInDateTime!).inMinutes;
        if (diff > 0) totalHours += (diff / 60.0);
      } else {
        totalHours += 8.0;
      }
    }

    return AttendanceStats(
      totalWorkingDays: 26,
      daysPresent: daysPresent,
      lateDays: lateCount,
      leaveDays: leaveDays,
      punctualityRate: punctualityRate > 0 ? double.parse(punctualityRate.toStringAsFixed(1)) : 100.0,
      totalHoursWorked: double.parse(totalHours.toStringAsFixed(1)),
    );
  }

  // Punch In
  Future<AttendanceRecord> recordPunchIn({
    required String userId,
    required String staffName,
    File? selfiePhoto,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final isOnTime = now.hour < 7 || (now.hour == 7 && now.minute <= 15);
    final finalLat = latitude ?? 13.4188;
    final finalLng = longitude ?? 80.3192;
    final finalLoc = locationLabel ?? 'Pazhaverkadu Hub (${finalLat.toStringAsFixed(3)}°N, ${finalLng.toStringAsFixed(3)}°E)';

    String? photoUrl;
    if (selfiePhoto != null) {
      try {
        final cleanId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final fileName = 'punch_in_${cleanId}_${now.millisecondsSinceEpoch}.jpg';
        final bytes = await selfiePhoto.readAsBytes();
        var uploadBytes = bytes;

        try {
          final compressed = await FlutterImageCompress.compressWithList(
            bytes,
            minWidth: 700,
            minHeight: 700,
            quality: 60,
            format: CompressFormat.jpeg,
          );
          if (compressed.isNotEmpty) {
            uploadBytes = Uint8List.fromList(compressed);
          }
        } catch (_) {}

        await _client.storage.from('staff-checkins').uploadBinary(
          fileName,
          uploadBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '3600', upsert: true),
        );
        photoUrl = _client.storage.from('staff-checkins').getPublicUrl(fileName);
      } catch (e) {
        debugPrint('Storage punch upload notice: $e');
      }
    }

    final nowTimeFmt = DateFormat('hh:mm a').format(now);

    final payload = {
      'auth_id': userId,
      'staff_name': staffName,
      'date': dateStr,
      'shift_window': '07:00 AM - 05:00 PM',
      'check_in_time': now.toIso8601String(),
      'status': isOnTime ? 'ON TIME' : 'PRESENT',
      'is_on_time': isOnTime,
      'photo_url': photoUrl,
      'live_photo_url': photoUrl,
      'latitude': finalLat,
      'longitude': finalLng,
      'location_name': finalLoc,
      'created_at': now.toIso8601String(),
    };

    String generatedId = 'att_${now.millisecondsSinceEpoch}';
    try {
      final res = await _client.from('staff_attendance').insert(payload).select().maybeSingle();
      if (res != null && res['id'] != null) {
        generatedId = res['id'].toString();
      }

      await _client.from('manager_activity_logs').insert({
        'staff_name': staffName,
        'event_type': 'shift_start',
        'description': 'Morning shift attendance clocked in ($nowTimeFmt)',
        'photo_url': photoUrl,
        'location_lat': finalLat,
        'location_lng': finalLng,
      });
    } catch (e) {
      debugPrint('Supabase punch in DB notice: $e');
    }

    final record = AttendanceRecord(
      id: generatedId,
      authId: userId,
      staffName: staffName,
      date: dateStr,
      checkInDateTime: now,
      checkInTimeFormatted: nowTimeFmt,
      status: isOnTime ? 'ON TIME' : 'PRESENT',
      isOnTime: isOnTime,
      photoUrl: photoUrl,
      latitude: finalLat,
      longitude: finalLng,
      locationName: finalLoc,
      shiftWindow: '07:00 AM - 05:00 PM',
    );

    await _saveTodayCache(userId, record);
    return record;
  }

  // Punch Out
  Future<AttendanceRecord> recordPunchOut({
    required AttendanceRecord todayRecord,
    required String userId,
    required String staffName,
    double? latitude,
    double? longitude,
  }) async {
    final now = DateTime.now();
    final nowTimeFmt = DateFormat('hh:mm a').format(now);
    final durationStr = todayRecord.checkInDateTime != null ? '${now.difference(todayRecord.checkInDateTime!).inHours}h ${now.difference(todayRecord.checkInDateTime!).inMinutes.remainder(60)}m' : '8h 00m';

    try {
      await _client.from('staff_attendance').update({
        'check_out_time': now.toIso8601String(),
        'status': 'COMPLETED',
      }).eq('id', todayRecord.id);

      await _client.from('manager_activity_logs').insert({
        'staff_name': staffName,
        'event_type': 'shift_end',
        'description': 'Shift completed - Punch Out ($nowTimeFmt, Working Hours: $durationStr)',
        'location_lat': latitude ?? 13.4188,
        'location_lng': longitude ?? 80.3192,
      });
    } catch (e) {
      debugPrint('Supabase punch out DB notice: $e');
    }

    final updated = AttendanceRecord(
      id: todayRecord.id,
      authId: todayRecord.authId,
      staffName: todayRecord.staffName,
      date: todayRecord.date,
      checkInDateTime: todayRecord.checkInDateTime,
      checkOutDateTime: now,
      checkInTimeFormatted: todayRecord.checkInTimeFormatted,
      checkOutTimeFormatted: nowTimeFmt,
      status: 'COMPLETED',
      isOnTime: todayRecord.isOnTime,
      photoUrl: todayRecord.photoUrl,
      latitude: latitude ?? todayRecord.latitude,
      longitude: longitude ?? todayRecord.longitude,
      locationName: todayRecord.locationName,
      shiftWindow: todayRecord.shiftWindow,
    );

    await _saveTodayCache(userId, updated);
    return updated;
  }

  // --- Local Cache Helpers ---
  Future<void> _saveTodayCache(String userId, AttendanceRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_todayPunchPrefix$userId', jsonEncode(record.toMap()));
    } catch (_) {}
  }

  Future<AttendanceRecord?> _getTodayCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('$_todayPunchPrefix$userId');
      if (str != null && str.isNotEmpty) {
        final map = jsonDecode(str) as Map<String, dynamic>;
        final record = AttendanceRecord.fromMap(map);
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        if (record.date == todayStr) {
          return record;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveHistoryCache(String userId, List<AttendanceRecord> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = records.map((e) => e.toMap()).toList();
      await prefs.setString('$_cacheKeyPrefix$userId', jsonEncode(list));
    } catch (_) {}
  }

  Future<List<AttendanceRecord>> _getHistoryCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('$_cacheKeyPrefix$userId');
      if (str != null && str.isNotEmpty) {
        final list = jsonDecode(str) as List;
        return list.map((e) => AttendanceRecord.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }
}
