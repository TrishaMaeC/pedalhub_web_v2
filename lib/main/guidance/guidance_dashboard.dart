// lib/main/guidance/guidance_dashboard.dart

import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/rejection_reason_dialog.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

class GuidanceRenewalApprovalPage extends StatefulWidget {
  const GuidanceRenewalApprovalPage({super.key});

  @override
  State<GuidanceRenewalApprovalPage> createState() =>
      _GuidanceRenewalApprovalPageState();
}

class _GuidanceRenewalApprovalPageState
    extends State<GuidanceRenewalApprovalPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _mainTabController;

  bool isLoading = true;
  String selectedStatus = 'renewal_health';
  List<Map<String, dynamic>> applications = [];

  int pendingCount = 0;
  int approvedCount = 0;
  int rejectedCount = 0;

  String selectedDisciplineTab = 'open';
  List<Map<String, dynamic>> disciplineCases = [];
  int openCasesCount = 0;
  int resolvedCasesCount = 0;

  String? userCampus;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _mainTabController.addListener(() {
      if (_mainTabController.indexIsChanging) return;
      if (_mainTabController.index == 1) _fetchDisciplineCases();
    });
    _loadUserCampusAndAll();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
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
      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      _loadAll();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user profile: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Student check: sr_code has value = student, sr_code null = personnel
  bool _isStudent(Map<String, dynamic> record) {
    final srCode = record['sr_code'];
    return srCode != null && srCode.toString().trim().isNotEmpty;
  }

  Future<void> _loadAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([_loadMetrics(), _fetchApplications(), _fetchDisciplineCases()]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadMetrics() async {
    final pending = await supabase
        .from('renewal_applications')
        .select('id')
        .eq('status', 'renewal_health')
        .eq('is_personnel', false)
        .ilike('campus', userCampus!);

    final approvedGuidance = await supabase
        .from('renewal_applications')
        .select('id')
        .eq('status', 'renewal_guidance')
        .eq('is_personnel', false)
        .ilike('campus', userCampus!);

    final approvedChancellor = await supabase
        .from('renewal_applications')
        .select('id')
        .eq('status', 'renewal_chancellor')
        .eq('is_personnel', false)
        .ilike('campus', userCampus!);

    final approvedGso = await supabase
        .from('renewal_applications')
        .select('id')
        .eq('status', 'renewal_gso')
        .eq('is_personnel', false)
        .ilike('campus', userCampus!);

    final rejected = await supabase
        .from('renewal_applications')
        .select('id')
        .eq('status', 'renewal_guidance_rejected')
        .eq('is_personnel', false)
        .ilike('campus', userCampus!);

    // Use sr_code directly from student_discipline — not null = student
    final openRaw = await supabase
        .from('student_discipline')
        .select('id, sr_code')
        .eq('status', 'open')
        .ilike('campus', userCampus!);

    final resolvedRaw = await supabase
        .from('student_discipline')
        .select('id, sr_code')
        .eq('status', 'resolved')
        .ilike('campus', userCampus!);

    setState(() {
      pendingCount = (pending as List).length;
      approvedCount = (approvedGuidance as List).length +
          (approvedChancellor as List).length +
          (approvedGso as List).length;
      rejectedCount = (rejected as List).length;

      openCasesCount = (openRaw as List).where((c) => _isStudent(c)).length;
      resolvedCasesCount = (resolvedRaw as List).where((c) => _isStudent(c)).length;
    });
  }

  Future<void> _fetchApplications() async {
    if (userCampus == null) return;
    final response = await supabase
        .from('renewal_applications')
        .select('*')
        .eq('status', selectedStatus)
        .eq('is_personnel', false)
        .ilike('campus', userCampus!)
        .order('created_at', ascending: false);

    setState(() => applications = List<Map<String, dynamic>>.from(response));
  }

  Future<void> _fetchDisciplineCases() async {
    if (userCampus == null) return;
    try {
      final response = await supabase
          .from('student_discipline')
          .select('*')
          .eq('status', selectedDisciplineTab)
          .ilike('campus', userCampus!)
          .order('forwarded_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response);

      // Students only: sr_code not null = student
      final filtered = list.where((c) => _isStudent(c)).toList();

      setState(() => disciplineCases = filtered);
    } catch (e) {
      debugPrint('Fetch discipline cases error: $e');
    }
  }

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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await supabase.auth.signOut();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
    }
  }

  void _showCertifyDialog(Map<String, dynamic> app) {
    final applicantName = '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GuidanceCertifyDialog(
        applicationId: app['id'].toString(),
        applicantName: applicantName,
        onApproved: _loadAll,
      ),
    );
  }

  void _showRejectDialog(Map<String, dynamic> app) {
    final applicantName = '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();
    RejectionReasonDialog.show(
      context: context,
      applicantName: applicantName,
      onReject: (reason) async {
        try {
          await supabase.from('renewal_applications').update({
            'status': 'renewal_guidance_rejected',
            'rejection_reason': reason,
            'hrmo_remarks': reason,
            'hrmo_approval_date': DateTime.now().toIso8601String(),
          }).eq('id', app['id']);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Application rejected.'), backgroundColor: Colors.orange),
            );
          }
          await _loadAll();
        } catch (e) {
          debugPrint('Reject error: $e');
        }
      },
    );
  }

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
                top: 16, left: 16,
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded), color: Colors.red,
                  iconSize: 28, tooltip: 'Logout', onPressed: _confirmLogout,
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
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              tabs: [
                const Tab(icon: Icon(Icons.how_to_reg_rounded), text: 'Renewal Approval'),
                Tab(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.gavel_rounded),
                      if (openCasesCount > 0)
                        Positioned(
                          right: -8, top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle),
                            child: Text(openCasesCount.toString(),
                                style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  text: 'Discipline Cases',
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F))))
                : TabBarView(controller: _mainTabController, children: [_buildRenewalTab(), _buildDisciplineTab()]),
          ),
        ],
      ),
    );
  }

  Widget _buildRenewalTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageTitle(), const SizedBox(height: 32),
            _buildMetricCards(), const SizedBox(height: 32),
            _buildFilterTabs(), const SizedBox(height: 24),
            _buildApplicationList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDisciplineTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _fetchDisciplineCases,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDisciplineTitle(), const SizedBox(height: 24),
            _buildDisciplineSummaryCards(), const SizedBox(height: 24),
            _buildDisciplineFilterTabs(), const SizedBox(height: 20),
            _buildDisciplineCasesList(),
          ],
        ),
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
              gradient: const LinearGradient(colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Discipline Cases',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              Text(
                userCampus != null
                    ? 'Campus: ${userCampus!.toUpperCase()}  •  Finalize penalty decisions'
                    : 'Finalize penalty decisions for liability cases',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ]),
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _fetchDisciplineCases, color: Colors.grey[600]),
      ],
    );
  }

  Widget _buildDisciplineSummaryCards() {
    return Row(children: [
      _disciplineSummaryCard(label: 'Open Cases', count: openCasesCount, icon: Icons.pending_actions_rounded, color: const Color(0xFFD32F2F)),
      const SizedBox(width: 16),
      _disciplineSummaryCard(label: 'Resolved Cases', count: resolvedCasesCount, icon: Icons.check_circle_rounded, color: const Color(0xFF388E3C)),
    ]);
  }

  Widget _disciplineSummaryCard({required String label, required int count, required IconData icon, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(count.toString(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ]),
        ]),
      ),
    );
  }

  Widget _buildDisciplineFilterTabs() {
    return Row(children: [
      _disciplineFilterTab(value: 'open', label: 'Open Cases', icon: Icons.pending_actions_rounded, color: const Color(0xFFD32F2F), count: openCasesCount),
      const SizedBox(width: 12),
      _disciplineFilterTab(value: 'resolved', label: 'Resolved', icon: Icons.check_circle_rounded, color: const Color(0xFF388E3C), count: resolvedCasesCount),
    ]);
  }

  Widget _disciplineFilterTab({required String value, required String label, required IconData icon, required Color color, required int count}) {
    final isSelected = selectedDisciplineTab == value;
    return GestureDetector(
      onTap: () { setState(() => selectedDisciplineTab = value); _fetchDisciplineCases(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: 1.5),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: isSelected ? Colors.white : color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : color)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.3) : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(99)),
              child: Text(count.toString(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : color)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildDisciplineCasesList() {
    if (disciplineCases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(children: [
            Icon(Icons.inbox_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(selectedDisciplineTab == 'open' ? 'No open discipline cases' : 'No resolved cases yet',
                style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w500)),
          ]),
        ),
      );
    }
    return Column(children: disciplineCases.map((c) => _disciplineCaseCard(c)).toList());
  }

  Widget _disciplineCaseCard(Map<String, dynamic> disciplineCase) {
    final isOpen = disciplineCase['status'] == 'open';
    final isRenewal = disciplineCase['renewal_application_id'] != null;
    final penaltyRec = _formatPenalty(disciplineCase['penalty_recommendation'] as String? ?? '');
    final finalPenalty = _formatPenalty(disciplineCase['final_penalty'] as String? ?? '');

    String forwardedAtLabel = 'N/A';
    try {
      final dt = DateTime.parse(disciplineCase['forwarded_at'].toString()).toLocal();
      forwardedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {}

    String resolvedAtLabel = '';
    if (!isOpen && disciplineCase['decided_at'] != null) {
      try {
        final dt = DateTime.parse(disciplineCase['decided_at'].toString()).toLocal();
        resolvedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
      } catch (_) {}
    }

    final Color statusColor = isOpen ? const Color(0xFFD32F2F) : const Color(0xFF388E3C);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(isOpen ? Icons.pending_actions_rounded : Icons.check_circle_rounded, color: statusColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(disciplineCase['borrower_name'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                    const SizedBox(width: 8),
                    _chip(isOpen ? 'Open Case' : 'Resolved', statusColor),
                    const SizedBox(width: 6),
                    _chip(isRenewal ? 'Renewal' : 'New', isRenewal ? const Color(0xFF7B1FA2) : const Color(0xFF1565C0)),
                  ]),
                  const SizedBox(height: 4),
                  if (disciplineCase['sr_code'] != null)
                    Text('SR Code: ${disciplineCase['sr_code']}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isOpen)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showFinalizeDialog(disciplineCase),
                icon: const Icon(Icons.gavel_rounded, size: 18),
                label: const Text('Finalize Decision', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _detailItem(Icons.pedal_bike_rounded, 'Bike', disciplineCase['bike_number'] ?? 'N/A')),
            Expanded(child: _detailItem(Icons.access_time_rounded, 'Forwarded', forwardedAtLabel)),
            Expanded(child: _detailItem(Icons.warning_amber_rounded, 'Days Overdue', '${disciplineCase['days_overdue'] ?? 0}')),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.assignment_rounded, color: Color(0xFFD32F2F), size: 16),
              const SizedBox(width: 8),
              Text('GSO Recommendation: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              Text(penaltyRec.isEmpty ? 'None provided' : penaltyRec,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
            ]),
          ),
          if (!isOpen && finalPenalty.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF388E3C).withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.gavel_rounded, color: Color(0xFF388E3C), size: 16),
                const SizedBox(width: 8),
                Text('Final Decision: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                Text(finalPenalty, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF388E3C))),
                if (resolvedAtLabel.isNotEmpty) ...[
                  const Spacer(),
                  Text(resolvedAtLabel, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ]),
            ),
          ],
          if (disciplineCase['notes'] != null && disciplineCase['notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.notes_rounded, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(child: Text('Notes: ${disciplineCase['notes']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic))),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  String _formatPenalty(String penalty) {
    switch (penalty) {
      case 'permanently_terminated': return 'Permanently Terminated';
      case 'suspended_1_semester': return 'Suspended for 1 Semester';
      default: return '';
    }
  }

  Widget _buildPageTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF9C27B0)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Student Discipline Office',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
            Text(
              userCampus != null
                  ? 'Campus: ${userCampus!.toUpperCase()}  •  Review renewal applications & manage discipline cases'
                  : 'Review renewal applications & manage discipline cases',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ]),
        ]),
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadAll, tooltip: 'Refresh', color: Colors.grey[600]),
      ],
    );
  }

  Widget _buildMetricCards() {
    return Row(children: [
      Expanded(child: _metricCard(label: 'Pending', count: pendingCount, icon: Icons.pending_actions_rounded, gradient: const LinearGradient(colors: [Color(0xFFF57C00), Color(0xFFFFB74D)]))),
      const SizedBox(width: 20),
      Expanded(child: _metricCard(label: 'Approved', count: approvedCount, icon: Icons.check_circle_rounded, gradient: const LinearGradient(colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]))),
      const SizedBox(width: 20),
      Expanded(child: _metricCard(label: 'Rejected', count: rejectedCount, icon: Icons.cancel_rounded, gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFE57373)]))),
    ]);
  }

  Widget _metricCard({required String label, required int count, required IconData icon, required Gradient gradient}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 20),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(count.toString(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }

  Widget _buildFilterTabs() {
    return Row(children: [
      _filterTab(value: 'renewal_health', label: 'Pending', icon: Icons.pending_actions_rounded, color: const Color(0xFFF57C00)),
      const SizedBox(width: 12),
      _filterTab(value: 'renewal_guidance', label: 'Approved', icon: Icons.check_circle_rounded, color: const Color(0xFF388E3C)),
      const SizedBox(width: 12),
      _filterTab(value: 'renewal_guidance_rejected', label: 'Rejected', icon: Icons.cancel_rounded, color: const Color(0xFFD32F2F)),
    ]);
  }

  Widget _filterTab({required String value, required String label, required IconData icon, required Color color}) {
    final isSelected = selectedStatus == value;
    return GestureDetector(
      onTap: () { setState(() => selectedStatus = value); _fetchApplications(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: 1.5),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: isSelected ? Colors.white : color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : color)),
        ]),
      ),
    );
  }

  Widget _buildApplicationList() {
    if (applications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(children: [
            Icon(Icons.inbox_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              selectedStatus == 'renewal_health' ? 'No pending applications'
                  : selectedStatus == 'renewal_guidance' ? 'No approved applications' : 'No rejected applications',
              style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      );
    }
    return Column(children: applications.map((app) => _applicationCard(app)).toList());
  }

  Widget _applicationCard(Map<String, dynamic> app) {
    final firstName = app['first_name'] ?? '';
    final lastName = app['last_name'] ?? '';
    final idNumber = app['id_number'] ?? 'N/A';
    final programOrOffice = app['program_or_office'] ?? 'N/A';
    final bikeNumber = app['bike_number'] ?? 'N/A';
    final status = app['status'] ?? '';
    final isPending = status == 'renewal_health';
    final isApproved = status == 'renewal_guidance';
    final Color statusColor = isPending ? const Color(0xFFF57C00) : isApproved ? const Color(0xFF388E3C) : const Color(0xFFD32F2F);
    final String statusLabel = isPending ? 'Pending Review' : isApproved ? 'Approved' : 'Rejected';
    final IconData statusIcon = isPending ? Icons.pending_actions_rounded : isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
          child: Icon(statusIcon, color: statusColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$firstName $lastName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withOpacity(0.1), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1976D2))),
                child: const Text('Student', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1976D2))),
              ),
            ]),
            const SizedBox(height: 4),
            Text('ID: $idNumber  •  Program: $programOrOffice', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 2),
            Text('Bike No: $bikeNumber', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor, width: 1)),
              child: Text(statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
            ),
          ]),
        ),
        Wrap(
          spacing: 8, runSpacing: 8, alignment: WrapAlignment.end,
          children: [
            if (isPending) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF388E3C), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showCertifyDialog(app),
                icon: const Icon(Icons.verified_rounded, size: 18),
                label: const Text('Certify', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showRejectDialog(app),
                icon: const Icon(Icons.cancel_rounded, size: 18),
                label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// FINALIZE DECISION DIALOG
// ═══════════════════════════════════════════════════════════════════
class _FinalizeDecisionDialog extends StatefulWidget {
  final Map<String, dynamic> disciplineCase;
  final VoidCallback onFinalized;
  const _FinalizeDecisionDialog({required this.disciplineCase, required this.onFinalized});
  @override
  State<_FinalizeDecisionDialog> createState() => _FinalizeDecisionDialogState();
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
    final rec = widget.disciplineCase['penalty_recommendation'] as String?;
    if (rec != null && rec.isNotEmpty) _finalPenalty = rec;
  }

  @override
  void dispose() { _notesController.dispose(); super.dispose(); }

  String _formatPenalty(String penalty) {
    switch (penalty) {
      case 'permanently_terminated': return 'Permanently Terminated';
      case 'suspended_1_semester': return 'Suspended for 1 Semester';
      default: return penalty;
    }
  }

  Future<void> _finalize() async {
    if (!_canFinalize) return;
    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now().toIso8601String();
      final userId = supabase.auth.currentUser?.id;
      final caseId = widget.disciplineCase['id'];
      final appId = widget.disciplineCase['application_id'];
      final renewalAppId = widget.disciplineCase['renewal_application_id'];

      await supabase.from('student_discipline').update({
        'status': 'resolved', 'final_penalty': _finalPenalty,
        'final_decision_notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'decided_by': userId, 'decided_at': now, 'notification_sent': true,
      }).eq('id', caseId);

      await supabase.from('liabilities').update({'status': 'resolved', 'resolved_at': now})
          .eq('id', widget.disciplineCase['liability_id']);

      if (renewalAppId != null) {
        await supabase.from('renewal_applications').update({'status': _finalPenalty, 'final_penalty': _finalPenalty}).eq('id', renewalAppId);
      } else if (appId != null) {
        await supabase.from('borrowing_applications').update({'status': _finalPenalty, 'final_penalty': _finalPenalty}).eq('id', appId);
      }

      if (renewalAppId != null) {
        final renewal = await supabase.from('renewal_applications').select('session_id').eq('id', renewalAppId).maybeSingle();
        if (renewal != null && renewal['session_id'] != null) {
          await supabase.from('borrowing_sessions').update({'status': _finalPenalty}).eq('id', renewal['session_id']);
        }
      } else if (appId != null) {
        await supabase.from('borrowing_sessions').update({'status': _finalPenalty}).eq('application_id', appId);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Decision finalized: ${_formatPenalty(_finalPenalty!)}'),
          backgroundColor: const Color(0xFF388E3C), duration: const Duration(seconds: 3),
        ));
        widget.onFinalized();
      }
    } catch (e) {
      debugPrint('Finalize error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gsoRec = widget.disciplineCase['penalty_recommendation'] as String? ?? '';
    final borrowerName = widget.disciplineCase['borrower_name'] ?? 'Unknown';
    final srCode = widget.disciplineCase['sr_code'];
    final bikeNumber = widget.disciplineCase['bike_number'] ?? 'N/A';
    final daysOverdue = widget.disciplineCase['days_overdue'] ?? 0;
    final notes = widget.disciplineCase['notes'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Finalize Discipline Decision',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                Text(borrowerName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ])),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF7B1FA2), size: 18),
                        const SizedBox(width: 8),
                        const Text('Case Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF7B1FA2))),
                      ]),
                      const SizedBox(height: 12),
                      _caseRow('Borrower', borrowerName),
                      if (srCode != null) _caseRow('SR Code', srCode),
                      _caseRow('Bike Number', bikeNumber),
                      _caseRow('Days Overdue', daysOverdue.toString()),
                      if (notes != null && notes.toString().isNotEmpty) _caseRow('GSO Notes', notes),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  if (gsoRec.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.assignment_rounded, color: Color(0xFFD32F2F), size: 16),
                        const SizedBox(width: 8),
                        Text('GSO Recommended: ', style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                        Text(_formatPenalty(gsoRec), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text('Pre-selected based on GSO recommendation. You may change it.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 16),
                  ],
                  const Text('Final Penalty Decision *',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  Text('This decision is final and will be applied to the student.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(height: 12),
                  _penaltyOption(value: 'permanently_terminated', label: 'Permanently Terminated',
                      description: 'Student is permanently banned from the PedalHub bike borrowing program.',
                      icon: Icons.block_rounded, color: const Color(0xFFD32F2F)),
                  const SizedBox(height: 10),
                  _penaltyOption(value: 'suspended_1_semester', label: 'Suspended for 1 Semester',
                      description: 'Student cannot borrow a bike for the next full semester.',
                      icon: Icons.pause_circle_rounded, color: const Color(0xFFE65100)),
                  const SizedBox(height: 24),
                  const Text('Decision Notes (optional)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController, maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add any notes or justification for this decision...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF7B1FA2), width: 2)),
                      filled: true, fillColor: const Color(0xFFFAFAFA),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.grey[600]))),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canFinalize ? const Color(0xFF7B1FA2) : Colors.grey[300],
                    foregroundColor: _canFinalize ? Colors.white : Colors.grey[500],
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: _canFinalize ? 2 : 0,
                  ),
                  onPressed: (_canFinalize && !_isSubmitting) ? _finalize : null,
                  icon: _isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.gavel_rounded, size: 18),
                  label: Text(_isSubmitting ? 'Finalizing...' : 'Finalize Decision',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _penaltyOption({required String value, required String label, required String description, required IconData icon, required Color color}) {
    final isSelected = _finalPenalty == value;
    return GestureDetector(
      onTap: () => setState(() => _finalPenalty = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))] : [],
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? color : const Color(0xFF1A1A1A))),
            const SizedBox(height: 2),
            Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey[400], size: 22),
        ]),
      ),
    );
  }

  Widget _caseRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// GUIDANCE CERTIFY DIALOG
