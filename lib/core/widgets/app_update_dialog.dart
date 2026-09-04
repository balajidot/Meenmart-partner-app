import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update_info.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo updateInfo) async {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (ctx) => PopScope(
        canPop: !updateInfo.isForceUpdate,
        child: AppUpdateDialog(updateInfo: updateInfo),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  bool _isReadyToInstall = false;
  File? _downloadedFile;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startNativeInAppDownload() async {
    AppHaptics.heavyImpact();
    SoundService().playSuccessChime();

    final urlStr = widget.updateInfo.apkUrl.trim();
    if (urlStr.isEmpty) {
      setState(() {
        _errorMessage = 'APK Download URL is not configured in Supabase.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _isReadyToInstall = false;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorMessage = null;
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(urlStr));
      final response = await client.send(request);

      if (response.statusCode >= 400) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }

      _totalBytes = response.contentLength ?? (26 * 1024 * 1024); // Fallback estimate ~26MB

      // Use External Cache Directory so Android Package Installer can access the APK without sandbox restrictions
      Directory? baseDir;
      if (Platform.isAndroid) {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          baseDir = extDirs.first;
        }
      }
      baseDir ??= await getTemporaryDirectory();

      final file = File('${baseDir.path}/meenmart_store_update.apk');
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        _receivedBytes += chunk.length;
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _progress = _totalBytes > 0 ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0) : 0.5;
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (mounted) {
        AppHaptics.heavyImpact();
        SoundService().playSuccessChime();

        setState(() {
          _isDownloading = false;
          _isReadyToInstall = true;
          _downloadedFile = file;
        });

        // Automatically trigger Android System Package Installer
        await _installApk(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download error: $e';
        });
      }
    }
  }

  Future<void> _installApk(File file) async {
    try {
      AppHaptics.heavyImpact();

      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'APK file not found. Please download again.';
          _isReadyToInstall = false;
        });
        return;
      }

      // Check and request Android Install Unknown Apps permission
      if (Platform.isAndroid) {
        final installPermissionStatus = await Permission.requestInstallPackages.status;
        if (!installPermissionStatus.isGranted) {
          final requestResult = await Permission.requestInstallPackages.request();
          if (!requestResult.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'அப்டேட் நிறுவ "Allow from this source" அனுமதியை இயக்கவும் (Enable Install Permission in Settings).',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  backgroundColor: const Color(0xFFDC2626),
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'SETTINGS',
                    textColor: Colors.white,
                    onPressed: () => openAppSettings(),
                  ),
                ),
              );
            }
            return;
          }
        }
      }

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Installer status: ${result.message}. நீங்கள் மேலேயுள்ள பட்டனைத் தொட்டு மீண்டும் முயற்சிக்கலாம்.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFFD97706),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installation error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _fallbackBrowserDownload() async {
    final uri = Uri.parse(widget.updateInfo.apkUrl.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notice: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForce = widget.updateInfo.isForceUpdate;
    final downloadedMb = (_receivedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = _totalBytes > 0 ? (_totalBytes / (1024 * 1024)).toStringAsFixed(1) : '26.8';
    final percentage = (_progress * 100).toInt();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top App Logo with Rocket Badge
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/icons/store_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.system_update_rounded,
                      size: 40,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isForce ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      _isDownloading ? Icons.cloud_download_rounded : Icons.rocket_launch_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Title in Tamil & English
            Text(
              widget.updateInfo.titleTa.isNotEmpty ? widget.updateInfo.titleTa : 'புதிய அப்டேட் வந்துள்ளது! 🚀',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.updateInfo.titleEn.isNotEmpty ? widget.updateInfo.titleEn : 'New Version Available',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),

            // Version Transition Pill (e.g. v2.0.0 → v2.1.0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'v${widget.updateInfo.currentVersionName}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF059669)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'v${widget.updateInfo.latestVersionName}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // DOWNLOADING STATE VIEW
            if (_isDownloading) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'பதிவிறக்கம் ஆகிறது...',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$percentage%',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFDCFCE7),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$downloadedMb MB / $totalMb MB',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                        Text(
                          percentage >= 100 ? 'நிறுவப்படுகிறது...' : 'நொடியில் முடியும்',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF65A30D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              // Release Notes Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded, size: 16, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Text(
                          'என்னென்ன புதியவை (What\'s New):',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.updateInfo.descTa,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: const Color(0xFF475569),
                      ),
                    ),
                    if (widget.updateInfo.descEn.isNotEmpty && widget.updateInfo.descEn != widget.updateInfo.descTa) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.updateInfo.descEn,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          height: 1.35,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Error notice if download failed
            if (_errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Mandatory Notice if Force Update is ON
            if (isForce && !_isDownloading) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'கட்டாயப் புதுப்பித்தல்: ஆப்பைத் தொடர்ந்து பயன்படுத்த உடனே புதுப்பிக்கவும்.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 1-Click Update Now / Install Primary Button
            if (!_isDownloading) ...[
              if (_isReadyToInstall && _downloadedFile != null) ...[
                // READY TO INSTALL BUTTON (Prominent Emerald Green)
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _installApk(_downloadedFile!),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.install_mobile_rounded, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'இப்போதே நிறுவுக (INSTALL UPDATE NOW)',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'டவுன்லோட் முடிந்தது. இன்ஸ்டாலர் தானாகத் திறக்காவிட்டால் மேலே தொடவும்.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF059669),
                  ),
                ),
                const SizedBox(height: 2),
                TextButton.icon(
                  onPressed: _startNativeInAppDownload,
                  icon: const Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF64748B)),
                  label: Text(
                    'மீண்டும் டவுன்லோட் செய்க (Re-download)',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ] else ...[
                // START DOWNLOAD BUTTON
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF047857)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _startNativeInAppDownload,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'இப்போதே புதுப்பிக்கவும் (UPDATE NOW)',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],

            // Browser Fallback (Available when download completes, fails, or needed)
            if (_errorMessage != null || _isReadyToInstall) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _fallbackBrowserDownload,
                icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Color(0xFF059669)),
                label: Text(
                  'Browser-ல் பதிவிறக்க (Open in Browser)',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF059669),
                  ),
                ),
              ),
            ],

            // Optional "Later / பிறகு" button if not force update and not currently downloading
            if (!isForce && !_isDownloading) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    AppHaptics.selectionClick();
                    Navigator.pop(context);
                  },
                  child: Text(
                    'பிறகு (LATER)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
