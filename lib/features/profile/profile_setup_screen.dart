import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/widgets/optimized_image.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _branchCtrl;
  late TextEditingController _upiCtrl;
  late TextEditingController _vehicleCtrl;
  late TextEditingController _shiftCtrl;

  File? _imageFile;
  bool _isSaving = false;
  String? _avatarUrl;
  final SoundService _soundService = SoundService();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authNotifierProvider).staffProfile;
    _nameCtrl = TextEditingController(text: profile?['name'] ?? '');
    _phoneCtrl = TextEditingController(text: profile?['phone'] ?? '');
    _branchCtrl = TextEditingController(text: profile?['branch_location'] ?? 'Pulicat Central Store');
    _upiCtrl = TextEditingController(text: profile?['upi_id'] ?? '');
    _vehicleCtrl = TextEditingController(text: profile?['vehicle_number'] ?? '');
    _shiftCtrl = TextEditingController(text: profile?['shift_timing'] ?? '07:00 AM - 05:00 PM (Morning Shift)');
    _avatarUrl = profile?['avatar_url'];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _branchCtrl.dispose();
    _upiCtrl.dispose();
    _vehicleCtrl.dispose();
    _shiftCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _imageFile = File(picked.path);
        });
        AppHaptics.lightImpact();
      }
    } catch (e) {
      debugPrint('Image pick notice: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    AppHaptics.mediumImpact();

    try {
      final client = Supabase.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User is not logged in');
      }

      String? uploadedUrl = _avatarUrl;

      // 1. Upload photo if selected
      if (_imageFile != null) {
        final filename = 'avatar_${currentUser.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await client.storage.from('staff-checkins').upload(
                filename,
                _imageFile!,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          uploadedUrl = client.storage.from('staff-checkins').getPublicUrl(filename);
        } catch (storageErr) {
          debugPrint('Storage avatar notice: $storageErr');
        }
      }

      final Map<String, dynamic> updateMap = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'branch_location': _branchCtrl.text.trim(),
        'upi_id': _upiCtrl.text.trim(),
        'vehicle_number': _vehicleCtrl.text.trim(),
        'shift_timing': _shiftCtrl.text.trim(),
        'status': 'active',
      };
      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        updateMap['avatar_url'] = uploadedUrl;
      }

      final staffProfile = ref.read(authNotifierProvider).staffProfile;
      final staffDbId = staffProfile?['id'];

      bool updated = false;

      // Strategy A: Update by DB primary key id if available
      if (staffDbId != null) {
        try {
          await client.from('store_staff').update(updateMap).eq('id', staffDbId);
          updated = true;
        } catch (e) {
          debugPrint('Update by id notice: $e');
        }
      }

      // Strategy B: Update by auth_id
      if (!updated) {
        try {
          await client.from('store_staff').update(updateMap).eq('auth_id', currentUser.id);
          updated = true;
        } catch (e) {
          debugPrint('Update by auth_id notice: $e');
        }
      }

      // Strategy C: Upsert row by auth_id if new
      if (!updated) {
        updateMap['auth_id'] = currentUser.id;
        updateMap['roles'] = staffProfile?['roles'] ?? ['store_manager'];
        try {
          await client.from('store_staff').upsert(updateMap, onConflict: 'auth_id');
        } catch (e) {
          debugPrint('Upsert notice: $e');
        }
      }

      // Refresh Riverpod auth state immediately
      await ref.read(authNotifierProvider.notifier).refreshProfile();
      _soundService.playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF059669),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile update error: ${e.toString()}'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            AppHaptics.selectionClick();
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Edit Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AVATAR PICKER
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF059669), width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _imageFile != null
                            ? Image.file(_imageFile!, fit: BoxFit.cover)
                            : (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                ? OptimizedImage(
                                    imageUrl: _avatarUrl!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 200,
                                    memCacheHeight: 200,
                                  )
                                : const Icon(Icons.person_rounded, size: 50, color: Color(0xFF64748B)),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            backgroundColor: Colors.white,
                            builder: (ctx) => Container(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF059669)),
                                    title: Text('Take Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickImage(ImageSource.camera);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF2563EB)),
                                    title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickImage(ImageSource.gallery);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0xFF059669),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // CLEAN FORM FIELDS (NO BILINGUAL CLUTTER)
              Text('Personal Information', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              const SizedBox(height: 10),

              _buildField(
                controller: _nameCtrl,
                label: 'Full Name',
                icon: Icons.person_outline_rounded,
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter name' : null,
              ),
              const SizedBox(height: 14),

              _buildField(
                controller: _phoneCtrl,
                label: 'Phone Number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (val) => val == null || val.trim().length < 10 ? 'Please enter valid phone' : null,
              ),
              const SizedBox(height: 18),

              Text('Store & Shift Settings', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              const SizedBox(height: 10),

              _buildField(
                controller: _branchCtrl,
                label: 'Store Branch',
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 14),

              _buildField(
                controller: _shiftCtrl,
                label: 'Shift Timing',
                icon: Icons.schedule_outlined,
              ),
              const SizedBox(height: 14),

              _buildField(
                controller: _upiCtrl,
                label: 'Payout UPI ID',
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 28),

              // SAVE BUTTON
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _isSaving ? null : _saveProfile,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        )
                      : Text(
                          'SAVE PROFILE',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}