// ═══════════════════════════════════════════════════════════════════
class _GuidanceCertifyDialog extends StatefulWidget {
  final String applicationId;
  final String applicantName;
  final VoidCallback onApproved;
  const _GuidanceCertifyDialog({required this.applicationId, required this.applicantName, required this.onApproved});
  @override
  State<_GuidanceCertifyDialog> createState() => _GuidanceCertifyDialogState();
}

class _GuidanceCertifyDialogState extends State<_GuidanceCertifyDialog> {
  final supabase = Supabase.instance.client;
  final TextEditingController _signatoryNameController = TextEditingController();
  bool? _hasDisciplinaryAction;
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  bool _isDrawMode = true;
  bool _hasSignature = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _isSubmitting = false;

  bool get _canApprove =>
      _hasDisciplinaryAction != null && _hasSignature && _signatoryNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSignatoryName();
    _signatureController.addListener(() {
      setState(() => _hasSignature = _signatureController.isNotEmpty || _uploadedImageBytes != null);
    });
    _signatoryNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _signatoryNameController.dispose(); _signatureController.dispose(); super.dispose(); }

  Future<void> _loadSignatoryName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final response = await supabase.from('profiles').select('email').eq('id', userId).maybeSingle();
        if (response != null && mounted) {
          final email = response['email'] as String;
          _signatoryNameController.text = email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) { debugPrint('Error loading signatory name: $e'); }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final bytes = result.files.first.bytes;
      final fileName = result.files.first.name;
      if (bytes != null) setState(() { _uploadedImageBytes = bytes; _uploadedFileName = fileName; _hasSignature = true; });
    }
  }

  Future<String?> _uploadSignature(Uint8List bytes, String fileName) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';
      final path = 'discipline_signatures/${userId}_${timestamp}_$fileName';
      await supabase.storage.from('signatures').uploadBinary(path, bytes);
      return supabase.storage.from('signatures').getPublicUrl(path);
    } catch (e) { debugPrint('Upload error: $e'); return null; }
  }

  Future<void> _approve() async {
    if (!_canApprove) return;
    setState(() => _isSubmitting = true);
    try {
      Uint8List? sigBytes;
      String fileName;
      if (_isDrawMode) {
        sigBytes = await _signatureController.toPngBytes();
        if (sigBytes == null) throw Exception('Failed to export drawn signature');
        fileName = 'drawn_signature.png';
      } else {
        sigBytes = _uploadedImageBytes;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }
      final signatureUrl = await _uploadSignature(sigBytes!, fileName);
      if (signatureUrl == null) throw Exception('Signature upload failed');

      await supabase.from('renewal_applications').update({
        'status': 'renewal_guidance',
        'hrmo_signature_url': signatureUrl,
        'hrmo_signatory_name': _signatoryNameController.text.trim(),
        'hrmo_approval_date': DateTime.now().toIso8601String(),
        'hrmo_remarks': _hasDisciplinaryAction == true
            ? 'Has disciplinary actions with final judgement relating to government properties'
            : 'Has no disciplinary actions with final judgement relating to government properties',
      }).eq('id', widget.applicationId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application certified and approved.'), backgroundColor: Color(0xFF388E3C)),
        );
      }
      widget.onApproved();
    } catch (e) {
      debugPrint('Certify error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Certify Application', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              Text(widget.applicantName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Disciplinary Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                Text('Select the applicable disciplinary status for this applicant:', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 14),
                _disciplinaryOption(value: false,
                    label: 'Has no disciplinary actions with final judgement relating to government properties',
                    icon: Icons.check_circle_outline_rounded, activeColor: const Color(0xFF388E3C)),
                const SizedBox(height: 10),
                _disciplinaryOption(value: true,
                    label: 'Has disciplinary actions with final judgement relating to government properties',
                    icon: Icons.warning_amber_rounded, activeColor: const Color(0xFFD32F2F)),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 20),
                const Text('Signatory Name *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 8),
                TextField(
                  controller: _signatoryNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter your full name', prefixIcon: const Icon(Icons.badge_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Signature *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                Text('Draw or upload your signature to certify this application:', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(8)),
                        child: _isDrawMode
                            ? ClipRRect(borderRadius: BorderRadius.circular(8),
                                child: Signature(controller: _signatureController, backgroundColor: Colors.white))
                            : _uploadedImageBytes == null
                                ? Center(child: ElevatedButton.icon(
                                    onPressed: _pickImage,
                                    icon: const Icon(Icons.upload_file, size: 20),
                                    label: const Text('Upload Signature'),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white),
                                  ))
                                : ClipRRect(borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(_uploadedImageBytes!, fit: BoxFit.contain)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(children: [
                      IconButton(
                        icon: const Icon(Icons.clear), tooltip: 'Clear signature',
                        onPressed: () { _signatureController.clear(); setState(() { _uploadedImageBytes = null; _hasSignature = false; }); },
                      ),
                      IconButton(
                        icon: Icon(_isDrawMode ? Icons.upload_file : Icons.edit),
                        tooltip: _isDrawMode ? 'Switch to Upload' : 'Switch to Draw',
                        onPressed: () { setState(() { _isDrawMode = !_isDrawMode; _uploadedImageBytes = null; _hasSignature = _signatureController.isNotEmpty; }); },
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isDrawMode ? 'Draw your signature in the box above' : 'Click "Upload Signature" to choose an image file',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.grey[600]))),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canApprove ? const Color(0xFF388E3C) : Colors.grey[300],
                  foregroundColor: _canApprove ? Colors.white : Colors.grey[500],
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _canApprove && !_isSubmitting ? _approve : null,
                icon: _isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_rounded, size: 18),
                label: Text(_isSubmitting ? 'Certifying...' : 'Approve',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _disciplinaryOption({required bool value, required String label, required IconData icon, required Color activeColor}) {
    final isSelected = _hasDisciplinaryAction == value;
    return GestureDetector(
      onTap: () => setState(() => _hasDisciplinaryAction = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? activeColor : Colors.grey[300]!, width: isSelected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? activeColor : Colors.grey[400], size: 22),
          const SizedBox(width: 12),
          Icon(icon, color: isSelected ? activeColor : Colors.grey[400], size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? activeColor : Colors.grey[700]))),
        ]),
      ),
    );
  }
}