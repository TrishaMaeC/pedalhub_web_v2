import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/bike_stats_widget.dart';
import 'package:pedalhub_admin/models/borrowing_application.dart';
import 'package:pedalhub_admin/login_page.dart';
import 'package:intl/intl.dart';

class ForRankingPage extends StatefulWidget {
  const ForRankingPage({super.key});

  @override
  State<ForRankingPage> createState() => _ForRankingPageState();
}

class _ForRankingPageState extends State<ForRankingPage> {
  final supabase = Supabase.instance.client;
  final _statsKey = GlobalKey<BikeStatsWidgetState>();

  bool isLoading = true;
  String selectedStatus = 'all';
  String? userCampus;

  List<BorrowingApplicationV2Model> applications = [];

  @override
  void initState() {
    super.initState();
    _loadUserCampusAndFetch();
  }

  Future<void> _loadUserCampusAndFetch() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      await _fetchApplications();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchApplications() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);

    try {
      List response;

      if (selectedStatus == 'all') {
        response = await supabase
            .from('borrowing_applications_version2')
            .select('*')
            .ilike('campus', userCampus!)
            .inFilter('status', [
              'active',
              'completed',
              'waitlisted',
              'for_release',
              'for_appointment',
            ])
            .order('created_at', ascending: false);
      } else {
        response = await supabase
            .from('borrowing_applications_version2')
            .select('*')
            .eq('status', selectedStatus)
            .ilike('campus', userCampus!)
            .order('created_at', ascending: false);
      }

      setState(() {
        applications = response
            .map((e) => BorrowingApplicationV2Model.fromJson(e))
            .toList();
      });
    } catch (e) {
      debugPrint('FETCH ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => isLoading = false);
  }

  Future<void> _refresh() async {
    _statsKey.currentState?.refresh();
    await _fetchApplications();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await supabase.auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Stack(
            children: [
              const AppHeader(),
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  color: Colors.red,
                  iconSize: 28,
                  tooltip: 'Logout',
                  onPressed: _confirmLogout,
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFD32F2F),
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageTitle(),
                    const SizedBox(height: 28),
                    if (userCampus != null)
                      BikeStatsWidget(
                        key: _statsKey,
                        campus: userCampus!,
                      ),
                    const SizedBox(height: 28),
                    _buildFilterTabs(),
                    const SizedBox(height: 24),
                    isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFD32F2F),
                              ),
                            ),
                          )
                        : _buildTable(),
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
  // PAGE TITLE
  // ─────────────────────────────────────────────
  Widget _buildPageTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dashboard_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vice Chancellor — Oversight Dashboard',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Monitoring bicycle allocation & borrower records'
                      : 'Monitoring bicycle allocation & borrower records',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
          tooltip: 'Refresh',
          color: Colors.grey[600],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // FILTER TABS
  // ─────────────────────────────────────────────
  Widget _buildFilterTabs() {
    final tabs = [
      _tabData('all', 'All Records', Icons.list_rounded, const Color(0xFF455A64)),
      _tabData('active', 'Active', Icons.directions_bike_rounded, const Color(0xFF1565C0)),
      _tabData('for_appointment', 'For Appointment', Icons.event_rounded, const Color(0xFFF57C00)),
      _tabData('waitlisted', 'Waitlisted', Icons.hourglass_top_rounded, const Color(0xFF6A1B9A)),
      _tabData('completed', 'Returned', Icons.check_circle_rounded, const Color(0xFF388E3C)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: tabs
          .map((t) => _filterTab(
                t[0] as String,
                t[1] as String,
                t[2] as IconData,
                t[3] as Color,
              ))
          .toList(),
    );
  }

  List<dynamic> _tabData(
    String value,
    String label,
    IconData icon,
    Color color,
  ) => [value, label, icon, color];

  Widget _filterTab(String value, String label, IconData icon, Color color) {
    final isSelected = selectedStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedStatus = value);
        _fetchApplications();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TABLE
  // ─────────────────────────────────────────────
  Widget _buildTable() {
    if (applications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 72, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No records found',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F7FA)),
            columnSpacing: 24,
            columns: const [
              DataColumn(
                label: Text(
                  'Name / ID No',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Type',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Bike No',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Borrowing Period',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows: applications.map((app) => _buildRow(app)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BorrowingApplicationV2Model app) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final statusColor = _statusColor(app.status);
    final statusLabel = _statusLabel(app.status);

    return DataRow(cells: [
      DataCell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${app.firstName} ${app.lastName}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              app.idNo ?? 'N/A',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: app.isStudent
                ? const Color(0xFF1565C0).withOpacity(0.1)
                : const Color(0xFF7B1FA2).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            app.isStudent ? 'Student' : 'Personnel',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: app.isStudent
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF7B1FA2),
            ),
          ),
        ),
      ),
      DataCell(
        Text(
          app.assignedBikeNumber ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      DataCell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'From: ${dateFormat.format(app.createdAt)}',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              app.status == 'completed'
                  ? 'To: ${dateFormat.format(app.updatedAt)}'
                  : 'To: Ongoing',
              style: TextStyle(
                fontSize: 11,
                color: app.status == 'completed'
                    ? Colors.grey[500]
                    : Colors.green,
              ),
            ),
          ],
        ),
      ),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
      ),
    ]);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF1565C0);
      case 'completed':
        return const Color(0xFF388E3C);
      case 'waitlisted':
        return const Color(0xFF6A1B9A);
      case 'for_appointment':
        return const Color(0xFFF57C00);
      case 'for_release':
        return const Color(0xFF0288D1);
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Returned';
      case 'waitlisted':
        return 'Waitlisted';
      case 'for_appointment':
        return 'For Appointment';
      case 'for_release':
        return 'For Release';
      default:
        return status;
    }
  }
}