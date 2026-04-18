// lib/main/osd/osd_dashboard.dart

import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

class OsdDashboardPage extends StatefulWidget {
  const OsdDashboardPage({super.key});

  @override
  State<OsdDashboardPage> createState() => _OsdDashboardPageState();
}

class _OsdDashboardPageState extends State<OsdDashboardPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _mainTabController;

  bool isLoading = true;

  // ── Renewal tab
  String selectedStatus = 'renewal_applied';
  List<Map<String, dynamic>> applications = [];
  int pendingCount = 0;
  int approvedCount = 0;
  int rejectedCount = 0;

  // ── New Applications tab
  String selectedNewAppStatus = 'pending_application';
  List<Map<String, dynamic>> newApplications = [];
  int newPendingCount = 0;
  int newApprovedCount = 0;
  int newRejectedCount = 0;

  // ── Discipline tab
  String selectedDisciplineTab = 'forwarded_discipline';
  List<Map<String, dynamic>> disciplineCases = [];
  int openCasesCount = 0;
  int resolvedCasesCount = 0;

  String? userCampus;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
    _mainTabController.addListener(() {
      if (_mainTabController.indexIsChanging) return;
      if (_mainTabController.index == 1) _fetchNewApplications();
      if (_mainTabController.index == 2) _fetchDisciplineCases();
    });
    _loadUserCampusAndAll();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadUserCampusAndAll() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();
      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      _loadAll();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading user profile: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _loadMetrics(),
        _fetchApplications(),
        _fetchNewApplications(),
        _fetchDisciplineCases(),
      ]);
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadMetrics() async {
    try {
      // ── 1. Renewal metrics
      final pending = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'renewal_applied')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      final approved = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('is_hrmo_osd_approved', true)
          .eq('status', 'renewal_osd_approved')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      final rejected = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'renewal_osd_rejected')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      // ── 2. New Applications metrics
      final newPending = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'pending_application')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      final newApproved = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('is_hrmo_osd_approved', true)
          .eq('status', 'osd_approved')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      final newRejected = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'osd_rejected')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      // ── 3. Discipline metrics — from liabilities_version2
      final openRaw = await supabase
          .from('liabilities_version2')
          .select('id')
          .eq('penalty_status', 'forwarded_discipline')
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      final resolvedRaw = await supabase
          .from('liabilities_version2')
          .select('id')
          .inFilter('final_penalty_status', ['suspended_1_semester', 'terminated'])
          .eq('user_type', 'student')
          .ilike('campus', userCampus!)
          .count(CountOption.exact);

      setState(() {
        pendingCount = pending.count;
        approvedCount = approved.count;
        rejectedCount = rejected.count;

        newPendingCount = newPending.count;
        newApprovedCount = newApproved.count;
        newRejectedCount = newRejected.count;

        openCasesCount = openRaw.count;
        resolvedCasesCount = resolvedRaw.count;
      });
    } catch (e) {
      debugPrint('Error loading metrics: $e');
    }
  }

  // ── Renewal applications ───────────────────────────────────────────────────

  Future<void> _fetchApplications() async {
    if (userCampus == null) return;
    final response = await supabase
        .from('borrowing_applications_version2')
        .select('*')
        .eq('status', selectedStatus)
        .eq('user_type', 'student')
        .ilike('campus', userCampus!)
        .order('renewal_applied_at', ascending: false);
    setState(() => applications = List<Map<String, dynamic>>.from(response));
  }

  // ── New Applications ───────────────────────────────────────────────────────

  Future<void> _fetchNewApplications() async {
    if (userCampus == null) return;
    final response = await supabase
        .from('borrowing_applications_version2')
        .select('*')
        .eq('status', selectedNewAppStatus)
        .eq('user_type', 'student')
        .ilike('campus', userCampus!)
        .order('created_at', ascending: false);
    setState(() => newApplications = List<Map<String, dynamic>>.from(response));
  }

  // ── Discipline cases — from liabilities_version2 ──────────────────────────

  Future<void> _fetchDisciplineCases() async {
    if (userCampus == null) return;
    try {
      final isOpen = selectedDisciplineTab == 'forwarded_discipline';
      late final List response;

      if (isOpen) {
        response = await supabase
            .from('liabilities_version2')
            .select('*')
            .eq('penalty_status', 'forwarded_discipline')
            .eq('user_type', 'student')
            .ilike('campus', userCampus!)
            .order('forwarded_at', ascending: false);
      } else {
        response = await supabase
            .from('liabilities_version2')
            .select('*')
            .inFilter('final_penalty_status', ['suspended_1_semester', 'terminated'])
            .eq('user_type', 'student')
            .ilike('campus', userCampus!)
            .order('final_penalty_set_at', ascending: false);
      }

      setState(() => disciplineCases = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Fetch discipline cases error: $e');
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _showFinalizeDialog(Map<String, dynamic> disciplineCase) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FinalizeDecisionDialog(
        disciplineCase: disciplineCase,
        onFinalized: () async {
          await _loadAll();
          setState(() => selectedDisciplineTab = 'resolved');
        },
      ),
    );
  }

  void _showCertifyRenewalDialog(Map<String, dynamic> app) {
    final applicantName =
        '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CertifyDialog(
        applicationId: app['id'].toString(),
        applicantName: applicantName,
        onApproved: _loadAll,
        tableSource: _AppTableSource.renewal,
      ),
    );
  }

  void _showCertifyNewAppDialog(Map<String, dynamic> app) {
    final applicantName =
        '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CertifyDialog(
        applicationId: app['id'].toString(),
        applicantName: applicantName,
        onApproved: _loadAll,
        tableSource: _AppTableSource.newApplication,
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
          SizedBox(width: 10),
          Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
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
          (route) => false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _mainTabController,
              labelColor: const Color(0xFFD32F2F),
              unselectedLabelColor: Colors.grey[500],
              indicatorColor: const Color(0xFFD32F2F),
              indicatorWeight: 3,
              labelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              tabs: [
                const Tab(
                    icon: Icon(Icons.how_to_reg_rounded),
                    text: 'Renewal Approval'),
                Tab(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.assignment_ind_rounded),
                      if (newPendingCount > 0)
                        Positioned(
                          right: -8,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Color(0xFFD32F2F),
                                shape: BoxShape.circle),
                            child: Text(newPendingCount.toString(),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  text: 'New Applications',
                ),
                Tab(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.gavel_rounded),
                      if (openCasesCount > 0)
                        Positioned(
                          right: -8,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Color(0xFFD32F2F),
                                shape: BoxShape.circle),
                            child: Text(openCasesCount.toString(),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  text: 'Disciplinary Cases',
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFD32F2F))))
                : TabBarView(
                    controller: _mainTabController,
                    children: [
                      _buildRenewalTab(),
                      _buildNewApplicationsTab(),
                      _buildDisciplineTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TAB 1 – Renewal Approval
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRenewalTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildRenewalTitle(),
          const SizedBox(height: 32),
          _buildRenewalMetricCards(),
          const SizedBox(height: 32),
          _buildRenewalFilterTabs(),
          const SizedBox(height: 24),
          _buildApplicationList(),
        ]),
      ),
    );
  }

  Widget _buildRenewalTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.how_to_reg_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('OSD Renewal Approval',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            Text(
              userCampus != null
                  ? 'Campus: ${userCampus!.toUpperCase()}  •  Review and certify student renewal applications'
                  : 'Review and certify student renewal applications',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ]),
        ]),
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
            tooltip: 'Refresh',
            color: Colors.grey[600]),
      ],
    );
  }

  Widget _buildRenewalMetricCards() {
    return Row(children: [
      Expanded(
          child: _metricCard(
              label: 'Pending',
              count: pendingCount,
              icon: Icons.pending_actions_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFFF57C00), Color(0xFFFFB74D)]))),
      const SizedBox(width: 20),
      Expanded(
          child: _metricCard(
              label: 'Approved',
              count: approvedCount,
              icon: Icons.check_circle_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]))),
      const SizedBox(width: 20),
      Expanded(
          child: _metricCard(
              label: 'Rejected',
              count: rejectedCount,
              icon: Icons.cancel_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)]))),
    ]);
  }

  Widget _buildRenewalFilterTabs() {
    return Row(children: [
      _filterTab(
        label: 'Pending',
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFFF57C00),
        isSelected: selectedStatus == 'renewal_applied',
        onTap: () {
          setState(() => selectedStatus = 'renewal_applied');
          _fetchApplications();
        },
      ),
      const SizedBox(width: 12),
      _filterTab(
        label: 'Approved',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF388E3C),
        isSelected: selectedStatus == 'renewal_osd_approved',
        onTap: () {
          setState(() => selectedStatus = 'renewal_osd_approved');
          _fetchApplications();
        },
      ),
      const SizedBox(width: 12),
      _filterTab(
        label: 'Rejected',
        icon: Icons.cancel_rounded,
        color: const Color(0xFFD32F2F),
        isSelected: selectedStatus == 'renewal_osd_rejected',
        onTap: () {
          setState(() => selectedStatus = 'renewal_osd_rejected');
          _fetchApplications();
        },
      ),
    ]);
  }

  Widget _buildApplicationList() {
    if (applications.isEmpty) {
      return _emptyState(
        selectedStatus == 'renewal_applied'
            ? 'No pending renewals'
            : selectedStatus == 'renewal_osd_approved'
                ? 'No approved renewals'
                : 'No rejected renewals',
      );
    }
    return Column(
        children: applications.map((app) => _renewalCard(app)).toList());
  }

  Widget _renewalCard(Map<String, dynamic> app) {
    final firstName = app['first_name'] ?? '';
    final lastName = app['last_name'] ?? '';
    final idNo = app['id_no'] ?? 'N/A';
    final collegeOffice = app['college_office'] ?? 'N/A';
    final controlNumber = app['control_number'] ?? 'N/A';
    final renewalCount = app['renewal_count'] ?? 0;
    final status = app['status'] ?? '';
    final isPending = status == 'renewal_applied';
    final isApproved = status == 'renewal_osd_approved';

    final Color statusColor = isPending
        ? const Color(0xFFF57C00)
        : isApproved
            ? const Color(0xFF388E3C)
            : const Color(0xFFD32F2F);
    final String statusLabel = isPending
        ? 'Pending Review'
        : isApproved
            ? 'Approved'
            : 'Rejected';
    final IconData statusIcon = isPending
        ? Icons.pending_actions_rounded
        : isApproved
            ? Icons.check_circle_rounded
            : Icons.cancel_rounded;

    String renewalAppliedLabel = 'N/A';
    if (app['renewal_applied_at'] != null) {
      try {
        final dt =
            DateTime.parse(app['renewal_applied_at'].toString()).toLocal();
        renewalAppliedLabel = DateFormat('MMM dd, yyyy').format(dt);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(statusIcon, color: statusColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$firstName $lastName',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(width: 8),
              _chip('Student', const Color(0xFF1976D2)),
              if (renewalCount > 0) ...[
                const SizedBox(width: 6),
                _chip('Renewal #$renewalCount', const Color(0xFF1565C0)),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
                'ID: $idNo  •  Program: $collegeOffice  •  Control: $controlNumber',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 2),
            Text('Applied: $renewalAppliedLabel',
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 10),
            _statusBadge(statusLabel, statusColor),
          ]),
        ),
        if (isPending)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _actionButton(
                  label: 'Certify',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF388E3C),
                  onPressed: () => _showCertifyRenewalDialog(app)),
            ],
          ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TAB 2 – New Applications
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildNewApplicationsTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _fetchNewApplications,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildNewAppTitle(),
          const SizedBox(height: 32),
          _buildNewAppMetricCards(),
          const SizedBox(height: 32),
          _buildNewAppFilterTabs(),
          const SizedBox(height: 24),
          _buildNewApplicationList(),
        ]),
      ),
    );
  }

  Widget _buildNewAppTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.assignment_ind_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New Applications',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            Text(
              userCampus != null
                  ? 'Campus: ${userCampus!.toUpperCase()}  •  Review new student applications'
                  : 'Review new student applications',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ]),
        ]),
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchNewApplications,
            tooltip: 'Refresh',
            color: Colors.grey[600]),
      ],
    );
  }

  Widget _buildNewAppMetricCards() {
    return Row(children: [
      Expanded(
          child: _metricCard(
              label: 'Pending',
              count: newPendingCount,
              icon: Icons.pending_actions_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFFF57C00), Color(0xFFFFB74D)]))),
      const SizedBox(width: 20),
      Expanded(
          child: _metricCard(
              label: 'Approved',
              count: newApprovedCount,
              icon: Icons.check_circle_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]))),
      const SizedBox(width: 20),
      Expanded(
          child: _metricCard(
              label: 'Rejected',
              count: newRejectedCount,
              icon: Icons.cancel_rounded,
              gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)]))),
    ]);
  }

  Widget _buildNewAppFilterTabs() {
    return Row(children: [
      _filterTab(
        label: 'Pending',
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFFF57C00),
        isSelected: selectedNewAppStatus == 'pending_application',
        onTap: () {
          setState(() => selectedNewAppStatus = 'pending_application');
          _fetchNewApplications();
        },
      ),
      const SizedBox(width: 12),
      _filterTab(
        label: 'Approved',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF388E3C),
        isSelected: selectedNewAppStatus == 'osd_approved',
        onTap: () {
          setState(() => selectedNewAppStatus = 'osd_approved');
          _fetchNewApplications();
        },
      ),
      const SizedBox(width: 12),
      _filterTab(
        label: 'Rejected',
        icon: Icons.cancel_rounded,
        color: const Color(0xFFD32F2F),
        isSelected: selectedNewAppStatus == 'osd_rejected',
        onTap: () {
          setState(() => selectedNewAppStatus = 'osd_rejected');
          _fetchNewApplications();
        },
      ),
    ]);
  }

  Widget _buildNewApplicationList() {
    if (newApplications.isEmpty) {
      return _emptyState(
        selectedNewAppStatus == 'pending_application'
            ? 'No pending applications'
            : selectedNewAppStatus == 'osd_approved'
                ? 'No approved applications'
                : 'No rejected applications',
      );
    }
    return Column(
        children: newApplications.map((app) => _newAppCard(app)).toList());
  }

  Widget _newAppCard(Map<String, dynamic> app) {
    final firstName = app['first_name'] ?? '';
    final lastName = app['last_name'] ?? '';
    final idNo = app['id_no'] ?? 'N/A';
    final collegeOffice = app['college_office'] ?? 'N/A';
    final controlNumber = app['control_number'] ?? 'N/A';
    final status = app['status'] ?? '';
    final isPending = status == 'pending_application';
    final isApproved = status == 'osd_approved';

    final Color statusColor = isPending
        ? const Color(0xFFF57C00)
        : isApproved
            ? const Color(0xFF388E3C)
            : const Color(0xFFD32F2F);
    final String statusLabel = isPending
        ? 'Pending Review'
        : isApproved
            ? 'Approved'
            : 'Rejected';
    final IconData statusIcon = isPending
        ? Icons.pending_actions_rounded
        : isApproved
            ? Icons.check_circle_rounded
            : Icons.cancel_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(statusIcon, color: statusColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$firstName $lastName',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(width: 8),
              _chip('Student', const Color(0xFF1976D2)),
            ]),
            const SizedBox(height: 4),
            Text(
                'ID: $idNo  •  Program: $collegeOffice  •  Control No: $controlNumber',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 10),
            _statusBadge(statusLabel, statusColor),
          ]),
        ),
        if (isPending)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _actionButton(
                  label: 'Certify',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF388E3C),
                  onPressed: () => _showCertifyNewAppDialog(app)),
            ],
          ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TAB 3 – Disciplinary Cases
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDisciplineTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _fetchDisciplineCases,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildDisciplineTitle(),
          const SizedBox(height: 24),
          _buildDisciplineSummaryCards(),
          const SizedBox(height: 24),
          _buildDisciplineFilterTabs(),
          const SizedBox(height: 20),
          _buildDisciplineCasesList(),
        ]),
      ),
    );
  }

  Widget _buildDisciplineTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.gavel_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Disciplinary Cases',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            Text(
              userCampus != null
                  ? 'Campus: ${userCampus!.toUpperCase()}  •  Finalize penalty decisions for students'
                  : 'Finalize penalty decisions for students',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ]),
        ]),
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchDisciplineCases,
            color: Colors.grey[600]),
      ],
    );
  }

  Widget _buildDisciplineSummaryCards() {
    return Row(children: [
      _disciplineSummaryCard(
          label: 'Open Cases',
          count: openCasesCount,
          icon: Icons.pending_actions_rounded,
          color: const Color(0xFFD32F2F)),
      const SizedBox(width: 16),
      _disciplineSummaryCard(
          label: 'Resolved Cases',
          count: resolvedCasesCount,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF388E3C)),
    ]);
  }

  Widget _disciplineSummaryCard(
      {required String label,
      required int count,
      required IconData icon,
      required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(count.toString(),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ]),
        ]),
      ),
    );
  }

  Widget _buildDisciplineFilterTabs() {
    return Row(children: [
      _disciplineFilterTab(
          value: 'forwarded_discipline',
          label: 'Open Cases',
          icon: Icons.pending_actions_rounded,
          color: const Color(0xFFD32F2F),
          count: openCasesCount),
      const SizedBox(width: 12),
      _disciplineFilterTab(
          value: 'resolved',
          label: 'Resolved',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF388E3C),
          count: resolvedCasesCount),
    ]);
  }

  Widget _disciplineFilterTab(
      {required String value,
      required String label,
      required IconData icon,
      required Color color,
      required int count}) {
    final isSelected = selectedDisciplineTab == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedDisciplineTab = value);
        _fetchDisciplineCases();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!, width: 1.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: isSelected ? Colors.white : color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.3)
                      : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(99)),
              child: Text(count.toString(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : color)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildDisciplineCasesList() {
    if (disciplineCases.isEmpty) {
      return _emptyState(
        selectedDisciplineTab == 'forwarded_discipline'
            ? 'No open discipline cases'
            : 'No resolved cases yet',
      );
    }
    return Column(
        children: disciplineCases.map((c) => _disciplineCaseCard(c)).toList());
  }

  Widget _disciplineCaseCard(Map<String, dynamic> disciplineCase) {
    final isOpen =
        disciplineCase['penalty_status'] == 'forwarded_discipline';
    final penaltyRec = _formatPenalty(
        disciplineCase['penalty_recommendation'] as String? ?? '');
    final finalPenalty = _formatPenalty(
        disciplineCase['final_penalty_status'] as String? ?? '');
    final idNo = disciplineCase['id_no']?.toString() ?? 'N/A';

    String forwardedAtLabel = 'N/A';
    try {
      final dt =
          DateTime.parse(disciplineCase['forwarded_at'].toString()).toLocal();
      forwardedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {}

    String resolvedAtLabel = '';
    if (!isOpen && disciplineCase['final_penalty_set_at'] != null) {
      try {
        final dt = DateTime.parse(
                disciplineCase['final_penalty_set_at'].toString())
            .toLocal();
        resolvedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
      } catch (_) {}
    }

    final Color statusColor =
        isOpen ? const Color(0xFFD32F2F) : const Color(0xFF388E3C);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(
                isOpen
                    ? Icons.pending_actions_rounded
                    : Icons.check_circle_rounded,
                color: statusColor,
                size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(disciplineCase['borrower_name'] ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(width: 8),
                    _chip(isOpen ? 'Open Case' : 'Resolved', statusColor),
                    const SizedBox(width: 6),
                    _chip('Student', const Color(0xFF1976D2)),
                  ]),
                  const SizedBox(height: 4),
                  Text('ID No: $idNo',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600])),
                ]),
          ),
          if (isOpen)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () => _showFinalizeDialog(disciplineCase),
              icon: const Icon(Icons.gavel_rounded, size: 18),
              label: const Text('Finalize Decision',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _detailItem(Icons.pedal_bike_rounded, 'Bike',
                  disciplineCase['bike_number'] ?? 'N/A')),
          Expanded(
              child: _detailItem(
                  Icons.access_time_rounded, 'Forwarded', forwardedAtLabel)),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color(0xFFD32F2F).withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.assignment_rounded,
                color: Color(0xFFD32F2F), size: 16),
            const SizedBox(width: 8),
            Text('GSO Recommendation: ',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            Text(
                penaltyRec.isEmpty ? 'None provided' : penaltyRec,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD32F2F))),
          ]),
        ),
        if (!isOpen && finalPenalty.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF388E3C).withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.gavel_rounded,
                  color: Color(0xFF388E3C), size: 16),
              const SizedBox(width: 8),
              Text('Final Decision: ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
              Text(finalPenalty,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF388E3C))),
              if (resolvedAtLabel.isNotEmpty) ...[
                const Spacer(),
                Text(resolvedAtLabel,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ]),
          ),
        ],
        if (disciplineCase['forwarded_notes'] != null &&
            disciplineCase['forwarded_notes'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.notes_rounded, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    'Notes: ${disciplineCase['forwarded_notes']}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic))),
          ]),
        ],
        if (disciplineCase['assessment_remarks'] != null &&
            disciplineCase['assessment_remarks'].toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.rate_review_rounded,
                size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    'Assessment: ${disciplineCase['assessment_remarks']}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic))),
          ]),
        ],
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _metricCard(
      {required String label,
      required int count,
      required IconData icon,
      required Gradient gradient}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 20),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(count.toString(),
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }

  Widget _filterTab({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!, width: 1.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: isSelected ? Colors.white : color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color)),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey[500]),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  String _formatPenalty(String penalty) {
    switch (penalty) {
      case 'terminated':
        return 'Permanently Terminated';
      case 'suspended_1_semester':
        return 'Suspended for 1 Semester';
      default:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Enum
// ═══════════════════════════════════════════════════════════════════
enum _AppTableSource { renewal, newApplication }

// ═══════════════════════════════════════════════════════════════════
// CERTIFY DIALOG
// ═══════════════════════════════════════════════════════════════════
class _CertifyDialog extends StatefulWidget {
  final String applicationId;
  final String applicantName;
  final VoidCallback onApproved;
  final _AppTableSource tableSource;

  const _CertifyDialog({
    required this.applicationId,
    required this.applicantName,
    required this.onApproved,
    required this.tableSource,
  });

  @override
  State<_CertifyDialog> createState() => _CertifyDialogState();
}

class _CertifyDialogState extends State<_CertifyDialog> {
  final supabase = Supabase.instance.client;
  final TextEditingController _signatoryNameController =
      TextEditingController();
  bool? _hasDisciplinaryAction;
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  bool _isDrawMode = true;
  bool _hasSignature = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _isSubmitting = false;

  bool get _canApprove =>
      _hasDisciplinaryAction != null &&
      _hasSignature &&
      _signatoryNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSignatoryName();
    _signatureController.addListener(() {
      setState(() => _hasSignature =
          _signatureController.isNotEmpty || _uploadedImageBytes != null);
    });
    _signatoryNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _signatoryNameController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _loadSignatoryName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final response = await supabase
            .from('profiles')
            .select('email')
            .eq('id', userId)
            .maybeSingle();
        if (response != null && mounted) {
          final email = response['email'] as String;
          _signatoryNameController.text =
              email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Error loading signatory name: $e');
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final bytes = result.files.first.bytes;
      final fileName = result.files.first.name;
      if (bytes != null) {
        setState(() {
          _uploadedImageBytes = bytes;
          _uploadedFileName = fileName;
          _hasSignature = true;
        });
      }
    }
  }

  Future<String?> _uploadSignature(Uint8List bytes, String fileName) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';
      final path = 'osd_signatures/${userId}_${timestamp}_$fileName';
      await supabase.storage.from('signatures').uploadBinary(path, bytes);
      return supabase.storage.from('signatures').getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _approve() async {
    if (!_canApprove) return;
    setState(() => _isSubmitting = true);
    try {
      Uint8List? sigBytes;
      String fileName;
      if (_isDrawMode) {
        sigBytes = await _signatureController.toPngBytes();
        if (sigBytes == null)
          throw Exception('Failed to export drawn signature');
        fileName = 'drawn_signature.png';
      } else {
        sigBytes = _uploadedImageBytes;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      final signatureUrl = await _uploadSignature(sigBytes!, fileName);
      if (signatureUrl == null) throw Exception('Signature upload failed');

      if (_hasDisciplinaryAction == true) {
        if (widget.tableSource == _AppTableSource.renewal) {
          await supabase.from('borrowing_applications_version2').update({
            'status': 'renewal_osd_rejected',
            'renewal_hrmo_osd_rejection_reason':
                'Has disciplinary actions with final judgement relating to government properties',
            'renewal_hrmo_osd_signature_url': signatureUrl,
            'renewal_hrmo_osd_signatory_name':
                _signatoryNameController.text.trim(),
          }).eq('id', widget.applicationId);
        } else {
          await supabase.from('borrowing_applications_version2').update({
            'status': 'osd_rejected',
            'rejection_reason':
                'Has disciplinary actions with final judgement relating to government properties',
            'hrmo_osd_signature': signatureUrl,
            'hrmo_osd_name': _signatoryNameController.text.trim(),
            'hrmo_osd_date_signed': DateTime.now().toIso8601String(),
          }).eq('id', widget.applicationId);
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Application rejected due to disciplinary actions.'),
              backgroundColor: Color(0xFFD32F2F),
            ),
          );
        }
      } else {
        if (widget.tableSource == _AppTableSource.renewal) {
          await supabase.from('borrowing_applications_version2').update({
            'status': 'renewal_osd_approved',
            'is_hrmo_osd_approved': true,
            'renewal_hrmo_osd_signature_url': signatureUrl,
            'renewal_hrmo_osd_signatory_name':
                _signatoryNameController.text.trim(),
          }).eq('id', widget.applicationId);
        } else {
          await supabase.from('borrowing_applications_version2').update({
            'status': 'osd_approved',
            'is_hrmo_osd_approved': true,
            'hrmo_osd_signature': signatureUrl,
            'hrmo_osd_name': _signatoryNameController.text.trim(),
            'hrmo_osd_date_signed': DateTime.now().toIso8601String(),
          }).eq('id', widget.applicationId);
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Application certified and approved.'),
                backgroundColor: Color(0xFF388E3C)),
          );
        }
      }

      widget.onApproved();
    } catch (e) {
      debugPrint('Certify error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(28),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Certify Application',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  Text(widget.applicantName,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600])),
                ])),
            IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Disciplinary Status',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text(
                        'Select the applicable disciplinary status for this applicant:',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 14),
                    _disciplinaryOption(
                        value: false,
                        label:
                            'Has no disciplinary actions with final judgement relating to government properties',
                        icon: Icons.check_circle_outline_rounded,
                        activeColor: const Color(0xFF388E3C)),
                    const SizedBox(height: 10),
                    _disciplinaryOption(
                        value: true,
                        label:
                            'Has disciplinary actions with final judgement relating to government properties',
                        icon: Icons.warning_amber_rounded,
                        activeColor: const Color(0xFFD32F2F)),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 20),
                    const Text('Signatory Name *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _signatoryNameController,
                      decoration: InputDecoration(
                        hintText: 'Enter your full name',
                        prefixIcon: const Icon(Icons.badge_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('OSD Signature *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text(
                        'Draw or upload your signature to certify this application:',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            height: 150,
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(8)),
                            child: _isDrawMode
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Signature(
                                        controller: _signatureController,
                                        backgroundColor: Colors.white))
                                : _uploadedImageBytes == null
                                    ? Center(
                                        child: ElevatedButton.icon(
                                        onPressed: _pickImage,
                                        icon: const Icon(Icons.upload_file,
                                            size: 20),
                                        label:
                                            const Text('Upload Signature'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF1976D2),
                                            foregroundColor: Colors.white),
                                      ))
                                    : ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: Image.memory(
                                            _uploadedImageBytes!,
                                            fit: BoxFit.contain)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(children: [
                          IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear signature',
                            onPressed: () {
                              _signatureController.clear();
                              setState(() {
                                _uploadedImageBytes = null;
                                _hasSignature = false;
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(_isDrawMode
                                ? Icons.upload_file
                                : Icons.edit),
                            tooltip: _isDrawMode
                                ? 'Switch to Upload'
                                : 'Switch to Draw',
                            onPressed: () {
                              setState(() {
                                _isDrawMode = !_isDrawMode;
                                _uploadedImageBytes = null;
                                _hasSignature =
                                    _signatureController.isNotEmpty;
                              });
                            },
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isDrawMode
                          ? 'Draw your signature in the box above'
                          : 'Click "Upload Signature" to choose an image file',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: Colors.grey[600]))),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canApprove
                      ? (_hasDisciplinaryAction == true
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF388E3C))
                      : Colors.grey[300],
                  foregroundColor:
                      _canApprove ? Colors.white : Colors.grey[500],
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed:
                    _canApprove && !_isSubmitting ? _approve : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        _hasDisciplinaryAction == true
                            ? Icons.cancel_rounded
                            : Icons.verified_rounded,
                        size: 18,
                      ),
                label: Text(
                    _isSubmitting
                        ? 'Processing...'
                        : (_hasDisciplinaryAction == true
                            ? 'Reject'
                            : 'Approve'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _disciplinaryOption(
      {required bool value,
      required String label,
      required IconData icon,
      required Color activeColor}) {
    final isSelected = _hasDisciplinaryAction == value;
    return GestureDetector(
      onTap: () => setState(() => _hasDisciplinaryAction = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isSelected ? activeColor.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? activeColor : Colors.grey[300]!,
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? activeColor : Colors.grey[400],
              size: 22),
          const SizedBox(width: 12),
          Icon(icon,
              color: isSelected ? activeColor : Colors.grey[400], size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color:
                          isSelected ? activeColor : Colors.grey[700]))),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// FINALIZE DECISION DIALOG
// ═══════════════════════════════════════════════════════════════════
class _FinalizeDecisionDialog extends StatefulWidget {
  final Map<String, dynamic> disciplineCase;
  final VoidCallback onFinalized;
  const _FinalizeDecisionDialog(
      {required this.disciplineCase, required this.onFinalized});
  @override
  State<_FinalizeDecisionDialog> createState() =>
      _FinalizeDecisionDialogState();
}

class _FinalizeDecisionDialogState extends State<_FinalizeDecisionDialog> {
  final supabase = Supabase.instance.client;
  String? _finalPenalty;
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;
  bool get _canFinalize => _finalPenalty != null;

  @override
  void initState() {
    super.initState();
    // FIX: was checking `rec == 'terminated' || rec == 'terminated'` (duplicate)
    // now correctly handles both old and new values
    final rec = widget.disciplineCase['penalty_recommendation'] as String?;
    if (rec == 'permanently_terminated' || rec == 'terminated') {
      _finalPenalty = 'terminated';
    } else if (rec == 'suspended_1_semester') {
      _finalPenalty = 'suspended_1_semester';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatPenalty(String penalty) {
    switch (penalty) {
      case 'terminated':
        return 'Permanently Terminated';
      case 'suspended_1_semester':
        return 'Suspended for 1 Semester';
      default:
        return penalty;
    }
  }

  Future<void> _finalize() async {
    if (!_canFinalize) return;
    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now().toIso8601String();
      final userId = supabase.auth.currentUser?.id;

      await supabase.from('liabilities_version2').update({
        'penalty_status': _finalPenalty,
        'final_penalty_status': _finalPenalty,
        'final_penalty_set_by': userId,
        'final_penalty_set_at': now,
        'final_penalty_remarks': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      }).eq('id', widget.disciplineCase['id']);

      final applicationId = widget.disciplineCase['application_id'];
      if (applicationId != null) {
        await supabase.from('borrowing_applications_version2').update({
          'penalty_status': _finalPenalty,
        }).eq('id', applicationId);

        await supabase.from('borrowing_sessions').update({
          'status': _finalPenalty,
        }).eq('application_id', applicationId);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Decision finalized: ${_formatPenalty(_finalPenalty!)}'),
          backgroundColor: const Color(0xFF388E3C),
          duration: const Duration(seconds: 3),
        ));
        widget.onFinalized();
      }
    } catch (e) {
      debugPrint('Finalize error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gsoRec =
        widget.disciplineCase['penalty_recommendation'] as String? ?? '';
    final borrowerName =
        widget.disciplineCase['borrower_name'] ?? 'Unknown';
    final idNo = widget.disciplineCase['id_no']?.toString() ?? 'N/A';
    final bikeNumber = widget.disciplineCase['bike_number'] ?? 'N/A';
    final notes = widget.disciplineCase['forwarded_notes'];
    final assessmentRemarks = widget.disciplineCase['assessment_remarks'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(28),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.gavel_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Finalize Discipline Decision',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  Text(borrowerName,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600])),
                ])),
            IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFF7B1FA2).withOpacity(0.3)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.info_outline_rounded,
                                  color: Color(0xFF7B1FA2), size: 18),
                              SizedBox(width: 8),
                              Text('Case Summary',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF7B1FA2))),
                            ]),
                            const SizedBox(height: 12),
                            _caseRow('Student', borrowerName),
                            _caseRow('ID No', idNo),
                            _caseRow('Bike Number', bikeNumber),
                            if (notes != null &&
                                notes.toString().isNotEmpty)
                              _caseRow(
                                  'Forwarded Notes', notes.toString()),
                            if (assessmentRemarks != null &&
                                assessmentRemarks.toString().isNotEmpty)
                              _caseRow('Assessment',
                                  assessmentRemarks.toString()),
                          ]),
                    ),
                    const SizedBox(height: 20),
                    if (gsoRec.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFD32F2F)
                                  .withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.assignment_rounded,
                              color: Color(0xFFD32F2F), size: 16),
                          const SizedBox(width: 8),
                          Text('GSO Recommended: ',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600)),
                          Text(_formatPenalty(gsoRec),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD32F2F))),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          'Pre-selected based on GSO recommendation. You may change it.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(height: 16),
                    ],
                    const Text('Final Penalty Decision *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text(
                        'This decision is final and will be applied to the student.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[500])),
                    const SizedBox(height: 12),
                    _penaltyOption(
                        value: 'terminated',
                        label: 'Permanently Terminated',
                        description:
                            'Student is permanently banned from the PedalHub bike borrowing program.',
                        icon: Icons.block_rounded,
                        color: const Color(0xFFD32F2F)),
                    const SizedBox(height: 10),
                    _penaltyOption(
                        value: 'suspended_1_semester',
                        label: 'Suspended for 1 Semester',
                        description:
                            'Student cannot borrow a bike for the next full semester.',
                        icon: Icons.pause_circle_rounded,
                        color: const Color(0xFFE65100)),
                    const SizedBox(height: 24),
                    const Text('Decision Notes (optional)',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Add any notes or justification for this decision...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF7B1FA2), width: 2)),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                      ),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: Colors.grey[600]))),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canFinalize
                      ? const Color(0xFF7B1FA2)
                      : Colors.grey[300],
                  foregroundColor:
                      _canFinalize ? Colors.white : Colors.grey[500],
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: _canFinalize ? 2 : 0,
                ),
                onPressed:
                    (_canFinalize && !_isSubmitting) ? _finalize : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.gavel_rounded, size: 18),
                label: Text(
                    _isSubmitting ? 'Finalizing...' : 'Finalize Decision',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _penaltyOption(
      {required String value,
      required String label,
      required String description,
      required IconData icon,
      required Color color}) {
    final isSelected = _finalPenalty == value;
    return GestureDetector(
      onTap: () => setState(() => _finalPenalty = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? color
                            : const Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text(description,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
          Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey[400],
              size: 22),
        ]),
      ),
    );
  }

  Widget _caseRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600]))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}