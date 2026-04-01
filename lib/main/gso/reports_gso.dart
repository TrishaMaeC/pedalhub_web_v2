// lib/main/gso/bike_reports_maintenance_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:intl/intl.dart';

class BikeReportsMaintenancePage extends StatefulWidget {
  const BikeReportsMaintenancePage({super.key});

  @override
  State<BikeReportsMaintenancePage> createState() =>
      _BikeReportsMaintenancePageState();
}

class _BikeReportsMaintenancePageState
    extends State<BikeReportsMaintenancePage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;

  bool isLoading = true;
  String? userCampus;

  // ── Reports
  String selectedReportStatus = 'submitted';
  List<Map<String, dynamic>> reports = [];
  int submittedCount = 0;
  int inProgressCount = 0;
  int resolvedCount = 0;

  // ── Maintenance
  String selectedMaintenanceStatus = 'all';
  List<Map<String, dynamic>> maintenanceBikes = [];
  int allBikesCount = 0;
  int forMaintenanceCount = 0;
  int maintenanceCount = 0;
  int availableCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) _fetchMaintenanceBikes();
    });
    _loadUserCampusAndAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        _loadMetrics(),
        _fetchReports(),
        _fetchMaintenanceBikes(),
      ]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadMetrics() async {
    try {
      // Join bikes to filter reports by campus
      final allReports = await supabase
          .from('bike_reports')
          .select('id, status, bike_id, bikes(campus)')
          .not('bike_id', 'is', null);

      final campusReports = (allReports as List).where((r) {
        final bike = r['bikes'];
        if (bike == null) return false;
        final campus = (bike['campus'] ?? '').toString().toLowerCase();
        return campus == userCampus!.toLowerCase();
      }).toList();

      final submitted = campusReports.where((r) => r['status'] == 'submitted').length;
      final inProgressReports = campusReports.where((r) => r['status'] == 'in_progress').length;
      final resolvedReports = campusReports.where((r) => r['status'] == 'resolved').length;
      final forMaintenance = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'for_maintenance')
          .ilike('campus', userCampus!);
      final maintenance = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'maintenance')
          .ilike('campus', userCampus!);
      final available = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'available')
          .ilike('campus', userCampus!);

      setState(() {
        submittedCount = submitted;
        inProgressCount = inProgressReports;
        resolvedCount = resolvedReports;
        forMaintenanceCount = (forMaintenance as List).length;
        maintenanceCount = (maintenance as List).length;
        availableCount = (available as List).length;
        allBikesCount = forMaintenanceCount + maintenanceCount + availableCount;
      });
    } catch (e) {
      debugPrint('Metrics error: $e');
    }
  }

  Future<void> _fetchReports() async {
  if (userCampus == null) return;
  try {
    // Step 1: Kunin muna lahat ng reports, NO join
    final response = await supabase
        .from('bike_reports')
        .select('*')  // ← tanggalin muna ang bikes join
        .eq('status', selectedReportStatus)
        .order('created_at', ascending: false);

    debugPrint('REPORTS WITHOUT JOIN: ${(response as List).length} results');
    debugPrint('FIRST REPORT: ${response.isNotEmpty ? response.first : "none"}');

    // Step 2: Separate query para sa bike campus
    final List<Map<String, dynamic>> result = [];
    for (final r in response) {
      if (r['bike_id'] == null) continue;
      
      final bikeRes = await supabase
          .from('bikes')
          .select('campus')
          .eq('id', r['bike_id'])
          .maybeSingle(); // ← maybeSingle para hindi mag-throw kung null
      
      debugPrint('Bike ${r['bike_id']} campus: $bikeRes');
      
      if (bikeRes == null) continue;
      final campus = (bikeRes['campus'] ?? '').toString().toLowerCase();
      if (campus == userCampus!.toLowerCase()) {
        result.add(Map<String, dynamic>.from(r));
      }
    }

    debugPrint('FILTERED RESULTS: ${result.length}');
    setState(() => reports = result);
  } catch (e) {
    debugPrint('Fetch reports error: $e');
  }
}
  Future<void> _fetchMaintenanceBikes() async {
    if (userCampus == null) return;
    try {
      dynamic query = supabase
          .from('bikes')
          .select('*')
          .ilike('campus', userCampus!)
          .order('updated_at', ascending: false);

      if (selectedMaintenanceStatus != 'all') {
        query = supabase
            .from('bikes')
            .select('*')
            .eq('status', selectedMaintenanceStatus)
            .ilike('campus', userCampus!)
            .order('updated_at', ascending: false);
      }

      final response = await query;
      setState(() =>
          maintenanceBikes = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Fetch maintenance bikes error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // REPORT ACTIONS
  // ─────────────────────────────────────────────
  Future<void> _acknowledgeReport(Map<String, dynamic> report) async {
    try {
      await supabase.from('bike_reports').update({
        'status': 'under_review',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Report acknowledged — now under review.'),
              backgroundColor: Color(0xFF1565C0)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _markInProgress(Map<String, dynamic> report) async {
    final confirmed = await _showConfirmDialog(
      title: 'Set For Maintenance',
      message:
          'Bike #${report['bike_number']} will be marked as "for_maintenance" and this report set to in progress.',
      confirmLabel: 'Confirm',
      confirmColor: const Color(0xFFF57C00),
    );
    if (!confirmed) return;
    try {
      await supabase.from('bike_reports').update({
        'status': 'in_progress',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      if (report['bike_id'] != null) {
        await supabase.from('bikes').update({
          'status': 'for_maintenance',
          'maintenance_started_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', report['bike_id']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bike set for maintenance.'),
              backgroundColor: Color(0xFFF57C00)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final notesController = TextEditingController();
    final notes = await _showRemarksDialog(notesController,
        title: 'Resolution Notes (optional)');
    if (notes == null) return;
    try {
      await supabase.from('bike_reports').update({
        'status': 'resolved',
        'admin_notes': notes.trim().isEmpty ? null : notes.trim(),
        'resolved_by': supabase.auth.currentUser?.id,
        'resolved_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Report resolved.'),
              backgroundColor: Color(0xFF388E3C)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────
  // MAINTENANCE ACTIONS
  // ─────────────────────────────────────────────
  Future<void> _assignWorker(Map<String, dynamic> bike) async {
    final workerController =
        TextEditingController(text: bike['maintenance_worker'] ?? '');
    final notesController =
        TextEditingController(text: bike['maintenance_notes'] ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFFF57C00).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.engineering_rounded,
                color: Color(0xFFF57C00), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Assign Worker — Bike #${bike['bike_number']}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Worker Name *',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: workerController,
              decoration: InputDecoration(
                hintText: 'Enter worker name',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Maintenance Notes (optional)',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe the issue or work needed...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF57C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, {
              'worker': workerController.text.trim(),
              'notes': notesController.text.trim(),
            }),
            child: const Text('Assign'),
          ),
        ],
      ),
    );

    if (result == null || result['worker']!.isEmpty) return;
    try {
      await supabase.from('bikes').update({
        'status': 'maintenance',
        'maintenance_worker': result['worker'],
        'maintenance_notes':
            result['notes']!.isEmpty ? null : result['notes'],
        'maintenance_started_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Worker "${result['worker']}" assigned to Bike #${bike['bike_number']}.'),
              backgroundColor: const Color(0xFFF57C00)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _setForMaintenance(Map<String, dynamic> bike) async {
    final confirmed = await _showConfirmDialog(
      title: 'Set For Maintenance',
      message:
          'Bike #${bike['bike_number']} will be marked as "for_maintenance". You can assign a worker after.',
      confirmLabel: 'Confirm',
      confirmColor: const Color(0xFFD32F2F),
    );
    if (!confirmed) return;
    try {
      await supabase.from('bikes').update({
        'status': 'for_maintenance',
        'maintenance_started_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Bike #${bike['bike_number']} set for maintenance.'),
              backgroundColor: const Color(0xFFD32F2F)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _markBikeDone(Map<String, dynamic> bike) async {
    final confirmed = await _showConfirmDialog(
      title: 'Mark as Done',
      message:
          'Bike #${bike['bike_number']} will be set back to available.',
      confirmLabel: 'Mark Done',
      confirmColor: const Color(0xFF388E3C),
    );
    if (!confirmed) return;
    try {
      await supabase.from('bikes').update({
        'status': 'available',
        'maintenance_worker': null,
        'maintenance_notes': null,
        'last_maintenance_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Bike #${bike['bike_number']} is now available.'),
              backgroundColor: const Color(0xFF388E3C)),
        );
        await _loadAll();
      }
    } catch (e) {
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  void _showError(dynamic e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

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
            hintText: 'Enter notes...',
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

  Color _reportStatusColor(String status) {
    switch (status) {
      case 'submitted':
        return const Color(0xFFD32F2F);
      case 'under_review':
        return const Color(0xFF1565C0);
      case 'in_progress':
        return const Color(0xFFF57C00);
      case 'resolved':
        return const Color(0xFF388E3C);
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _reportStatusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'New';
      case 'under_review':
        return 'Under Review';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return const Color(0xFFD32F2F);
      case 'high':
        return const Color(0xFFE65100);
      case 'medium':
        return const Color(0xFFF57C00);
      case 'low':
        return const Color(0xFF388E3C);
      default:
        return Colors.grey;
    }
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
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFD32F2F),
              unselectedLabelColor: Colors.grey[500],
              indicatorColor: const Color(0xFFD32F2F),
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700),
              tabs: [
                Tab(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.report_rounded),
                      if (submittedCount > 0)
                        Positioned(
                          right: -8,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Color(0xFFD32F2F),
                                shape: BoxShape.circle),
                            child: Text(submittedCount.toString(),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  text: 'Bike Reports',
                ),
                Tab(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.build_rounded),
                      if (forMaintenanceCount > 0)
                        Positioned(
                          right: -8,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                                color: Color(0xFFF57C00),
                                shape: BoxShape.circle),
                            child: Text(forMaintenanceCount.toString(),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  text: 'Maintenance',
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
                    controller: _tabController,
                    children: [
                      _buildReportsTab(),
                      _buildMaintenanceTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  // REPORTS TAB
  // ══════════════════════════════════════════════
  Widget _buildReportsTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'Bike Reports',
              Icons.report_rounded,
              const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)]),
              'User-submitted bike issue reports',
              onRefresh: _loadAll,
            ),
            const SizedBox(height: 24),
            Row(children: [
              _metricCard(
                  label: 'New Reports',
                  count: submittedCount,
                  icon: Icons.fiber_new_rounded,
                  color: const Color(0xFFD32F2F)),
              const SizedBox(width: 16),
              _metricCard(
                  label: 'In Progress',
                  count: inProgressCount,
                  icon: Icons.pending_rounded,
                  color: const Color(0xFFF57C00)),
              const SizedBox(width: 16),
              _metricCard(
                  label: 'Resolved',
                  count: resolvedCount,
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF388E3C)),
            ]),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('submitted', 'New',
                      Icons.fiber_new_rounded, const Color(0xFFD32F2F),
                      true),
                  const SizedBox(width: 10),
                  _filterChip('under_review', 'Under Review',
                      Icons.search_rounded, const Color(0xFF1565C0),
                      true),
                  const SizedBox(width: 10),
                  _filterChip('in_progress', 'In Progress',
                      Icons.pending_rounded, const Color(0xFFF57C00),
                      true),
                  const SizedBox(width: 10),
                  _filterChip('resolved', 'Resolved',
                      Icons.check_circle_rounded,
                      const Color(0xFF388E3C), true),
                  const SizedBox(width: 10),
                  _filterChip('rejected', 'Rejected',
                      Icons.cancel_rounded, Colors.grey, true),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (reports.isEmpty)
              _emptyState('No reports found',
                  Icons.inbox_outlined, Colors.grey)
            else
              ...reports.map((r) => _reportCard(r)),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final status = report['status'] ?? 'submitted';
    final issueType = (report['issue_type'] ?? 'other')
        .toString()
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    final priority = report['priority'] ?? 'medium';
    final photoUrl = report['photo_url'] as String?;

    String createdAtLabel = 'N/A';
    try {
      final dt =
          DateTime.parse(report['created_at'].toString()).toLocal();
      createdAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {}

    final Color statusColor = _reportStatusColor(status);
    final String statusLabel = _reportStatusLabel(status);
    final Color priorityColor = _priorityColor(priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo (if exists) ──
          if (photoUrl != null && photoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: GestureDetector(
                onTap: () => _showPhotoDialog(photoUrl),
                child: Stack(
                  children: [
                    Image.network(
                      photoUrl,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 80,
                        color: Colors.grey[100],
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded,
                              color: Colors.grey, size: 32),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Tap to expand',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.report_rounded,
                          color: statusColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(
                                report['reporter_name'] ?? 'Unknown',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _chip(statusLabel, statusColor),
                            const SizedBox(width: 6),
                            _chip(priority.toUpperCase(),
                                priorityColor),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                              'Bike #${report['bike_number'] ?? 'N/A'}  •  $issueType',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600])),
                          Text('Reported: $createdAtLabel',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Description ──
                if (report['description'] != null &&
                    report['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!)),
                    child: Text(report['description'],
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[700])),
                  ),
                ],

                // ── Admin notes ──
                if (report['admin_notes'] != null &&
                    report['admin_notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.notes_rounded,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Admin Notes: ${report['admin_notes']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic)),
                    ),
                  ]),
                ],

                const SizedBox(height: 14),

                // ── Action buttons ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'submitted')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _acknowledgeReport(report),
                        icon: const Icon(Icons.visibility_rounded,
                            size: 16),
                        label: const Text('Acknowledge',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    if (status == 'under_review') ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF57C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _markInProgress(report),
                        icon: const Icon(Icons.build_rounded,
                            size: 16),
                        label: const Text('Set For Maintenance',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF388E3C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _resolveReport(report),
                        icon: const Icon(Icons.check_circle_rounded,
                            size: 16),
                        label: const Text('Resolve',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ],
                    if (status == 'in_progress')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF388E3C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _resolveReport(report),
                        icon: const Icon(Icons.check_circle_rounded,
                            size: 16),
                        label: const Text('Mark Resolved',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoDialog(String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(32),
                  color: Colors.white,
                  child: const Icon(Icons.broken_image_rounded,
                      size: 64, color: Colors.grey),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // MAINTENANCE TAB
  // ══════════════════════════════════════════════
  Widget _buildMaintenanceTab() {
    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: _fetchMaintenanceBikes,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'Maintenance',
              Icons.build_rounded,
              const LinearGradient(
                  colors: [Color(0xFFF57C00), Color(0xFFFFB74D)]),
              'Manage bikes under maintenance',
              onRefresh: _fetchMaintenanceBikes,
            ),
            const SizedBox(height: 24),
            Row(children: [
              _metricCard(
                  label: 'All Bikes',
                  count: allBikesCount,
                  icon: Icons.pedal_bike_rounded,
                  color: const Color(0xFF1565C0)),
              const SizedBox(width: 16),
              _metricCard(
                  label: 'For Maintenance',
                  count: forMaintenanceCount,
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFD32F2F)),
              const SizedBox(width: 16),
              _metricCard(
                  label: 'Being Fixed',
                  count: maintenanceCount,
                  icon: Icons.engineering_rounded,
                  color: const Color(0xFFF57C00)),
              const SizedBox(width: 16),
              _metricCard(
                  label: 'Available',
                  count: availableCount,
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF388E3C)),
            ]),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                      'all',
                      'All Bikes',
                      Icons.pedal_bike_rounded,
                      const Color(0xFF1565C0),
                      false),
                  const SizedBox(width: 10),
                  _filterChip(
                      'for_maintenance',
                      'For Maintenance',
                      Icons.warning_amber_rounded,
                      const Color(0xFFD32F2F),
                      false),
                  const SizedBox(width: 10),
                  _filterChip(
                      'maintenance',
                      'Being Fixed',
                      Icons.engineering_rounded,
                      const Color(0xFFF57C00),
                      false),
                  const SizedBox(width: 10),
                  _filterChip('available', 'Available',
                      Icons.check_circle_rounded,
                      const Color(0xFF388E3C), false),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (maintenanceBikes.isEmpty)
              _emptyState('No bikes found',
                  Icons.pedal_bike_outlined, Colors.grey)
            else
              ...maintenanceBikes.map((b) => _bikeCard(b)),
          ],
        ),
      ),
    );
  }

  Widget _bikeCard(Map<String, dynamic> bike) {
    final status = bike['status'] ?? 'for_maintenance';
    final isForMaintenance = status == 'for_maintenance';
    final isBeingFixed = status == 'maintenance';
    final isAvailable = status == 'available';

    final Color color = isForMaintenance
        ? const Color(0xFFD32F2F)
        : isBeingFixed
            ? const Color(0xFFF57C00)
            : const Color(0xFF388E3C);

    final String statusLabel = isForMaintenance
        ? 'For Maintenance'
        : isBeingFixed
            ? 'Being Fixed'
            : 'Available';

    String lastMaintenanceLabel = 'Never';
    if (bike['last_maintenance_date'] != null) {
      try {
        final dt = DateTime.parse(
                bike['last_maintenance_date'].toString())
            .toLocal();
        lastMaintenanceLabel =
            DateFormat('MMM dd, yyyy').format(dt);
      } catch (_) {}
    }

    String startedAtLabel = 'N/A';
    if (bike['maintenance_started_at'] != null) {
      try {
        final dt = DateTime.parse(
                bike['maintenance_started_at'].toString())
            .toLocal();
        startedAtLabel = DateFormat('MMM dd, yyyy HH:mm').format(dt);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isBeingFixed
                      ? Icons.engineering_rounded
                      : Icons.pedal_bike_rounded,
                  color: color,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                        'Bike #${bike['bike_number']}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                      ),
                      const SizedBox(width: 8),
                      _chip(statusLabel, color),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        'Campus: ${(bike['campus'] ?? 'N/A').toString().toUpperCase()}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                    Text(
                        'Last Maintenance: $lastMaintenanceLabel  •  Rides: ${bike['total_rides'] ?? 0}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),

          // ── Maintenance details ──
          if (isBeingFixed || isForMaintenance) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: color.withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBeingFixed &&
                      bike['maintenance_worker'] != null) ...[
                    Row(children: [
                      Icon(Icons.engineering_rounded,
                          size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(
                          'Worker: ${bike['maintenance_worker']}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ]),
                    const SizedBox(height: 4),
                  ],
                  if (bike['maintenance_notes'] != null &&
                      bike['maintenance_notes']
                          .toString()
                          .isNotEmpty) ...[
                    Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes_rounded,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                bike['maintenance_notes'],
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600])),
                          ),
                        ]),
                    const SizedBox(height: 4),
                  ],
                  Row(children: [
                    Icon(Icons.schedule_rounded,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text('Started: $startedAtLabel',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ]),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Action buttons ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isForMaintenance)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _assignWorker(bike),
                  icon: const Icon(Icons.engineering_rounded,
                      size: 18),
                  label: const Text('Assign Worker',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              if (isAvailable)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _setForMaintenance(bike),
                  icon: const Icon(Icons.build_rounded, size: 18),
                  label: const Text('Set For Maintenance',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              if (isBeingFixed) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF57C00),
                    side: const BorderSide(
                        color: Color(0xFFF57C00)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _assignWorker(bike),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit Worker',
                      style: TextStyle(fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF388E3C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _markBikeDone(bike),
                  icon: const Icon(Icons.check_circle_rounded,
                      size: 18),
                  label: const Text('Mark Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────
  Widget _buildSectionTitle(
    String title,
    IconData icon,
    Gradient gradient,
    String subtitle, {
    required VoidCallback onRefresh,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  $subtitle'
                      : subtitle,
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onRefresh,
          color: Colors.grey[600],
        ),
      ],
    );
  }

  Widget _metricCard({
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
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
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
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label, IconData icon,
      Color color, bool isReport) {
    final isSelected = isReport
        ? selectedReportStatus == value
        : selectedMaintenanceStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isReport) {
            selectedReportStatus = value;
          } else {
            selectedMaintenanceStatus = value;
          }
        });
        if (isReport) {
          _fetchReports();
        } else {
          _fetchMaintenanceBikes();
        }
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
              width: 1.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: isSelected ? Colors.white : color),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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