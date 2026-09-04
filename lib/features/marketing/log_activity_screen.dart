import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';

class LogActivityScreen extends ConsumerStatefulWidget {
  const LogActivityScreen({super.key});

  @override
  ConsumerState<LogActivityScreen> createState() => _LogActivityScreenState();
}

class _LogActivityScreenState extends ConsumerState<LogActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  String _activityType = 'area_visit';
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  final SoundService _soundService = SoundService();

  final List<DropdownMenuItem<String>> _activityTypes = const [
    DropdownMenuItem(value: 'area_visit', child: Text('Area Visit')),
    DropdownMenuItem(value: 'promotion', child: Text('Promotion / Campaign')),
    DropdownMenuItem(value: 'new_customer', child: Text('New Customer Onboarding')),
    DropdownMenuItem(value: 'vendor_visit', child: Text('Vendor / Merchant Visit')),
  ];

  @override
  void dispose() {
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    AppHaptics.mediumImpact();

    try {
      final db = Supabase.instance.client;
      final authState = ref.read(authNotifierProvider);
      final profile = authState.staffProfile;
      final staffName = profile?['name'] ?? 'Marketing Executive';
      final staffDbId = profile?['id']?.toString();
      final isUuid = staffDbId != null && RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(staffDbId);

      await db.from('marketing_activities').insert({
        'activity_type': _activityType,
        'location': _locationController.text.trim(),
        'notes': _notesController.text.trim(),
        'staff_name': staffName,
        if (isUuid) 'exec_id': staffDbId,
        'branch_location': profile?['branch_location'] ?? 'Pulicat Central Store',
        'created_at': DateTime.now().toIso8601String(),
      });

      _soundService.playSuccessChime();
      AppHaptics.success();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Activity logged to Supabase successfully!', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error inserting marketing activity: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notice: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  String? clientUserId() => Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            AppHaptics.selectionClick();
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Log Marketing Activity',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16.5, color: const Color(0xFF0F172A)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVITY DETAILS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _activityType,
                      decoration: InputDecoration(
                        labelText: 'Activity Type',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      items: _activityTypes,
                      onChanged: (value) {
                        if (value != null) {
                          AppHaptics.selectionClick();
                          setState(() => _activityType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Location / Area',
                        hintText: 'e.g. Pulicat Beach Road, Minjur Market',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFFD97706), size: 20),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a location';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Notes / Outcomes',
                        hintText: 'e.g. Distributed pamphlets, onboarded 3 new customers...',
                        alignLabelWithHint: true,
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 20),
                  label: Text(
                    _isSubmitting ? 'SAVING TO SUPABASE...' : 'SAVE ACTIVITY',
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
