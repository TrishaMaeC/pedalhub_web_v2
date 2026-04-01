// lib/main/gso/gso_dashboard.dart

import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class GSODashboard extends StatefulWidget {
  const GSODashboard({super.key});

  @override
  State<GSODashboard> createState() => _GSODashboardState();
}

class _GSODashboardState extends State<GSODashboard> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  String? userCampus;

  // ── Date range filter
  DateTime? _fromDate;
  DateTime? _toDate;

  // ── Stats
  int totalBorrows = 0;
  int activeBorrows = 0;
  int returnedBikes = 0;
  int terminatedCases = 0;
  int liabilityCases = 0;
  int totalBikes = 0;
  int availableBikes = 0;
  int inUseBikes = 0;
  int maintenanceBikes = 0;
  double totalDistanceKm = 0;
  int totalRides = 0;

  // ── Per campus breakdown
  int newBorrowsCount = 0;
  int renewalBorrowsCount = 0;

  // ── Recent activity
  List<Map<String, dynamic>> recentBorrows = [];

  @override
  void initState() {
    super.initState();
    // Default: current month
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _loadUserCampusAndAll();
  }

  Future<void> _loadUserCampusAndAll() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();
      setState(
          () => userCampus = (profile['campus'] as String).toLowerCase());
      await _loadAll();
    } catch (e) {
      debugPrint('Campus load error: $e');
    }
  }

  Future<void> _loadAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _loadStats(),
        _loadBorrowBreakdown(),
        _loadRecentBorrows(),
      ]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String get _fromIso =>
      _fromDate?.toIso8601String() ?? '2000-01-01T00:00:00';
  String get _toIso =>
      _toDate?.toIso8601String() ?? DateTime.now().toIso8601String();

  // ─────────────────────────────────────────────
  // LOAD STATS
  // ─────────────────────────────────────────────
  Future<void> _loadStats() async {
    try {
      // Total borrows (new + renewal) within date range
      final newBorrows = await supabase
          .from('borrowing_applications')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('created_at', _fromIso)
          .lte('created_at', _toIso);

      final renewalBorrows = await supabase
          .from('renewal_applications')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('created_at', _fromIso)
          .lte('created_at', _toIso);

      // Get all borrowing_application IDs for this campus
      final campusApps = await supabase
          .from('borrowing_applications')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('created_at', _fromIso)
          .lte('created_at', _toIso);

      final campusAppIds = (campusApps as List)
          .map((a) => a['id'])
          .toList();

      // Active borrows filtered by campus app IDs
      final List active;
      if (campusAppIds.isEmpty) {
        active = [];
      } else {
        final activeSessions = await supabase
            .from('borrowing_sessions')
            .select('id')
            .eq('status', 'active')
            .inFilter('application_id', campusAppIds);
        active = activeSessions as List;
      }

      // Returned bikes filtered by campus app IDs
      final List returned;
      if (campusAppIds.isEmpty) {
        returned = [];
      } else {
        final returnedSessions = await supabase
            .from('borrowing_sessions')
            .select('id')
            .eq('status', 'ride_completed')
            .inFilter('application_id', campusAppIds);
        returned = returnedSessions as List;
      }

      // Terminated cases filtered by campus app IDs
      final List terminated;
      if (campusAppIds.isEmpty) {
        terminated = [];
      } else {
        final terminatedSessions = await supabase
            .from('borrowing_sessions')
            .select('id')
            .inFilter('status', [
              'terminated',
              'permanently_terminated',
              'suspended_1_semester'
            ])
            .inFilter('application_id', campusAppIds);
        terminated = terminatedSessions as List;
      }

      // Liability cases
      final liabilities = await supabase
          .from('liabilities')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('tagged_at', _fromIso)
          .lte('tagged_at', _toIso);

      // Bike fleet stats (no date filter — current state)
      final bikes = await supabase
          .from('bikes')
          .select('id, status, total_rides, total_distance_km')
          .ilike('campus', userCampus!);

      final bikeList = List<Map<String, dynamic>>.from(bikes);

      setState(() {
        totalBorrows = (newBorrows as List).length +
            (renewalBorrows as List).length;
        activeBorrows = (active as List).length;
        returnedBikes = (returned as List).length;
        terminatedCases = (terminated as List).length;
        liabilityCases = (liabilities as List).length;
        totalBikes = bikeList.length;
        availableBikes = bikeList
            .where((b) => b['status'] == 'available')
            .length;
        inUseBikes =
            bikeList.where((b) => b['status'] == 'in_use').length;
        maintenanceBikes = bikeList
            .where((b) =>
                b['status'] == 'maintenance' ||
                b['status'] == 'for_maintenance')
            .length;
        totalRides = bikeList.fold(
            0, (sum, b) => sum + ((b['total_rides'] ?? 0) as int));
        totalDistanceKm = bikeList.fold(
            0.0,
            (sum, b) =>
                sum + ((b['total_distance_km'] ?? 0.0) as num).toDouble());
      });
    } catch (e) {
      debugPrint('Load stats error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // LOAD BORROW BREAKDOWN (New vs Renewal)
  // ─────────────────────────────────────────────
  Future<void> _loadBorrowBreakdown() async {
    try {
      final newB = await supabase
          .from('borrowing_applications')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('created_at', _fromIso)
          .lte('created_at', _toIso);

      final renewalB = await supabase
          .from('renewal_applications')
          .select('id')
          .ilike('campus', userCampus!)
          .gte('created_at', _fromIso)
          .lte('created_at', _toIso);

      setState(() {
        newBorrowsCount = (newB as List).length;
        renewalBorrowsCount = (renewalB as List).length;
      });
    } catch (e) {
      debugPrint('Borrow breakdown error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // LOAD RECENT BORROWS
  // ─────────────────────────────────────────────
  Future<void> _loadRecentBorrows() async {
    try {
      // Get campus app IDs first
      final campusApps = await supabase
          .from('borrowing_applications')
          .select('id')
          .ilike('campus', userCampus!);

      final campusAppIds = (campusApps as List)
          .map((a) => a['id'])
          .toList();

      if (campusAppIds.isEmpty) {
        setState(() => recentBorrows = []);
        return;
      }

      final response = await supabase
          .from('borrowing_sessions')
          .select('id, status, start_time, end_time, created_at')
          .inFilter('application_id', campusAppIds)
          .order('created_at', ascending: false)
          .limit(8);

      setState(() =>
          recentBorrows = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Recent borrows error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // DATE PICKER
  // ─────────────────────────────────────────────
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate =
            DateTime(picked.end.year, picked.end.month, picked.end.day,
                23, 59, 59);
      });
      await _loadAll();
    }
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    DateTime from;
    DateTime to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (preset) {
      case 'today':
        from = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        from = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'year':
        from = DateTime(now.year, 1, 1);
        to = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      default:
        from = DateTime(now.year, now.month, 1);
    }
    setState(() {
      _fromDate = from;
      _toDate = to;
    });
    _loadAll();
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: const GsoDrawer(),
      body: Column(
        children: [
          Stack(
            children: [
              const AppHeader(),
              Positioned(
                top: 16,
                left: 16,
                child: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    color: Colors.red,
                    iconSize: 30,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFD32F2F))))
                : RefreshIndicator(
                    color: const Color(0xFFD32F2F),
                    onRefresh: _loadAll,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildDateFilter(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('Borrow Statistics'),
                          const SizedBox(height: 16),
                          _buildBorrowStats(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('Bike Fleet'),
                          const SizedBox(height: 16),
                          _buildBikeFleetStats(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('Usage Stats'),
                          const SizedBox(height: 16),
                          _buildUsageStats(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('New vs Renewal Borrows'),
                          const SizedBox(height: 16),
                          _buildBorrowBreakdown(),
                          const SizedBox(height: 28),
                          _buildSectionLabel('Recent Activity'),
                          const SizedBox(height: 16),
                          _buildRecentActivity(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFE57373)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.dashboard_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GSO Dashboard',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Overview & Statistics'
                      : 'Overview & Statistics',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadAll,
          color: Colors.grey[600],
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // DATE FILTER
  // ─────────────────────────────────────────────
  Widget _buildDateFilter() {
    final fmt = DateFormat('MMM dd, yyyy');
    final rangeLabel = _fromDate != null && _toDate != null
        ? '${fmt.format(_fromDate!)} — ${fmt.format(_toDate!)}'
        : 'Select date range';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_rounded,
                  color: Color(0xFFD32F2F), size: 20),
              const SizedBox(width: 8),
              const Text('Date Range',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFD32F2F)
                              .withOpacity(0.3))),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 14, color: Color(0xFFD32F2F)),
                    const SizedBox(width: 6),
                    Text(rangeLabel,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD32F2F))),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Preset buttons
          Row(
            children: [
              _presetBtn('Today', 'today'),
              const SizedBox(width: 8),
              _presetBtn('This Week', 'week'),
              const SizedBox(width: 8),
              _presetBtn('This Month', 'month'),
              const SizedBox(width: 8),
              _presetBtn('This Year', 'year'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetBtn(String label, String preset) {
    final isActive = preset == 'month' &&
        _fromDate?.day == 1 &&
        _fromDate?.month == DateTime.now().month;
    return GestureDetector(
      onTap: () => _setPreset(preset),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFD32F2F)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive
                  ? const Color(0xFFD32F2F)
                  : Colors.grey[300]!),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : Colors.grey[700])),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BORROW STATS
  // ─────────────────────────────────────────────
  Widget _buildBorrowStats() {
    return Row(
      children: [
        _statCard(
            label: 'Total Borrows',
            value: totalBorrows.toString(),
            icon: Icons.pedal_bike_rounded,
            color: const Color(0xFF1565C0),
            subtitle: 'New + Renewal'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Active Borrows',
            value: activeBorrows.toString(),
            icon: Icons.directions_bike_rounded,
            color: const Color(0xFF388E3C),
            subtitle: 'Currently riding'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Returned',
            value: returnedBikes.toString(),
            icon: Icons.assignment_turned_in_rounded,
            color: const Color(0xFF00695C),
            subtitle: 'Completed rides'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Terminated',
            value: terminatedCases.toString(),
            icon: Icons.gavel_rounded,
            color: const Color(0xFFD32F2F),
            subtitle: 'Liability cases'),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // BIKE FLEET
  // ─────────────────────────────────────────────
  Widget _buildBikeFleetStats() {
    return Row(
      children: [
        _statCard(
            label: 'Total Bikes',
            value: totalBikes.toString(),
            icon: Icons.pedal_bike_rounded,
            color: const Color(0xFF1A1A1A),
            subtitle: 'Fleet size'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Available',
            value: availableBikes.toString(),
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF388E3C),
            subtitle: 'Ready to borrow'),
        const SizedBox(width: 16),
        _statCard(
            label: 'In Use',
            value: inUseBikes.toString(),
            icon: Icons.directions_bike_rounded,
            color: const Color(0xFF1565C0),
            subtitle: 'Currently borrowed'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Maintenance',
            value: maintenanceBikes.toString(),
            icon: Icons.build_rounded,
            color: const Color(0xFFF57C00),
            subtitle: 'Under repair'),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // USAGE STATS
  // ─────────────────────────────────────────────
  Widget _buildUsageStats() {
    return Row(
      children: [
        _statCard(
            label: 'Total Rides',
            value: totalRides.toString(),
            icon: Icons.route_rounded,
            color: const Color(0xFF7B1FA2),
            subtitle: 'All time'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Total Distance',
            value: '${totalDistanceKm.toStringAsFixed(1)} km',
            icon: Icons.straighten_rounded,
            color: const Color(0xFF00838F),
            subtitle: 'All time combined'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Avg Distance',
            value: totalRides > 0
                ? '${(totalDistanceKm / totalRides).toStringAsFixed(1)} km'
                : '0.0 km',
            icon: Icons.speed_rounded,
            color: const Color(0xFFE65100),
            subtitle: 'Per ride'),
        const SizedBox(width: 16),
        _statCard(
            label: 'Liability Cases',
            value: liabilityCases.toString(),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFD32F2F),
            subtitle: 'Overdue returns'),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // NEW VS RENEWAL BREAKDOWN
  // ─────────────────────────────────────────────
  Widget _buildBorrowBreakdown() {
    final total = newBorrowsCount + renewalBorrowsCount;
    final newRatio = total > 0 ? newBorrowsCount / total : 0.0;
    final renewalRatio = total > 0 ? renewalBorrowsCount / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary row
          Row(children: [
            Expanded(
              child: _breakdownStat(
                label: 'New Borrows',
                count: newBorrowsCount,
                color: const Color(0xFF1565C0),
                icon: Icons.fiber_new_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _breakdownStat(
                label: 'Renewal Borrows',
                count: renewalBorrowsCount,
                color: const Color(0xFF7B1FA2),
                icon: Icons.autorenew_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _breakdownStat(
                label: 'Total',
                count: total,
                color: const Color(0xFFD32F2F),
                icon: Icons.summarize_rounded,
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── New borrows bar
          _breakdownBar(
            label: 'New',
            count: newBorrowsCount,
            ratio: newRatio,
            color: const Color(0xFF1565C0),
          ),
          const SizedBox(height: 12),

          // ── Renewal borrows bar
          _breakdownBar(
            label: 'Renewal',
            count: renewalBorrowsCount,
            ratio: renewalRatio,
            color: const Color(0xFF7B1FA2),
          ),

          const SizedBox(height: 20),

          // ── Percentage labels
          if (total > 0)
            Row(children: [
              _pctChip(
                  '${(newRatio * 100).toStringAsFixed(1)}% New',
                  const Color(0xFF1565C0)),
              const SizedBox(width: 10),
              _pctChip(
                  '${(renewalRatio * 100).toStringAsFixed(1)}% Renewal',
                  const Color(0xFF7B1FA2)),
            ]),
        ],
      ),
    );
  }

  Widget _breakdownStat({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(count.toString(),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      ]),
    );
  }

  Widget _breakdownBar({
    required String label,
    required int count,
    required double ratio,
    required Color color,
  }) {
    return Row(children: [
      SizedBox(
        width: 70,
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
      ),
      Expanded(
        child: Stack(children: [
          Container(
            height: 32,
            decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8)),
          ),
          FractionallySizedBox(
            widthFactor: ratio.clamp(0.02, 1.0),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$count borrows',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 12),
      Text('${(ratio * 100).toStringAsFixed(0)}%',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color)),
    ]);
  }

  Widget _pctChip(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  // ─────────────────────────────────────────────
  // RECENT ACTIVITY
  // ─────────────────────────────────────────────
  Widget _buildRecentActivity() {
    if (recentBorrows.isEmpty) {
      return _emptyCard('No recent activity found.');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: recentBorrows.asMap().entries.map((entry) {
          final i = entry.key;
          final session = entry.value;
          final status = session['status'] ?? 'unknown';
          final color = _sessionStatusColor(status);
          final label = _sessionStatusLabel(status);

          String timeLabel = 'N/A';
          try {
            final dt = DateTime.parse(
                    session['created_at'].toString())
                .toLocal();
            timeLabel = DateFormat('MMM dd, HH:mm').format(dt);
          } catch (_) {}

          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: i < recentBorrows.length - 1
                  ? Border(
                      bottom: BorderSide(color: Colors.grey[100]!))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.pedal_bike_rounded,
                      color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session #${session['id']}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A))),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color)),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _sessionStatusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF388E3C);
      case 'ride_completed':
        return const Color(0xFF1565C0);
      case 'terminated':
      case 'permanently_terminated':
        return const Color(0xFFD32F2F);
      case 'suspended_1_semester':
        return const Color(0xFFE65100);
      case 'overdue':
        return const Color(0xFFF57C00);
      default:
        return Colors.grey;
    }
  }

  String _sessionStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'ride_completed':
        return 'Completed';
      case 'terminated':
        return 'Terminated';
      case 'permanently_terminated':
        return 'Perm. Terminated';
      case 'suspended_1_semester':
        return 'Suspended';
      case 'overdue':
        return 'Overdue';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  // ─────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Row(children: [
      Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
              color: const Color(0xFFD32F2F),
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 22),
                ),
                Text(value,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A))),
            Text(subtitle,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
      child: Center(
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ]),
      ),
    );
  }
}