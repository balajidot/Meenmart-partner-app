import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/sound_service.dart';

class MeenMartOnboardingScreen extends ConsumerStatefulWidget {
  const MeenMartOnboardingScreen({super.key});

  @override
  ConsumerState<MeenMartOnboardingScreen> createState() => _MeenMartOnboardingScreenState();
}

class _MeenMartOnboardingScreenState extends ConsumerState<MeenMartOnboardingScreen> {
  int _currentStep = 1; // 1: Select Store, 2: Select Shift/Role, 3: ID Verification, 4: Complete
  final ImagePicker _picker = ImagePicker();

  // Form selections
  int _selectedStoreIndex = 0;
  int _selectedShiftIndex = 0;
  final _aadhaarCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  File? _selfieFile;
  bool _isLoading = false;

  final List<Map<String, String>> _stores = [
    {
      'name': 'Pulicat Central Store ES01',
      'distance': '0.5 km',
      'address': 'No. 12/A, Sea Shore Road, Pazhaverkadu, Tiruvallur, Tamil Nadu 601205',
      'is_recommended': 'true',
    },
    {
      'name': 'Ponneri Hub Store ES02',
      'distance': '14 km',
      'address': 'No. 45, Main Market Road, Ponneri Town, TN 601204',
      'is_recommended': 'true',
    },
    {
      'name': 'Minjur Operational Hub ES03',
      'distance': '22 km',
      'address': 'Plot 88, Station Road, Minjur Industrial Zone, TN 601203',
      'is_recommended': 'false',
    },
  ];

