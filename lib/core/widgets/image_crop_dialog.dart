import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';

class ImageCropDialog extends StatefulWidget {
  final File imageFile;
  final String bucketName;
  final String title;

  const ImageCropDialog({
    super.key,
    required this.imageFile,
    this.bucketName = 'fish-images',
    this.title = 'Crop & Adjust Photo',
  });

  /// Helper static launcher that handles image picking, cropping dialog, and storage upload
  static Future<String?> pickCropAndUpload({
    required BuildContext context,
    required ImageSource source,
    String bucketName = 'fish-images',
    String title = 'Crop & Adjust Photo',
  }) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );

      if (picked == null) return null;

      if (!context.mounted) return null;

      final croppedUrl = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => ImageCropDialog(
          imageFile: File(picked.path),
          bucketName: bucketName,
          title: title,
        ),
      );

      return croppedUrl;
    } catch (e) {
      debugPrint('Pick & Crop error: $e');
      return null;
    }
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformCtrl = TransformationController();
  late File _currentFile;
  int _rotationQuarterTurns = 0;
  bool _isUploading = false;
  BoxFit _imageFit = BoxFit.cover;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.imageFile;
  }

  Future<void> _pickAnotherImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );
      if (picked != null) {
        AppHaptics.mediumImpact();
        setState(() {
          _currentFile = File(picked.path);
          _rotationQuarterTurns = 0;
          _imageFit = BoxFit.cover;
          _transformCtrl.value = Matrix4.identity();
        });
      }
    } catch (e) {
      debugPrint('Pick another image notice: $e');
    }
  }

  Future<void> _confirmAndUpload() async {
    setState(() => _isUploading = true);
    AppHaptics.mediumImpact();

    try {
      final boundary = _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not capture crop boundary');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert image bytes');
      }
      final rawBytes = byteData.buffer.asUint8List();

      // Compress to high-efficiency JPEG (800x800, quality 82, ~80KB-120KB)
      Uint8List uploadBytes = rawBytes;
      String contentType = 'image/jpeg';
      String ext = 'jpg';

      try {
        final compressed = await FlutterImageCompress.compressWithList(
          rawBytes,
          minWidth: 800,
          minHeight: 800,
          quality: 82,
          format: CompressFormat.jpeg,
        );
        if (compressed.isNotEmpty) {
          uploadBytes = Uint8List.fromList(compressed);
        }
      } catch (compErr) {
        debugPrint('Image compression notice: $compErr');
      }

      final fileName = 'crop_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final db = Supabase.instance.client;

      await db.storage.from(widget.bucketName).uploadBinary(
            fileName,
            uploadBytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );

      final publicUrl = db.storage.from(widget.bucketName).getPublicUrl(fileName);
      SoundService().playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        Navigator.pop(context, publicUrl);
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload cropped image: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void _rotateImage() {
    AppHaptics.lightImpact();
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _toggleFit() {
    AppHaptics.lightImpact();
    setState(() {
      _imageFit = _imageFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
      _transformCtrl.value = Matrix4.identity();
    });
  }

  void _resetTransform() {
    AppHaptics.lightImpact();
    _transformCtrl.value = Matrix4.identity();
    setState(() {
      _rotationQuarterTurns = 0;
      _imageFit = BoxFit.cover;
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cropSize = screenSize.width * 0.84;

    return Container(
      color: Colors.white, // COMPLETE 100% PURE WHITE THEME
      child: SafeArea(
        child: Column(
          children: [
            // 1. TOP HEADER (ZERO OVERFLOW, PURE WHITE)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF0F172A), size: 22),
                    onPressed: _isUploading
                        ? null
                        : () {
                            AppHaptics.lightImpact();
                            Navigator.pop(context, null);
                          },
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Pinch to zoom • Drag to frame',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 20),
                    tooltip: 'Reset Frame',
                    onPressed: _isUploading ? null : _resetTransform,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            const Spacer(),

            // 2. INTERACTIVE CROP VIEWPORT WITH 3x3 GRID (PURE WHITE CARD FRAME)
            Center(
              child: Container(
                width: cropSize,
                height: cropSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF059669), width: 2.2),
                  color: const Color(0xFFF8FAFC),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Image Viewer Repaint Boundary
                      Positioned.fill(
                        child: RepaintBoundary(
                          key: _cropKey,
                          child: Container(
                            color: const Color(0xFFF1F5F9),
                            child: RotatedBox(
                              quarterTurns: _rotationQuarterTurns,
                              child: InteractiveViewer(
                                transformationController: _transformCtrl,
                                minScale: 0.7,
                                maxScale: 4.5,
                                boundaryMargin: const EdgeInsets.all(double.infinity),
                                child: Center(
                                  child: Image.file(
                                    _currentFile,
                                    fit: _imageFit,
                                    width: cropSize,
                                    height: cropSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Rule of Thirds Grid Overlay
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _CropGridPainter(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 3. EDIT & DIRECT IMAGE CHANGE CONTROLS (ROW OF CLEAN WHITE BUTTONS)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildPillButton(
                    icon: Icons.rotate_right_rounded,
                    label: 'Rotate 90°',
                    color: const Color(0xFF2563EB),
                    onTap: _isUploading ? null : _rotateImage,
                  ),
                  _buildPillButton(
                    icon: _imageFit == BoxFit.cover ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                    label: _imageFit == BoxFit.cover ? 'Fill Mode' : 'Fit Mode',
                    color: const Color(0xFF0F172A),
                    onTap: _isUploading ? null : _toggleFit,
                  ),
                  _buildPillButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Retake',
                    color: const Color(0xFF059669),
                    onTap: _isUploading ? null : () => _pickAnotherImage(ImageSource.camera),
                  ),
                  _buildPillButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: const Color(0xFF7C3AED),
                    onTap: _isUploading ? null : () => _pickAnotherImage(ImageSource.gallery),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // 4. BOTTOM ACTION BAR (100% PURE WHITE THEME)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.2)),
              ),
              child: Row(
                children: [
                  // Exit / Cancel Button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        backgroundColor: const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isUploading
                          ? null
                          : () {
                              AppHaptics.lightImpact();
                              Navigator.pop(context, null);
                            },
                      child: Text(
                        'CANCEL',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Confirm & Crop Button
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _isUploading ? null : _confirmAndUpload,
                      child: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 17, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  'CONFIRM & USE',
                                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7.5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter for rule-of-thirds framing grid
class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double w1 = size.width / 3;
    final double w2 = size.width * 2 / 3;
    final double h1 = size.height / 3;
    final double h2 = size.height * 2 / 3;

    // Vertical grid lines
    canvas.drawLine(Offset(w1, 0), Offset(w1, size.height), paint);
    canvas.drawLine(Offset(w2, 0), Offset(w2, size.height), paint);

    // Horizontal grid lines
    canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint);
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
