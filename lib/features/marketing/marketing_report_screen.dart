import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';

class MarketingReportScreen extends StatefulWidget {
  const MarketingReportScreen({super.key});

  @override
  State<MarketingReportScreen> createState() => _MarketingReportScreenState();
}

class _MarketingReportScreenState extends State<MarketingReportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _fetchActivities();
  }

  Future<void> _fetchActivities() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('marketing_activities')
          .select('*')
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _activities = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching marketing activities: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatType(String type) {
    switch (type) {
      case 'area_visit':
        return 'Area Visit';
      case 'promotion':
        return 'Promotion / Campaign';
      case 'new_customer':
        return 'New Customer Onboarding';
      case 'vendor_visit':
        return 'Vendor Visit';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'area_visit':
        return Icons.map_rounded;
      case 'promotion':
        return Icons.campaign_rounded;
      case 'new_customer':
        return Icons.person_add_alt_1_rounded;
      case 'vendor_visit':
        return Icons.storefront_rounded;
      default:
        return Icons.event_note_rounded;
    }
  }

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
          'Marketing Activity Report',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16.5, color: const Color(0xFF0F172A)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            tooltip: 'Refresh',
            onPressed: () {
              AppHaptics.selectionClick();
              _fetchActivities();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD97706)))
          : RefreshIndicator(
              color: const Color(0xFFD97706),
              onRefresh: _fetchActivities,
              child: _activities.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFEF3C7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.history_toggle_off_rounded, size: 40, color: Color(0xFFD97706)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No Activities Recorded Yet',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Log field visits and campaigns from the Marketing Hub.',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final item = _activities[index];
                        final rawType = item['activity_type']?.toString() ?? 'area_visit';
                        final location = item['location']?.toString() ?? 'Unspecified';
                        final notes = item['notes']?.toString() ?? '';
                        final staffName = item['staff_name']?.toString() ?? 'Staff';
                        final createdAtStr = item['created_at']?.toString();
                        
                        String formattedDate = '';
                        if (createdAtStr != null) {
                          try {
                            final dt = DateTime.parse(createdAtStr).toLocal();
                            formattedDate = DateFormat('dd MMM yyyy • hh:mm a').format(dt);
                          } catch (_) {
                            formattedDate = createdAtStr.substring(0, 10);
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.025),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(_getTypeIcon(rawType), color: const Color(0xFFD97706), size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _formatType(rawType),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (formattedDate.isNotEmpty)
                                          Text(
                                            formattedDate,
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFF94A3B8),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  AppBadges.capsule(
                                    label: staffName,
                                    bgColor: const Color(0xFFF8FAFC),
                                    borderColor: const Color(0xFFE2E8F0),
                                    textColor: const Color(0xFF475569),
                                    fontSize: 9.5,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF334155),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF1F5F9)),
                                  ),
                                  child: Text(
                                    notes,
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF475569),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