  final List<Map<String, String>> _shifts = [
    {
      'title': 'Morning Store Operations Shift',
      'timing': '07:00 AM - 05:00 PM',
      'desc': 'Fresh Fish Arrival, Weight Confirmation & Order Packing',
      'icon': '☀️',
    },
    {
      'title': 'Evening Delivery & Logistics Shift',
      'timing': '02:00 PM - 10:00 PM',
      'desc': 'Express Customer Delivery & Doorstep Drop-Off',
      'icon': '🛵',
    },
    {
      'title': 'Marketing & Vendor Onboarding Shift',
      'timing': '09:00 AM - 06:00 PM',
      'desc': 'Area Visits, Merchant Acquisition & Marketing Reports',
      'icon': '📊',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  void _loadProfileData() {
    final profile = ref.read(authNotifierProvider).staffProfile;
    if (profile != null) {
      _nameCtrl.text = profile['name'] ?? '';
      _phoneCtrl.text = profile['phone'] ?? '';
      _upiCtrl.text = profile['upi_id'] ?? '';
    }
  }

  Future<void> _takeSelfie() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 80,
      );
      if (photo != null && mounted) {
        setState(() {
          _selfieFile = File(photo.path);
        });
      }
    } catch (e) {
      debugPrint('Selfie picker notice: $e');
    }
  }

  Future<void> _submitOnboarding() async {
    setState(() => _isLoading = true);
    AppHaptics.mediumImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      if (userId != null) {
        String? selfieUrl;
        if (_selfieFile != null) {
          final filename = 'onboarding_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          try {
            await client.storage.from('staff-checkins').upload(
                  filename,
                  _selfieFile!,
                  fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
                );
            selfieUrl = client.storage.from('staff-checkins').getPublicUrl(filename);
          } catch (stErr) {
            debugPrint('Storage notice: $stErr');
          }
        }

        final selectedStore = _stores[_selectedStoreIndex]['name'];
        final selectedShift = _shifts[_selectedShiftIndex]['timing'];

        final Map<String, dynamic> updateData = {
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'branch_location': selectedStore,
          'shift_timing': selectedShift,
          'upi_id': _upiCtrl.text.trim(),
          'status': 'active',
        };

        if (selfieUrl != null) {
          updateData['avatar_url'] = selfieUrl;
        }

        await client.from('store_staff').update(updateData).eq('auth_id', userId);
        await ref.read(authNotifierProvider.notifier).refreshProfile();
      }

      SoundService().playSuccessChime();

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 MeenMart Partner Onboarding Complete! Profile Active.'),
            backgroundColor: Color(0xFF059669),
          ),
        );
        context.go('/store-dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Onboarding notice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepProgress = _currentStep / 3.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            AppHaptics.selectionClick();
            if (_currentStep > 1) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _currentStep == 1
              ? 'Select store'
              : _currentStep == 2
                  ? 'Select shift & role'
                  : 'Submit ID verification',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                value: stepProgress,
                backgroundColor: const Color(0xFFE2E8F0),
                color: const Color(0xFF8B5CF6),
                strokeWidth: 3.5,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // STEP 1: SELECT STORE
                        if (_currentStep == 1) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: Color(0xFF059669), size: 22),
                                const SizedBox(width: 10),
                                Text('Search stores in Tiruvallur / Chennai', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13.5)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          _buildYellowVideoBanner(
                            title: 'How to Select Store?',
                            duration: '1m 5s',
                            illustrationIcon: Icons.storefront_rounded,
                          ),
                          const SizedBox(height: 20),

                          Text(
                            'NEARBY STORES IN TIRUVALLUR & CHENNAI',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF64748B), letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 12),

                          ...List.generate(_stores.length, (idx) {
                            final st = _stores[idx];
                            final isSel = _selectedStoreIndex == idx;
                            return GestureDetector(
                              onTap: () {
                                AppHaptics.selectionClick();
                                setState(() => _selectedStoreIndex = idx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFECFDF5) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                                    width: isSel ? 1.8 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (st['is_recommended'] == 'true') ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D9488),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                                            const SizedBox(width: 3),
                                            Text('Recommended', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${st['name']} • ${st['distance']}',
                                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                                          ),
                                        ),
                                        Icon(
                                          isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                          color: isSel ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '"${st['address']}"',
                                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],

                        // STEP 2: SELECT SHIFT / ROLE
                        if (_currentStep == 2) ...[
                          _buildYellowVideoBanner(
                            title: 'How to Choose Your Shift?',
                            duration: '0m 48s',
                            illustrationIcon: Icons.two_wheeler_rounded,
                          ),
                          const SizedBox(height: 20),

                          Text(
                            'AVAILABLE WORK SHIFTS',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF64748B), letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 12),

                          ...List.generate(_shifts.length, (idx) {
                            final sh = _shifts[idx];
                            final isSel = _selectedShiftIndex == idx;
                            return GestureDetector(
                              onTap: () {
                                AppHaptics.selectionClick();
                                setState(() => _selectedShiftIndex = idx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFECFDF5) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                                    width: isSel ? 1.8 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(sh['icon']!, style: const TextStyle(fontSize: 26)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(sh['title']!, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
                                          const SizedBox(height: 2),
                                          Text('🕒 ${sh['timing']}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
                                          Text(sh['desc']!, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                      color: isSel ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],

                        // STEP 3: ID VERIFICATION & SELFIE
                        if (_currentStep == 3) ...[
                          _buildYellowVideoBanner(
                            title: 'How to Verify Government ID?',
                            duration: '1m 15s',
                            illustrationIcon: Icons.badge_rounded,
                          ),
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('ID verification time', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                                      Text('Without ID Verification', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Instant', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
                                    Text('2-3 days', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          Text('Staff Name & Phone', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(hintText: 'Enter Full Name'),
                          ),
                          const SizedBox(height: 14),
                          Text('Aadhaar / Government ID Number', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _aadhaarCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'Enter 12-digit Aadhaar number'),
                          ),
                          const SizedBox(height: 14),
                          Text('Payout UPI ID (GPay/PhonePe)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _upiCtrl,
                            decoration: const InputDecoration(hintText: 'e.g. name@okaxis'),
                          ),
                          const SizedBox(height: 20),

                          Center(
                            child: GestureDetector(
                              onTap: _takeSelfie,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF059669), width: 1.8),
                                ),
                                child: _selfieFile != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.file(_selfieFile!, fit: BoxFit.cover),
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.camera_alt_rounded, color: Color(0xFF059669), size: 32),
                                          const SizedBox(height: 6),
                                          Text('LIVE SELFIE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF059669))),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text('Help', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B050),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            AppHaptics.selectionClick();
                            if (_currentStep < 3) {
                              setState(() => _currentStep++);
                            } else {
                              _submitOnboarding();
                            }
                          },
                          child: Text(
                            _currentStep == 3 ? 'Verify & Complete Setup' : 'Next',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900),
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

  Widget _buildYellowVideoBanner({
    required String title,
    required String duration,
    required IconData illustrationIcon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    duration,
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(illustrationIcon, size: 36, color: const Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF059669), size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
