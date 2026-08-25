import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/haptic_service.dart';
import '../drawer/partner_drawer.dart';
import 'log_activity_screen.dart';
import 'marketing_report_screen.dart';

class MarketingHomeScreen extends StatefulWidget {
  const MarketingHomeScreen({super.key});

  @override
  State<MarketingHomeScreen> createState() => _MarketingHomeScreenState();
}

class _MarketingHomeScreenState extends State<MarketingHomeScreen> {
  bool _isLoading = true;
  int _todayVisits = 0;
  int _weeklyVisits = 0;
  int _totalVisits = 0;

  @override
  void initState() {
    super.initState();
    _fetchMarketingMetrics();
  }

  Future<void> _fetchMarketingMetrics() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('marketing_activities')
          .select('id, created_at')
          .order('created_at', ascending: false);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 0, 0);
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      int todayCount = 0;
      int weekCount = 0;

      for (var row in rows) {
        final createdAtStr = row['created_at']?.toString();
        if (createdAtStr != null) {
          try {
            final dt = DateTime.parse(createdAtStr);
            if (dt.isAfter(todayStart)) {
              todayCount++;
            }
            if (dt.isAfter(sevenDaysAgo)) {
              weekCount++;
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _todayVisits = todayCount;
          _weeklyVisits = weekCount;
          _totalVisits = rows.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching marketing metrics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF0F172A)),
            onPressed: () {
              AppHaptics.selectionClick();
              Scaffold.of(ctx).openDrawer();
            },
          ),
        ),
        title: Text(
          'Marketing Hub',
          style: GoogleFonts.inter(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
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
            tooltip: 'Refresh Metrics',
            onPressed: () {
              AppHaptics.selectionClick();
              _fetchMarketingMetrics();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFD97706),
        onRefresh: _fetchMarketingMetrics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FIELD OVERVIEW',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _OverviewCard(
                      title: 'Visits Today',
                      tamilTitle: 'Logged today',
                      value: _isLoading ? '...' : '$_todayVisits',
                      icon: Icons.today_rounded,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OverviewCard(
                      title: 'Weekly Total',
                      tamilTitle: 'Logged this week',
                      value: _isLoading ? '...' : '$_weeklyVisits',
                      icon: Icons.date_range_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Total Activities Recorded:',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                        ),
                      ],
                    ),
                    Text(
                      _isLoading ? '...' : '$_totalVisits Entries',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'QUICK ACTIONS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                title: 'Log New Field Activity',
                tamilTitle: 'Field Entry',
                subtitle: 'Record an area visit, flyer campaign, or merchant onboarding.',
                icon: Icons.add_chart_rounded,
                color: const Color(0xFFD97706),
                onTap: () async {
                  AppHaptics.selectionClick();
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LogActivityScreen()),
                  );
                  if (result == true) {
                    _fetchMarketingMetrics();
                  }
                },
              ),
              const SizedBox(height: 12),
              _ActionCard(
                title: 'View Marketing History & Reports',
                tamilTitle: 'Activity Logs',
                subtitle: 'Live history of all logged marketing activities from Supabase.',
                icon: Icons.assignment_rounded,
                color: const Color(0xFF2563EB),
                onTap: () {
                  AppHaptics.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MarketingReportScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final String tamilTitle;
  final String value;
  final IconData icon;
  final Color color;

  const _OverviewCard({
    required this.title,
    required this.tamilTitle,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            tamilTitle,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String tamilTitle;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.tamilTitle,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      tamilTitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

