import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TerminationPage extends StatefulWidget {
  const TerminationPage({super.key});

  @override
  State<TerminationPage> createState() => _TerminationPageState();
}

class _TerminationPageState extends State<TerminationPage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  String selectedTab = 'monitoring';
  String? userCampus;

  List<Map<String, dynamic>> overdueList = [];
  List<Map<String, dynamic>> forTerminationList = [];
  List<Map<String, dynamic>> needsActionList = [];
  List<Map<String, dynamic>> forwardedList = [];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initPage();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 60), (_) { if (mounted) _fetchAll(); });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPage() async {
    await _loadUserCampus();
    await _fetchAll();
  }

  Future<void> _loadUserCampus() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();
      setState(() =>
          userCampus = (profile['campus'] as String).toLowerCase());
    } catch (e) {
      debugPrint('Campus load error: $e');
    }
  }

  Future<void> _fetchAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchMonitoring(),
        _fetchNeedsAction(),
        _fetchForwarded(),
      ]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  // FETCH
  // ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchWithSession(
      List<String> statuses) async {
    final response = await supabase
        .from('borrowing_applications_version2')
        .select('*')
        .inFilter('penalty_status', statuses)
        .ilike('campus', userCampus!)
        .order('updated_at', ascending: false);

    final apps = List<Map<String, dynamic>>.from(response);
    return await Future.wait(apps.map((app) async {
      try {
        final session = await supabase
            .from('borrowing_sessions')
            .select(
                'id, bike_id, start_time, end_time, actual_return_time, expected_return_time, status')
            .eq('application_id', app['id'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return {...app, 'session': session};
      } catch (_) {
        return {...app, 'session': null};
      }
    }));
  }

  Future<void> _fetchMonitoring() async {
    try {
      final results =
          await _fetchWithSession(['overdue', 'for_termination']);
      if (mounted) {
        setState(() {
          overdueList = results
              .where((a) => a['penalty_status'] == 'overdue')
              .toList();
          forTerminationList = results
              .where((a) => a['penalty_status'] == 'for_termination')
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Fetch monitoring error: $e');
    }
  }

  Future<void> _fetchNeedsAction() async {
    try {
      final results = await _fetchWithSession([
        'returned_overdue',
        'returned_terminated',
        'damaged_bike',
        'missing_bike',
      ]);
      if (mounted) setState(() => needsActionList = results);
    } catch (e) {
      debugPrint('Fetch needs action error: $e');
    }
  }

  Future<void> _fetchForwarded() async {
    try {
      final results = await _fetchWithSession(
          ['forwarded_discipline', 'forwarded_hrmo']);
      if (mounted) setState(() => forwardedList = results);
    } catch (e) {
      debugPrint('Fetch forwarded error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────
  void _showReturnDialog(Map<String, dynamic> app) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TerminationReturnDialog(
        application: app,
        session: app['session'],
        onCompleted: () async {
          await _fetchAll();
          if (mounted) setState(() => selectedTab = 'needs_action');
        },
      ),
    );
  }

  Future<void> _forwardCase(Map<String, dynamic> app) async {
    final isStudent =
        (app['user_type'] ?? '').toString().toLowerCase() == 'student';
    final targetStatus =
        isStudent ? 'forwarded_discipline' : 'forwarded_hrmo';
    final targetLabel = isStudent ? 'Student Discipline' : 'HRMO';
    final penaltyStatus = app['penalty_status'] ?? '';

    String reason = 'late_return';
    if (penaltyStatus == 'damaged_bike') reason = 'damaged_bike';
    if (penaltyStatus == 'missing_bike') reason = 'missing_bike';

    final confirmed = await _showConfirmDialog(
      title: 'Forward to $targetLabel',
      message:
          'Forward ${app['first_name']} ${app['last_name']}\'s case to $targetLabel?',
      confirmLabel: 'Forward',
      confirmColor: const Color(0xFF7B1FA2),
    );
    if (!confirmed) return;

    final notesController = TextEditingController();
    String? penaltyRec;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Forward to $targetLabel',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Penalty Recommendation',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _penaltyOptionInline(
                  label: 'Permanently Terminated',
                  value: 'terminated',
                  selected: penaltyRec,
                  color: const Color(0xFFD32F2F),
                  icon: Icons.block_rounded,
                  onTap: () => setS(() => penaltyRec = 'terminated'),
                ),
                const SizedBox(height: 8),
                _penaltyOptionInline(
                  label: 'Suspended for 1 Semester',
                  value: 'suspended_1_semester',
                  selected: penaltyRec,
                  color: const Color(0xFFE65100),
                  icon: Icons.pause_circle_rounded,
                  onTap: () =>
                      setS(() => penaltyRec = 'suspended_1_semester'),
                ),
                const SizedBox(height: 16),
                const Text('Notes (optional)',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add notes...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (penaltyRec == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                      '* Please select a penalty recommendation.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: penaltyRec != null
                      ? const Color(0xFF7B1FA2)
                      : Colors.grey[300],
                  foregroundColor: penaltyRec != null
                      ? Colors.white
                      : Colors.grey[500]),
              onPressed: penaltyRec == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Forward to $targetLabel'),
            ),
          ],
        ),
      ),
    );

    if (proceed != true || penaltyRec == null) return;

    try {
      final session = app['session'];
      final fullName =
          '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();

      // Insert into liabilities_version2
      await supabase.from('liabilities_version2').insert({
        'application_id': app['id'],
        'session_id': session?['id'],
        'user_id': app['user_id'],
        'borrower_name': fullName,
        'id_no': app['id_no'],
        'campus': app['campus'],
        'user_type': app['user_type'],
        'college_office': app['college_office'],
        'bike_number': app['assigned_bike_number'],
        'bike_id': app['assigned_bike_id'],
        'reason': reason,
        'penalty_status': targetStatus,
        'penalty_recommendation': penaltyRec,
        'forwarded_by': supabase.auth.currentUser?.id,
        'forwarded_notes': notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        'tagged_at': app['updated_at'],
        'returned_at': session?['actual_return_time'],
      });

      // Update borrowing_applications_version2
      await supabase
          .from('borrowing_applications_version2')
          .update({'penalty_status': targetStatus})
          .eq('id', app['id']);

      // Update borrowing_sessions
      if (session != null) {
        await supabase
            .from('borrowing_sessions')
            .update({'status': targetStatus})
            .eq('id', session['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Case forwarded to $targetLabel.'),
            backgroundColor: const Color(0xFF7B1FA2),
          ),
        );
        setState(() => selectedTab = 'forwarded');
        await _fetchAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // DIALOGS
  // ─────────────────────────────────────────────
  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _penaltyOptionInline({
    required String label,
    required String value,
    required String? selected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected ? color : const Color(0xFF1A1A1A)))),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showInspectionDialog(Map<String, dynamic> app) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _InspectionDialog(
      application: app,
      session: app['session'],
      onDamageReported: () async {
        await _fetchAll();
      },
      onClean: () async {
        await _fetchAll();
      },
    ),
  );
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
                    onRefresh: _fetchAll,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageTitle(),
                          const SizedBox(height: 24),
                          _buildSummaryCards(),
                          const SizedBox(height: 24),
                          _buildTabBar(),
                          const SizedBox(height: 20),
                          _buildTabContent(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

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
                    colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.gavel_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Termination Management',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Penalty & Liability Management'
                      : 'Penalty & Liability Management',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _fetchAll,
          tooltip: 'Refresh',
          color: Colors.grey[600],
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    final monitoringCount =
        overdueList.length + forTerminationList.length;
    return Row(
      children: [
        _summaryCard(
          label: 'Monitoring',
          count: monitoringCount,
          icon: Icons.visibility_rounded,
          color: const Color(0xFFE65100),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Needs Action',
          count: needsActionList.length,
          icon: Icons.assignment_late_rounded,
          color: const Color(0xFFD32F2F),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Forwarded',
          count: forwardedList.length,
          icon: Icons.send_rounded,
          color: const Color(0xFF7B1FA2),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(count.toString(),
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final monitoringCount =
        overdueList.length + forTerminationList.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _tabBtn('monitoring', 'Monitoring',
                Icons.visibility_rounded,
                const Color(0xFFE65100), monitoringCount),
            _tabBtn('needs_action', 'Needs Action',
                Icons.assignment_late_rounded,
                const Color(0xFFD32F2F), needsActionList.length),
            _tabBtn('forwarded', 'Forwarded',
                Icons.send_rounded,
                const Color(0xFF7B1FA2), forwardedList.length),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String value, String label, IconData icon,
      Color color, int count) {
    final isSelected = selectedTab == value;
    return GestureDetector(
      onTap: () => setState(() => selectedTab = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? color : Colors.grey[500]),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : Colors.grey[500])),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: isSelected ? color : Colors.grey[400],
                    borderRadius: BorderRadius.circular(99)),
                child: Text(count.toString(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (selectedTab) {
      case 'monitoring':
        return _buildMonitoringTab();
      case 'needs_action':
        return _buildNeedsActionTab();
      case 'forwarded':
        return _buildForwardedTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────
  // TAB CONTENTS
  // ─────────────────────────────────────────────
  Widget _buildMonitoringTab() {
  if (overdueList.isEmpty && forTerminationList.isEmpty) {
    return _emptyState('No active penalty cases',
        Icons.check_circle_outline_rounded, Colors.green);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (forTerminationList.isNotEmpty) ...[
        _sectionHeader('For Termination', Icons.warning_rounded,
            const Color(0xFFD32F2F)),
        const SizedBox(height: 12),
        ...forTerminationList.map((app) => _appCard(app,
            penaltyStatus: 'for_termination',
            color: const Color(0xFFD32F2F),
            action: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReturnDialog(app),
              icon: const Icon(Icons.assignment_return_rounded, size: 18),
              label: const Text('Process Return',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ))),
        const SizedBox(height: 24),
      ],
      if (overdueList.isNotEmpty) ...[
        _sectionHeader('Overdue (Grace Period Active)',
            Icons.hourglass_bottom_rounded,
            const Color(0xFFE65100)),
        const SizedBox(height: 12),
        // ← CHANGED: added Process Return button to overdue cards
        ...overdueList.map((app) => _appCard(app,
            penaltyStatus: 'overdue',
            color: const Color(0xFFE65100),
            action: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReturnDialog(app),
              icon: const Icon(Icons.assignment_return_rounded, size: 18),
              label: const Text('Process Return',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ))),
      ],
    ],
  );
}

  Widget _buildNeedsActionTab() {
  if (needsActionList.isEmpty) {
    return _emptyState('No cases need action',
        Icons.check_circle_outline_rounded, Colors.green);
  }
  return Column(
    children: needsActionList.map((app) {
      final ps = app['penalty_status'] ?? '';
      Color color = const Color(0xFFD32F2F);
      if (ps == 'returned_overdue') color = const Color(0xFFE65100);
      if (ps == 'damaged_bike') color = const Color(0xFFB71C1C);
      if (ps == 'missing_bike') color = Colors.black87;

      Widget? action;

      // returned_overdue — inspect only, no forward button
      // (forward only available after GSO reports damage via dialog)
      if (ps == 'returned_overdue') {
        action = ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00695C),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showInspectionDialog(app),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Inspect',
              style: TextStyle(fontWeight: FontWeight.w600)),
        );
      }

      // returned_terminated, damaged_bike, missing_bike — forward
      if (ps == 'returned_terminated' ||
          ps == 'damaged_bike' ||
          ps == 'missing_bike') {
        action = ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B1FA2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _forwardCase(app),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Forward',
              style: TextStyle(fontWeight: FontWeight.w600)),
        );
      }

      return _appCard(app,
          penaltyStatus: ps, color: color, action: action);
    }).toList(),
  );
}

  Widget _buildForwardedTab() {
    if (forwardedList.isEmpty) {
      return _emptyState('No forwarded cases yet',
          Icons.send_outlined, Colors.purple);
    }
    return Column(
      children: forwardedList
          .map((app) => _appCard(app,
              penaltyStatus: app['penalty_status'],
              color: const Color(0xFF7B1FA2)))
          .toList(),
    );
  }

  // ─────────────────────────────────────────────
  // APP CARD
  // ─────────────────────────────────────────────
  Widget _appCard(
    Map<String, dynamic> app, {
    required String penaltyStatus,
    required Color color,
    Widget? action,
  }) {
    final session = app['session'];
    final fullName =
        '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim();
    final idNo = app['id_no'] ?? 'N/A';
    final bikeNumber = app['assigned_bike_number'] ?? 'N/A';
    final userType = app['user_type'] ?? '';

    String startTimeLabel = 'N/A';
    if (session?['start_time'] != null) {
      try {
        final dt =
            DateTime.parse(session['start_time'].toString()).toLocal();
        startTimeLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
      } catch (_) {}
    }

    String updatedLabel = 'N/A';
    try {
      final dt =
          DateTime.parse(app['updated_at'].toString()).toLocal();
      updatedLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_penaltyIcon(penaltyStatus),
                color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(fullName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 8),
                  _chip(_penaltyLabel(penaltyStatus), color),
                  const SizedBox(width: 6),
                  _chip(
                    userType.toLowerCase() == 'student'
                        ? 'Student'
                        : 'Personnel',
                    userType.toLowerCase() == 'student'
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF2E7D32),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('ID No: $idNo',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.pedal_bike_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Bike: $bikeNumber',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.play_circle_outline,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Started: $startTimeLabel',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.update_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Updated: $updatedLabel',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                ]),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action,
          ],
        ],
      ),
    );
  }

  IconData _penaltyIcon(String status) {
    switch (status) {
      case 'overdue':
        return Icons.hourglass_bottom_rounded;
      case 'for_termination':
        return Icons.warning_rounded;
      case 'returned_overdue':
        return Icons.assignment_return_rounded;
      case 'returned_terminated':
        return Icons.assignment_turned_in_rounded;
      case 'damaged_bike':
        return Icons.build_rounded;
      case 'missing_bike':
        return Icons.search_off_rounded;
      case 'forwarded_discipline':
      case 'forwarded_hrmo':
        return Icons.send_rounded;
      default:
        return Icons.gavel_rounded;
    }
  }

  String _penaltyLabel(String status) {
    switch (status) {
      case 'overdue':
        return 'Overdue';
      case 'for_termination':
        return 'For Termination';
      case 'returned_overdue':
        return 'Returned Overdue';
      case 'returned_terminated':
        return 'Returned (Late)';
      case 'damaged_bike':
        return 'Damaged Bike';
      case 'missing_bike':
        return 'Missing Bike';
      case 'forwarded_discipline':
        return 'Forwarded → Discipline';
      case 'forwarded_hrmo':
        return 'Forwarded → HRMO';
      default:
        return status;
    }
  }

  Widget _sectionHeader(
      String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color)),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  Widget _emptyState(
      String message, IconData icon, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            Icon(icon, size: 72, color: color.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TERMINATION RETURN DIALOG
// ═══════════════════════════════════════════════════════════════════
class _TerminationReturnDialog extends StatefulWidget {
  final Map<String, dynamic> application;
  final Map<String, dynamic>? session;
  final VoidCallback onCompleted;

  const _TerminationReturnDialog({
    required this.application,
    required this.session,
    required this.onCompleted,
  });

  @override
  State<_TerminationReturnDialog> createState() =>
      _TerminationReturnDialogState();
}

class _TerminationReturnDialogState
    extends State<_TerminationReturnDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _showingQr = false;
  bool _isReturned = false;
  bool _isSubmitting = false;
  bool _isDamaged = false;
  bool _isMissing = false;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Bike condition
  bool _frameOk = true;
  bool _wheelsOk = true;
  bool _brakesOk = true;
  bool _chaingearOk = true;
  bool _saddleOk = true;
  bool _lightsOk = true;

  // Damage/missing
  final TextEditingController _damageRemarksController =
      TextEditingController();

  // Assessment remarks
  final TextEditingController _remarksController =
      TextEditingController();

  bool get _allConditionsOk =>
      _frameOk &&
      _wheelsOk &&
      _brakesOk &&
      _chaingearOk &&
      _saddleOk &&
      _lightsOk;

  String get _qrData =>
      'RETURN-${widget.session?['id'] ?? widget.application['id']}';

  String get _startTimeLabel {
    final startTime = widget.session?['start_time'];
    if (startTime == null) return 'N/A';
    try {
      final dt =
          DateTime.parse(startTime.toString()).toLocal();
      return DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {
      return 'N/A';
    }
  }

  String get _durationLabel {
    final startTime = widget.session?['start_time'];
    if (startTime == null) return 'N/A';
    try {
      final start =
          DateTime.parse(startTime.toString()).toLocal();
      final diff = DateTime.now().difference(start);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (hours > 0) return '${hours}h ${minutes}m';
      return '${minutes}m';
    } catch (_) {
      return 'N/A';
    }
  }

  String get _fullName =>
      '${widget.application['first_name'] ?? ''} ${widget.application['last_name'] ?? ''}'
          .trim();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(
            parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _remarksController.dispose();
    _damageRemarksController.dispose();
    if (_channel != null) supabase.removeChannel(_channel!);
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // REPORT DAMAGED — skip QR, forward immediately
  // ─────────────────────────────────────────────
  Future<void> _reportDamaged() async {
    setState(() => _isDamaged = true);
    await _submitDirectForward(
      newPenaltyStatus: 'damaged_bike',
      bikeStatus: 'damaged',
      reason: 'damaged_bike',
    );
  }

  // ─────────────────────────────────────────────
  // REPORT MISSING — skip QR, forward immediately
  // ─────────────────────────────────────────────
  Future<void> _reportMissing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Report Missing Bike',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'This will mark the bike as missing and forward the case. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Missing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isMissing = true);
    await _submitDirectForward(
      newPenaltyStatus: 'missing_bike',
      bikeStatus: 'missing_bike',
      reason: 'missing_bike',
    );
  }

  // ─────────────────────────────────────────────
  // DIRECT FORWARD (damaged / missing)
  // ─────────────────────────────────────────────
  Future<void> _submitDirectForward({
    required String newPenaltyStatus,
    required String bikeStatus,
    required String reason,
  }) async {
    setState(() => _isSubmitting = true);
    try {
      final app = widget.application;
      final session = widget.session;
      final bikeId = app['assigned_bike_id'];

      // Update penalty_status on application
      await supabase
          .from('borrowing_applications_version2')
          .update({'penalty_status': newPenaltyStatus})
          .eq('id', app['id']);

      // Update session status
      if (session != null) {
        await supabase
            .from('borrowing_sessions')
            .update({'status': newPenaltyStatus})
            .eq('id', session['id']);
      }

      // Update bike status
      if (bikeId != null) {
        await supabase
            .from('bikes')
            .update({'status': bikeStatus})
            .eq('id', bikeId);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                reason == 'damaged_bike'
                    ? 'Bike marked as damaged. Please forward the case.'
                    : 'Bike marked as missing. Please forward the case.'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─────────────────────────────────────────────
  // GENERATE RETURN QR
  // ─────────────────────────────────────────────
  Future<void> _generateReturnQr() async {
    setState(() => _isSubmitting = true);
    try {
      await supabase
          .from('borrowing_applications_version2')
          .update({
        'penalty_status': 'for_termination',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.application['id']);

      setState(() {
        _showingQr = true;
        _isSubmitting = false;
      });

      _startRealtimeListener();
      _startPollingFallback();
    } catch (e) {
      debugPrint('QR generate error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _startRealtimeListener() {
    _channel = supabase.channel(
        'termination_app_${widget.application['id']}');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'borrowing_applications_version2',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.application['id'].toString(),
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['penalty_status'];
            if ((newStatus == 'returned_terminated' ||
                    newStatus == 'returned_overdue') &&
                !_isReturned &&
                mounted) {
              _onReturnDetected();
            }
          },
        )
        .subscribe();
  }

  void _startPollingFallback() {
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isReturned) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final row = await supabase
            .from('borrowing_applications_version2')
            .select('penalty_status')
            .eq('id', widget.application['id'])
            .maybeSingle();
        if (row != null &&
            (row['penalty_status'] == 'returned_terminated' ||
                row['penalty_status'] == 'returned_overdue') &&
            mounted) {
          _onReturnDetected();
        }
      } catch (e) {
        debugPrint('Poll error: $e');
      }
    });
  }

  void _onReturnDetected() {
    if (_isReturned) return;
    setState(() => _isReturned = true);
    _pollTimer?.cancel();
    _pulseController.stop();
    widget.onCompleted();
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: _showingQr
                  ? _buildQrView()
                  : _buildAssessmentForm(),
            ),
            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _showingQr
                ? Icons.qr_code_2_rounded
                : Icons.assignment_return_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _showingQr ? 'Waiting for Borrower' : 'Return Assessment',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A)),
              ),
              Text(
                _showingQr
                    ? 'Ask borrower to scan QR with the PedalHub app'
                    : _fullName,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD32F2F)),
          ),
          child: const Text(
            'TERMINATION RETURN',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Color(0xFFD32F2F)),
          ),
        ),
        if (!_showingQr) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ASSESSMENT FORM
  // ─────────────────────────────────────────────
  Widget _buildAssessmentForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFD32F2F).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                _summaryRow(Icons.person_rounded, 'Borrower', _fullName),
                const SizedBox(height: 8),
                _summaryRow(Icons.badge_rounded, 'ID No',
                    widget.application['id_no'] ?? 'N/A'),
                const SizedBox(height: 8),
                _summaryRow(Icons.pedal_bike_rounded, 'Bike',
                    widget.application['assigned_bike_number'] ?? 'N/A'),
                const SizedBox(height: 8),
                _summaryRow(Icons.play_circle_outline_rounded,
                    'Borrow Start', _startTimeLabel),
                const SizedBox(height: 8),
                _summaryRow(
                    Icons.timer_outlined, 'Duration', _durationLabel),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Bike condition
          const Text('Bike Condition Checklist',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Inspect the bike before processing return:',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 12),
          _conditionCheck(
              'Frame & Body',
              'No visible damage or cracks',
              _frameOk,
              (v) => setState(() => _frameOk = v!)),
          _conditionCheck(
              'Wheels & Tires',
              'Properly inflated, no flat tires',
              _wheelsOk,
              (v) => setState(() => _wheelsOk = v!)),
          _conditionCheck(
              'Brakes',
              'Front and rear brakes functioning',
              _brakesOk,
              (v) => setState(() => _brakesOk = v!)),
          _conditionCheck(
              'Chain & Gears',
              'Chain lubricated, gears shifting properly',
              _chaingearOk,
              (v) => setState(() => _chaingearOk = v!)),
          _conditionCheck(
              'Saddle & Handlebars',
              'Properly adjusted and secured',
              _saddleOk,
              (v) => setState(() => _saddleOk = v!)),
          _conditionCheck(
              'Lights & Reflectors',
              'Front light and reflectors present',
              _lightsOk,
              (v) => setState(() => _lightsOk = v!)),

          if (!_allConditionsOk) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          const Color(0xFFD32F2F).withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD32F2F), size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'One or more components are in poor condition. Consider reporting damage.',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFD32F2F)))),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          // Assessment remarks
          const Text('Assessment Remarks (optional)',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          TextField(
            controller: _remarksController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add notes about the condition or situation...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFFD32F2F), width: 2)),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _conditionCheck(String label, String description,
      bool value, void Function(bool?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value
                ? const Color(0xFF388E3C).withOpacity(0.3)
                : const Color(0xFFD32F2F).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF388E3C),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: value
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFD32F2F))),
                Text(description,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Icon(
            value
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: value
                ? const Color(0xFF388E3C)
                : const Color(0xFFD32F2F),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFD32F2F)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A))),
        Expanded(
          child: Text(value,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[700])),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // QR VIEW
  // ─────────────────────────────────────────────
  Widget _buildQrView() {
    const accentColor = Color(0xFFD32F2F);
    return SingleChildScrollView(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _isReturned
                ? _statusBanner(
                    key: const ValueKey('returned'),
                    color: const Color(0xFF00695C),
                    bgColor: const Color(0xFFE0F2F1),
                    icon: Icons.assignment_turned_in_rounded,
                    message:
                        'Bike returned successfully! Case moved to Needs Action.',
                  )
                : _statusBanner(
                    key: const ValueKey('waiting'),
                    color: accentColor,
                    bgColor: const Color(0xFFFFEBEE),
                    icon: null,
                    message:
                        'Waiting for borrower to complete return on the PedalHub app…',
                  ),
          ),

          const SizedBox(height: 24),

          Text(
            _isReturned
                ? '✅  Bike returned successfully!'
                : 'Ask the borrower to scan this QR with the PedalHub app',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _isReturned
                    ? const Color(0xFF00695C)
                    : Colors.grey[700]),
          ),

          const SizedBox(height: 20),

          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: (_isReturned
                              ? const Color(0xFF00695C)
                              : accentColor)
                          .withOpacity(_isReturned
                              ? 1.0
                              : _pulseAnimation.value),
                      width: _isReturned ? 3 : 2),
                  boxShadow: [
                    BoxShadow(
                      color: (_isReturned
                              ? const Color(0xFF00695C)
                              : accentColor)
                          .withOpacity(0.2 *
                              (_isReturned
                                  ? 1
                                  : _pulseAnimation.value)),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: accentColor),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A1A1A)),
                    ),
                    if (_isReturned)
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Center(
                          child: Icon(
                              Icons.assignment_turned_in_rounded,
                              color: Color(0xFF00695C),
                              size: 80),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: accentColor.withOpacity(0.3))),
            child: const Text(
              'TERMINATION RETURN QR ACTIVE',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: accentColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner({
    required Key key,
    required Color color,
    required Color bgColor,
    required IconData? icon,
    required String message,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Row(children: [
        icon != null
            ? Icon(icon, color: color, size: 20)
            : SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(color))),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // ACTION BUTTONS
  // ─────────────────────────────────────────────
  Widget _buildActionButtons() {
    if (_showingQr && _isReturned) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }

    if (_showingQr && !_isReturned) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('QR is active — waiting for borrower to scan…',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[500])),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      );
    }

    // Assessment form buttons
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: damage / missing
        Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD32F2F),
                side: const BorderSide(color: Color(0xFFD32F2F)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSubmitting ? null : _reportDamaged,
              icon: const Icon(Icons.build_rounded, size: 16),
              label: const Text('Report Damage',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(color: Colors.black54),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSubmitting ? null : _reportMissing,
              icon: const Icon(Icons.search_off_rounded, size: 16),
              label: const Text('Report Missing',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        // Right: cancel + generate QR
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey[600])),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed:
                  _isSubmitting ? null : _generateReturnQr,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(Icons.qr_code_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Saving…' : 'Generate Return QR',
                style:
                    const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
// ═══════════════════════════════════════════════════════════════════
// INSPECTION DIALOG (for returned_overdue)
// ═══════════════════════════════════════════════════════════════════
class _InspectionDialog extends StatefulWidget {
  final Map<String, dynamic> application;
  final Map<String, dynamic>? session;
  final VoidCallback onDamageReported;
  final VoidCallback onClean;

  const _InspectionDialog({
    required this.application,
    required this.session,
    required this.onDamageReported,
    required this.onClean,
  });

  @override
  State<_InspectionDialog> createState() => _InspectionDialogState();
}

class _InspectionDialogState extends State<_InspectionDialog> {
  final supabase = Supabase.instance.client;

  bool _frameOk = true;
  bool _wheelsOk = true;
  bool _brakesOk = true;
  bool _chaingearOk = true;
  bool _saddleOk = true;
  bool _lightsOk = true;
  bool _isSubmitting = false;

  final TextEditingController _remarksController =
      TextEditingController();

  bool get _allConditionsOk =>
      _frameOk &&
      _wheelsOk &&
      _brakesOk &&
      _chaingearOk &&
      _saddleOk &&
      _lightsOk;

  String get _fullName =>
      '${widget.application['first_name'] ?? ''} ${widget.application['last_name'] ?? ''}'
          .trim();

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _reportDamaged() async {
    setState(() => _isSubmitting = true);
    try {
      final bikeId = widget.application['assigned_bike_id'];

      await supabase
          .from('borrowing_applications_version2')
          .update({'penalty_status': 'damaged_bike'})
          .eq('id', widget.application['id']);

      if (widget.session != null) {
        await supabase
            .from('borrowing_sessions')
            .update({'status': 'damaged_bike'})
            .eq('id', widget.session!['id']);
      }

      if (bikeId != null) {
        await supabase
            .from('bikes')
            .update({'status': 'damaged'})
            .eq('id', bikeId);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDamageReported();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Bike marked as damaged. Please forward the case.'),
            backgroundColor: Color(0xFFD32F2F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _markClean() async {
    // returned_overdue with no damage — stays as returned_overdue
    // no further action needed
    Navigator.pop(context);
    widget.onClean();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bike inspected — no damage found.'),
        backgroundColor: Color(0xFF00695C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search_rounded,
                      color: Color(0xFFE65100), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bike Inspection',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                      Text(_fullName,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFE65100)),
                  ),
                  child: const Text(
                    'RETURNED OVERDUE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFFE65100)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFE65100)
                                .withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Color(0xFFE65100), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bike: ${widget.application['assigned_bike_number'] ?? 'N/A'}  •  ID No: ${widget.application['id_no'] ?? 'N/A'}',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 20),

                    const Text('Bike Condition Checklist',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text('Inspect returned bike:',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600])),
                    const SizedBox(height: 12),

                    _conditionCheck('Frame & Body',
                        'No visible damage or cracks', _frameOk,
                        (v) => setState(() => _frameOk = v!)),
                    _conditionCheck(
                        'Wheels & Tires',
                        'Properly inflated, no flat tires',
                        _wheelsOk,
                        (v) => setState(() => _wheelsOk = v!)),
                    _conditionCheck(
                        'Brakes',
                        'Front and rear brakes functioning',
                        _brakesOk,
                        (v) => setState(() => _brakesOk = v!)),
                    _conditionCheck(
                        'Chain & Gears',
                        'Chain lubricated, gears shifting properly',
                        _chaingearOk,
                        (v) => setState(
                            () => _chaingearOk = v!)),
                    _conditionCheck(
                        'Saddle & Handlebars',
                        'Properly adjusted and secured',
                        _saddleOk,
                        (v) => setState(() => _saddleOk = v!)),
                    _conditionCheck(
                        'Lights & Reflectors',
                        'Front light and reflectors present',
                        _lightsOk,
                        (v) => setState(() => _lightsOk = v!)),

                    if (!_allConditionsOk) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFD32F2F)
                                    .withOpacity(0.3))),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFD32F2F),
                              size: 18),
                          SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  'Damage detected. Please use "Report Damage" below.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          Color(0xFFD32F2F)))),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Text('Remarks (optional)',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarksController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Add inspection notes...',
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD32F2F),
                    side:
                        const BorderSide(color: Color(0xFFD32F2F)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed:
                      _isSubmitting ? null : _reportDamaged,
                  icon: const Icon(Icons.build_rounded, size: 16),
                  label: const Text('Report Damage',
                      style:
                          TextStyle(fontWeight: FontWeight.w600)),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: Colors.grey[600])),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF00695C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8)),
                      ),
                      onPressed:
                          _isSubmitting ? null : _markClean,
                      icon: const Icon(
                          Icons.check_circle_rounded,
                          size: 18),
                      label: const Text('No Damage',
                          style: TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _conditionCheck(String label, String description,
      bool value, void Function(bool?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value
                ? const Color(0xFF388E3C).withOpacity(0.3)
                : const Color(0xFFD32F2F).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF388E3C),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: value
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFD32F2F))),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600])),
              ],
            ),
          ),
          Icon(
            value
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: value
                ? const Color(0xFF388E3C)
                : const Color(0xFFD32F2F),
            size: 20,
          ),
        ],
      ),
    );
  }
}