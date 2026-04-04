import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/bike_stats_widget.dart';
import 'package:pedalhub_admin/models/borrowing_application.dart';
import 'package:pedalhub_admin/login_page.dart';
import 'package:intl/intl.dart';

class ViceChancellorDashboardPage extends StatefulWidget {
  const ViceChancellorDashboardPage({super.key});

  @override
  State<ViceChancellorDashboardPage> createState() =>
      _ViceChancellorDashboardPageState();
}

class _ViceChancellorDashboardPageState
    extends State<ViceChancellorDashboardPage> {
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

      setState(
          () => userCampus = (profile['campus'] as String).toLowerCase());
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
            .or('status.in.(fit_to_use,vice_pending,for_release,vice_rejected,active,completed,overdue,terminated),decision_source.eq.SYSTEM')
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  borderRadius: BorderRadius.circular(8)),
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
                                  Color(0xFFD32F2F)),
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
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vice Chancellor — Automated System Oversight',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Monitoring fair allocation & compliance'
                      : 'Monitoring automated bicycle allocation system',
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
      _tabData('all', 'All VC Records', Icons.list_rounded,
          const Color(0xFF455A64)),
      _tabData('fit_to_use', 'Awaiting System',
          Icons.pending_actions_rounded, const Color(0xFFF57C00)),
      _tabData('vice_pending', 'System Processing',
          Icons.autorenew_rounded, const Color(0xFF1976D2)),
      _tabData('for_release', 'Auto-Approved',
          Icons.check_circle_rounded, const Color(0xFF388E3C)),
      _tabData('vice_rejected', 'Not Selected', Icons.cancel_rounded,
          const Color(0xFFD32F2F)),
      _tabData('active', 'Active Borrowers',
          Icons.directions_bike_rounded, const Color(0xFF1565C0)),
      _tabData('completed', 'Completed', Icons.task_alt_rounded,
          const Color(0xFF6A1B9A)),
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
          String value, String label, IconData icon, Color color) =>
      [value, label, icon, color];

  Widget _filterTab(
      String value, String label, IconData icon, Color color) {
    final isSelected = selectedStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedStatus = value);
        _fetchApplications();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            Icon(icon,
                size: 18,
                color: isSelected ? Colors.white : color),
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
  // TABLE  — full-width, desktop-optimised
  // ─────────────────────────────────────────────
  Widget _buildTable() {
    if (applications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(
            children: [
              Icon(Icons.inbox_outlined,
                  size: 72, color: Colors.grey[300]),
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

    // Column flex ratios  (must sum to a convenient number)
    // Name/ID: 3 | Type: 1.5 | Score: 2 | Bike: 1.5 | Date: 2 | Status: 2.5
    const colWidths = [3.0, 1.5, 2.0, 1.5, 2.0, 2.5];

    return Container(
      width: double.infinity,
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
        child: Column(
          children: [
            // ── Header row ──────────────────────────────────────────
            _TableHeader(colWidths: colWidths),

            // ── Data rows ───────────────────────────────────────────
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: applications.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.grey.shade100,
              ),
              itemBuilder: (context, index) {
                final app = applications[index];
                return _TableDataRow(
                  app: app,
                  colWidths: colWidths,
                  isEven: index.isEven,
                  statusColor: _statusColor(app.status),
                  statusLabel: _statusLabel(app.status),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'fit_to_use':
        return const Color(0xFFF57C00);
      case 'vice_pending':
        return const Color(0xFF1976D2);
      case 'for_release':
        return const Color(0xFF388E3C);
      case 'vice_rejected':
        return const Color(0xFFD32F2F);
      case 'active':
        return const Color(0xFF1565C0);
      case 'completed':
        return const Color(0xFF6A1B9A);
      case 'overdue':
        return const Color(0xFFE64A19);
      case 'terminated':
        return const Color(0xFF424242);
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'fit_to_use':
        return 'Awaiting Automated System';
      case 'vice_pending':
        return 'System Processing';
      case 'for_release':
        return 'Auto-Approved for Release';
      case 'vice_rejected':
        return 'Not Selected (Low Score)';
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'overdue':
        return 'Overdue';
      case 'terminated':
        return 'Terminated';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table Header
// ─────────────────────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final List<double> colWidths;

  const _TableHeader({required this.colWidths});

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Name / ID No',
      'Type',
      'Score / Decision',
      'Bike No',
      'Application Date',
      'Status',
    ];

    return Container(
      color: const Color(0xFFF5F7FA),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: List.generate(labels.length, (i) {
          return Expanded(
            flex: (colWidths[i] * 10).toInt(),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
                letterSpacing: 0.4,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table Data Row
// ─────────────────────────────────────────────────────────────────────────────

class _TableDataRow extends StatefulWidget {
  final BorrowingApplicationV2Model app;
  final List<double> colWidths;
  final bool isEven;
  final Color statusColor;
  final String statusLabel;

  const _TableDataRow({
    required this.app,
    required this.colWidths,
    required this.isEven,
    required this.statusColor,
    required this.statusLabel,
  });

  @override
  State<_TableDataRow> createState() => _TableDataRowState();
}

class _TableDataRowState extends State<_TableDataRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final dateFormat = DateFormat('MMM dd, yyyy  h:mm a');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered
            ? const Color(0xFFF0F4FF)
            : widget.isEven
                ? Colors.white
                : const Color(0xFFFAFAFA),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            // ── Name / ID ──────────────────────────────────────────
            Expanded(
              flex: (widget.colWidths[0] * 10).toInt(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${app.firstName} ${app.lastName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app.idNo ?? 'N/A',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),

            // ── Type ───────────────────────────────────────────────
            Expanded(
              flex: (widget.colWidths[1] * 10).toInt(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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
            ),

            // ── Score / Decision ───────────────────────────────────
            Expanded(
              flex: (widget.colWidths[2] * 10).toInt(),
              child: _buildScoreCell(app),
            ),

            // ── Bike No ────────────────────────────────────────────
            Expanded(
              flex: (widget.colWidths[3] * 10).toInt(),
              child: Text(
                app.assignedBikeNumber ?? '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),

            // ── Application Date ───────────────────────────────────
            Expanded(
              flex: (widget.colWidths[4] * 10).toInt(),
              child: Text(
                dateFormat.format(app.createdAt),
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[700]),
              ),
            ),

            // ── Status ─────────────────────────────────────────────
            Expanded(
              flex: (widget.colWidths[5] * 10).toInt(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        widget.statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: widget.statusColor
                            .withOpacity(0.4)),
                  ),
                  child: Text(
                    widget.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: widget.statusColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCell(BorrowingApplicationV2Model app) {
    final isSystemDecision = app.decisionSource == 'SYSTEM';

    if (!isSystemDecision) {
      return Text('—',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]));
    }

    if (app.weightedScore == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Auto-Approved',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF388E3C),
            ),
          ),
          Text(
            'No ranking needed',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          app.weightedScore!.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1976D2),
          ),
        ),
        Text(
          'Ranked by System',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}