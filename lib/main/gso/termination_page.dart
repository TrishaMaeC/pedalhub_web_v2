// lib/main/gso/termination_page.dart

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
  String selectedTab = 'pending'; // pending | returned_terminated | forwarded

  String? userCampus;

  List<Map<String, dynamic>> pendingList = [];
  List<Map<String, dynamic>> returnedList = [];
  List<Map<String, dynamic>> forwardedList = [];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initPage();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _fetchAll();
    });
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
      setState(
          () => userCampus = (profile['campus'] as String).toLowerCase());
    } catch (e) {
      debugPrint('Campus load error: $e');
    }
  }

  Future<void> _fetchAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchByStatus('pending'),
        _fetchByStatus('returned_terminated'),
        _fetchByStatus('forwarded'),
      ]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  // FETCH LIABILITIES BY STATUS
  // ─────────────────────────────────────────────
  Future<void> _fetchByStatus(String status) async {
    try {
      final response = await supabase
          .from('liabilities')
          .select('*')
          .eq('status', status)
          .ilike('campus', userCampus!)
          .order('tagged_at', ascending: false);

      final liabilities = List<Map<String, dynamic>>.from(response);

      // Enrich each liability with session info
      final enriched = await Future.wait(liabilities.map((lib) async {
        try {
          Map<String, dynamic>? session;

          if (lib['application_id'] != null) {
            session = await supabase
                .from('borrowing_sessions')
                .select('id, bike_id, start_time, end_time, status')
                .eq('application_id', lib['application_id'])
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
          } else if (lib['renewal_application_id'] != null) {
            // Get session_id from renewal_applications
            final renewal = await supabase
                .from('renewal_applications')
                .select('session_id')
                .eq('id', lib['renewal_application_id'])
                .maybeSingle();

            if (renewal != null && renewal['session_id'] != null) {
              session = await supabase
                  .from('borrowing_sessions')
                  .select('id, bike_id, start_time, end_time, status')
                  .eq('id', renewal['session_id'])
                  .maybeSingle();
            }
          }

          return {...lib, 'borrowing_sessions': session};
        } catch (_) {
          return {...lib, 'borrowing_sessions': null};
        }
      }));

      if (mounted) {
        setState(() {
          if (status == 'pending') pendingList = enriched;
          if (status == 'returned_terminated') returnedList = enriched;
          if (status == 'forwarded') forwardedList = enriched;
        });
      }
    } catch (e) {
      debugPrint('Fetch liabilities ($status) error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // SHOW RETURN DIALOG (mirrors for_return page)
  // ─────────────────────────────────────────────
  void _showReturnDialog(Map<String, dynamic> liability) {
    final session = liability['borrowing_sessions'];
    final sessionId = session != null ? session['id']?.toString() : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TerminationReturnDialog(
        liabilityId: liability['id'].toString(),
        applicationId: liability['application_id']?.toString(),
        renewalApplicationId: liability['renewal_application_id']?.toString(),
        sessionId: sessionId,
        applicantName: liability['borrower_name'] ?? 'Unknown',
        bikeNumber: liability['bike_number'] ?? 'N/A',
        startTime: session?['start_time'],
        isRenewal: liability['renewal_application_id'] != null,
        onReturned: () async {
          await _fetchAll();
          setState(() => selectedTab = 'returned_terminated');
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // FORWARD TO DISCIPLINE
  // ─────────────────────────────────────────────
  Future<void> _forwardToDiscipline(Map<String, dynamic> liability) async {
    final confirmed = await _showConfirmDialog(
      title: 'Forward to Student Discipline',
      message:
          'This will forward ${liability['borrower_name']}\'s case to the Student Discipline Office.',
      confirmLabel: 'Forward',
      confirmColor: const Color(0xFF7B1FA2),
    );
    if (!confirmed) return;

    final notes = await _showRemarksDialog(
      TextEditingController(),
      title: 'Notes for Discipline Office (optional)',
    );
    if (notes == null) return;

    try {
      await supabase.from('student_discipline').insert({
        'liability_id': liability['id'],
        'application_id': liability['application_id'],
        'renewal_application_id': liability['renewal_application_id'],
        'borrower_name': liability['borrower_name'],
        'sr_code': liability['sr_code'],
        'campus': liability['campus'],
        'bike_number': liability['bike_number'],
        'due_date': liability['due_date'],
        'days_overdue': liability['days_overdue'],
        'penalty_recommendation': liability['penalty_recommendation'],
        'forwarded_by': supabase.auth.currentUser?.id,
        'forwarded_at': DateTime.now().toIso8601String(),
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'status': 'open',
      });

      await supabase
          .from('liabilities')
          .update({'status': 'forwarded'})
          .eq('id', liability['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Case forwarded to Student Discipline.'),
            backgroundColor: Color(0xFF7B1FA2),
          ),
        );
        setState(() => selectedTab = 'forwarded');
        await _fetchAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
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
                style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Future<String?> _showRemarksDialog(
    TextEditingController controller, {
    String title = 'Add Remarks (optional)',
  }) async {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter remarks...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
          ),
        ],
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
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Manage liability returns & discipline forwarding'
                      : 'Manage liability returns & discipline forwarding',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey[600]),
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
    return Row(
      children: [
        _summaryCard(
          label: 'Pending Return',
          count: pendingList.length,
          icon: Icons.hourglass_bottom_rounded,
          color: const Color(0xFFD32F2F),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Bike Returned',
          count: returnedList.length,
          icon: Icons.assignment_turned_in_rounded,
          color: const Color(0xFF00695C),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Forwarded to Discipline',
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _tabBtn('pending', 'Pending Return',
                Icons.hourglass_bottom_rounded,
                const Color(0xFFD32F2F), pendingList.length),
            _tabBtn('returned_terminated', 'Bike Returned',
                Icons.assignment_turned_in_rounded,
                const Color(0xFF00695C), returnedList.length),
            _tabBtn('forwarded', 'Forwarded to Discipline',
                Icons.send_rounded,
                const Color(0xFF7B1FA2), forwardedList.length),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(
      String value, String label, IconData icon, Color color, int count) {
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
      case 'pending':
        return pendingList.isEmpty
            ? _emptyState('No pending liability returns',
                Icons.check_circle_outline_rounded, Colors.green)
            : Column(
                children: pendingList
                    .map((lib) => _liabilityCard(lib, tab: 'pending'))
                    .toList());
      case 'returned_terminated':
        return returnedList.isEmpty
            ? _emptyState('No returned bikes yet',
                Icons.hourglass_empty_rounded, Colors.orange)
            : Column(
                children: returnedList
                    .map((lib) => _liabilityCard(lib, tab: 'returned_terminated'))
                    .toList());
      case 'forwarded':
        return forwardedList.isEmpty
            ? _emptyState('No cases forwarded yet',
                Icons.send_outlined, Colors.purple)
            : Column(
                children: forwardedList
                    .map((lib) => _liabilityCard(lib, tab: 'forwarded'))
                    .toList());
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────
  // LIABILITY CARD
  // ─────────────────────────────────────────────
  Widget _liabilityCard(Map<String, dynamic> lib,
      {required String tab}) {
    final isPending = tab == 'pending';
    final isReturned = tab == 'returned_terminated';
    final isForwarded = tab == 'forwarded';
    final isRenewal = lib['renewal_application_id'] != null;

    final Color color = isPending
        ? const Color(0xFFD32F2F)
        : isReturned
            ? const Color(0xFF00695C)
            : const Color(0xFF7B1FA2);

    final String statusLabel = isPending
        ? 'Pending Return'
        : isReturned
            ? 'Bike Returned'
            : 'Forwarded to Discipline';

    String taggedAtLabel = 'N/A';
    try {
      final dt =
          DateTime.parse(lib['tagged_at'].toString()).toLocal();
      taggedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {}

    final session = lib['borrowing_sessions'];
    final startTime = session?['start_time'];
    String startTimeLabel = 'N/A';
    if (startTime != null) {
      try {
        final dt = DateTime.parse(startTime.toString()).toLocal();
        startTimeLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
      } catch (_) {}
    }

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
            child: Icon(
              isPending
                  ? Icons.hourglass_bottom_rounded
                  : isReturned
                      ? Icons.assignment_turned_in_rounded
                      : Icons.send_rounded,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(lib['borrower_name'] ?? 'Unknown',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 8),
                  _chip(statusLabel, color),
                  const SizedBox(width: 6),
                  _chip(
                    isRenewal ? 'Renewal' : 'New',
                    isRenewal
                        ? const Color(0xFF7B1FA2)
                        : const Color(0xFF1565C0),
                  ),
                ]),
                const SizedBox(height: 4),
                if (lib['sr_code'] != null)
                  Text('SR Code: ${lib['sr_code']}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.pedal_bike_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Bike: ${lib['bike_number'] ?? 'N/A'}',
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
                  Icon(Icons.access_time_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Tagged: $taggedAtLabel',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                ]),
                if (lib['remarks'] != null &&
                    lib['remarks'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.notes_rounded,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('Remarks: ${lib['remarks']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Action buttons
          if (isPending)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReturnDialog(lib),
              icon: const Icon(Icons.assignment_return_rounded, size: 18),
              label: const Text('Process Return',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (isReturned)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1FA2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _forwardToDiscipline(lib),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Forward to Discipline',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
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

  Widget _emptyState(String message, IconData icon, Color color) {
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
  final String liabilityId;
  final String? applicationId;
  final String? renewalApplicationId;
  final String? sessionId;
  final String applicantName;
  final String bikeNumber;
  final dynamic startTime;
  final bool isRenewal;
  final VoidCallback onReturned;

  const _TerminationReturnDialog({
    required this.liabilityId,
    required this.applicationId,
    required this.renewalApplicationId,
    required this.sessionId,
    required this.applicantName,
    required this.bikeNumber,
    required this.startTime,
    required this.isRenewal,
    required this.onReturned,
  });

  @override
  State<_TerminationReturnDialog> createState() =>
      _TerminationReturnDialogState();
}

class _TerminationReturnDialogState extends State<_TerminationReturnDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _showingQr = false;
  bool _isReturned = false;
  bool _isSubmitting = false;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Bike condition checklist (same as for_release)
  bool _frameOk = true;
  bool _wheelsOk = true;
  bool _brakesOk = true;
  bool _chaingearOk = true;
  bool _saddleOk = true;
  bool _lightsOk = true;

  // ── Penalty recommendation
  String? _penaltyRecommendation; // 'permanently_terminated' | 'suspended_1_semester'

  // ── Assessment remarks
  final TextEditingController _remarksController = TextEditingController();

  bool get _canGenerateQr => _penaltyRecommendation != null;

  bool get _allConditionsOk =>
      _frameOk && _wheelsOk && _brakesOk && _chaingearOk && _saddleOk && _lightsOk;

  String get _qrData =>
      'RETURN-${widget.sessionId ?? widget.applicationId}';

  String get _durationLabel {
    if (widget.startTime == null) return 'N/A';
    try {
      final start = DateTime.parse(widget.startTime.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(start);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (hours > 0) return '${hours}h ${minutes}m';
      return '${minutes}m';
    } catch (_) {
      return 'N/A';
    }
  }

  String get _startTimeLabel {
    if (widget.startTime == null) return 'N/A';
    try {
      final dt = DateTime.parse(widget.startTime.toString()).toLocal();
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'N/A';
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _remarksController.dispose();
    if (_channel != null) supabase.removeChannel(_channel!);
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // SAVE ASSESSMENT THEN SHOW QR
  // ─────────────────────────────────────────────
  Future<void> _generateReturnQr() async {
    if (!_canGenerateQr) return;
    setState(() => _isSubmitting = true);

    try {
      // Save bike condition + penalty recommendation to liabilities
      await supabase.from('liabilities').update({
        'bike_condition': {
          'frame': _frameOk,
          'wheels': _wheelsOk,
          'brakes': _brakesOk,
          'chain_gear': _chaingearOk,
          'saddle': _saddleOk,
          'lights': _lightsOk,
        },
        'penalty_recommendation': _penaltyRecommendation,
        'assessment_remarks': _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
        'assessed_at': DateTime.now().toIso8601String(),
        'assessed_by': supabase.auth.currentUser?.id,
      }).eq('id', int.parse(widget.liabilityId));

      setState(() {
        _showingQr = true;
        _isSubmitting = false;
      });

      _startRealtimeListener();
      _startPollingFallback();
    } catch (e) {
      debugPrint('Assessment save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _startRealtimeListener() {
    _channel =
        supabase.channel('termination_liability_${widget.liabilityId}');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'liabilities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.liabilityId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'];
            if (newStatus == 'returned_terminated' && !_isReturned && mounted) {
              _onReturnDetected();
            }
          },
        )
        .subscribe();
  }

  void _startPollingFallback() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isReturned) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final row = await supabase
            .from('liabilities')
            .select('status')
            .eq('id', int.parse(widget.liabilityId))
            .maybeSingle();
        if (row != null && row['status'] == 'returned_terminated' && mounted) {
          _onReturnDetected();
        }
      } catch (e) {
        debugPrint('Poll error: $e');
      }
    });
  }

  // Mobile app handles all DB updates — admin just detects and refreshes
  void _onReturnDetected() {
    if (_isReturned) return;
    setState(() => _isReturned = true);
    _pollTimer?.cancel();
    _pulseController.stop();
    widget.onReturned();
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              child: _showingQr ? _buildQrView() : _buildAssessmentForm(),
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
            gradient: LinearGradient(
                colors: widget.isRenewal
                    ? [const Color(0xFF4A148C), const Color(0xFF9C27B0)]
                    : [const Color(0xFFB71C1C), const Color(0xFFD32F2F)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _showingQr ? Icons.qr_code_2_rounded : Icons.assignment_return_rounded,
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
                    : widget.applicantName,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD32F2F)),
          ),
          child: const Text(
            'LIABILITY RETURN',
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
  // ASSESSMENT FORM (before QR)
  // ─────────────────────────────────────────────
  Widget _buildAssessmentForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Return summary info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                _summaryRow(Icons.person_rounded, 'Borrower', widget.applicantName),
                const SizedBox(height: 8),
                _summaryRow(Icons.pedal_bike_rounded, 'Bike Number', widget.bikeNumber),
                const SizedBox(height: 8),
                _summaryRow(Icons.play_circle_outline_rounded, 'Borrow Start', _startTimeLabel),
                const SizedBox(height: 8),
                _summaryRow(Icons.timer_outlined, 'Duration', _durationLabel),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Bike condition checklist
          const Text('Bike Condition Checklist',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Inspect bike before processing return:',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 12),
          _conditionCheck('Frame & Body', 'No visible damage or cracks',
              _frameOk, (v) => setState(() => _frameOk = v!)),
          _conditionCheck('Wheels & Tires', 'Properly inflated, no flat tires',
              _wheelsOk, (v) => setState(() => _wheelsOk = v!)),
          _conditionCheck('Brakes', 'Front and rear brakes functioning',
              _brakesOk, (v) => setState(() => _brakesOk = v!)),
          _conditionCheck('Chain & Gears', 'Chain lubricated, gears shifting properly',
              _chaingearOk, (v) => setState(() => _chaingearOk = v!)),
          _conditionCheck('Saddle & Handlebars', 'Properly adjusted and secured',
              _saddleOk, (v) => setState(() => _saddleOk = v!)),
          _conditionCheck('Lights & Reflectors', 'Front light and reflectors present',
              _lightsOk, (v) => setState(() => _lightsOk = v!)),

          if (!_allConditionsOk) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text('One or more components are in poor condition.',
                        style: TextStyle(fontSize: 13, color: Color(0xFFD32F2F)))),
              ]),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 20),

          // Penalty recommendation
          const Text('Penalty Recommendation',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Discipline office will make the final decision.',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          const SizedBox(height: 12),

          _penaltyOption(
            value: 'permanently_terminated',
            label: 'Permanently Terminated',
            description: 'Borrower is permanently banned from the program.',
            icon: Icons.block_rounded,
            color: const Color(0xFFD32F2F),
          ),
          const SizedBox(height: 10),
          _penaltyOption(
            value: 'suspended_1_semester',
            label: 'Suspended for 1 Semester',
            description: 'Borrower cannot borrow for the next semester.',
            icon: Icons.pause_circle_rounded,
            color: const Color(0xFFE65100),
          ),

          if (_penaltyRecommendation == null) ...[
            const SizedBox(height: 8),
            Text('* Please select a penalty recommendation to proceed.',
                style: TextStyle(fontSize: 12, color: Colors.red[400])),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 2)),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _penaltyOption({
    required String value,
    required String label,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _penaltyRecommendation == value;
    return GestureDetector(
      onTap: () => setState(() => _penaltyRecommendation = value),
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
              ? [BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : const Color(0xFF1A1A1A))),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey[400],
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _conditionCheck(String label, String description, bool value,
      void Function(bool?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Icon(
            value ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: value ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
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
              style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // QR VIEW (same as before)
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
                    message: 'Bike returned successfully! Liability status updated.',
                  )
                : _statusBanner(
                    key: const ValueKey('waiting'),
                    color: accentColor,
                    bgColor: const Color(0xFFFFEBEE),
                    icon: null,
                    message: 'Waiting for borrower to complete return on the PedalHub app…',
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
                color: _isReturned ? const Color(0xFF00695C) : Colors.grey[700]),
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
                      color: (_isReturned ? const Color(0xFF00695C) : accentColor)
                          .withOpacity(_isReturned ? 1.0 : _pulseAnimation.value),
                      width: _isReturned ? 3 : 2),
                  boxShadow: [
                    BoxShadow(
                      color: (_isReturned ? const Color(0xFF00695C) : accentColor)
                          .withOpacity(0.2 * (_isReturned ? 1 : _pulseAnimation.value)),
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
                          eyeShape: QrEyeShape.square, color: accentColor),
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
                          child: Icon(Icons.assignment_turned_in_rounded,
                              color: Color(0xFF00695C), size: 80),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withOpacity(0.3))),
            child: const Text(
              'LIABILITY RETURN QR ACTIVE',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: accentColor),
            ),
          ),

          if (!_isReturned) ...[
            const SizedBox(height: 20),
            // Penalty summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.gavel_rounded, color: Color(0xFFD32F2F), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Penalty Recommendation',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      Text(
                        _penaltyRecommendation == 'permanently_terminated'
                            ? 'Permanently Terminated'
                            : 'Suspended for 1 Semester',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Borrower',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      Text(widget.applicantName,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bike No.',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      Text(widget.bikeNumber,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                    ],
                  ),
                ),
              ]),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    valueColor: AlwaysStoppedAnimation<Color>(color))),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildActionButtons() {
    if (_showingQr && _isReturned) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _canGenerateQr
                ? const Color(0xFFD32F2F)
                : Colors.grey[300],
            foregroundColor: _canGenerateQr ? Colors.white : Colors.grey[500],
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: _canGenerateQr ? 2 : 0,
          ),
          onPressed: (_isSubmitting || !_canGenerateQr) ? null : _generateReturnQr,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.qr_code_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'Saving…' : 'Generate Return QR',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}