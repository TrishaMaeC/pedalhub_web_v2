// for_return_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:signature/signature.dart';

class ForReturnPage extends StatefulWidget {
  const ForReturnPage({super.key});

  @override
  State<ForReturnPage> createState() => _ForReturnPageState();
}

class _ForReturnPageState extends State<ForReturnPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String selectedTab = 'new';

  String selectedNewStatus = 'active';
  String selectedRenewalStatus = 'renewal_medical_approved';
  String selectedShortTermStatus = 'active';
  String selectedRenewalUserType = 'student'; // 'student' or 'personnel'

  List<Map<String, dynamic>> newActiveBorrows = [];
  List<Map<String, dynamic>> renewalActiveBorrows = [];
  List<Map<String, dynamic>> shortTermBorrows = [];

  String? userCampus;
  bool _isShortTermEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserCampusAndFetch();
    _fetchShortTermSetting();
  }

  Future<void> _fetchShortTermSetting() async {
    try {
      final data = await supabase
          .from('system_settings')
          .select('is_short_term')
          .limit(1)
          .single();
      setState(() => _isShortTermEnabled = data['is_short_term'] ?? false);
    } catch (e) {
      debugPrint('Short term setting error: $e');
    }
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
      _fetchAll();
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

  Future<void> _fetchAll() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchNewBorrows(),
        _fetchRenewalBorrows(),
        if (_isShortTermEnabled) _fetchShortTermBorrows(),
      ]);
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchNewBorrows() async {
    if (userCampus == null) return;
    try {
      final appsResponse = await supabase
          .from('borrowing_applications_version2')
          .select('*')
          .eq('status', selectedNewStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);

      final apps = List<Map<String, dynamic>>.from(appsResponse);
      final enriched = await Future.wait(apps.map((app) async {
        try {
          final sessionRes = await supabase
              .from('borrowing_sessions')
              .select('id, bike_id, start_time, end_time, status')
              .eq('application_id', app['id'])
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          return {...app, 'borrowing_sessions': sessionRes};
        } catch (_) {
          return {...app, 'borrowing_sessions': null};
        }
      }));
      setState(() => newActiveBorrows = enriched);
    } catch (e) {
      debugPrint('Fetch new borrows error: $e');
    }
  }

  Future<void> _fetchRenewalBorrows() async {
    if (userCampus == null) return;
    try {
      // Fetch renewal applications that need bike inspection/return handling
      // Status: renewal_medical_approved (student/personnel need bike inspection)
      // Status: active_renewal (currently borrowed, for return)
      // Status: renewal_bike_damage_reported (self-reported damage, needs verification)
      final appsResponse = await supabase
          .from('borrowing_applications_version2')
          .select('*')
          .inFilter('status', [
            selectedRenewalStatus,
            'renewal_bike_damage_reported',
          ])
          .eq('user_type', selectedRenewalUserType)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);

      final apps = List<Map<String, dynamic>>.from(appsResponse);
      final enriched = await Future.wait(apps.map((app) async {
        try {
          final sessionRes = await supabase
              .from('borrowing_sessions')
              .select('id, bike_id, start_time, end_time, status')
              .eq('application_id', app['id'])
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          
          // Also fetch bike info if available
          Map<String, dynamic>? bikeInfo;
          if (sessionRes != null && sessionRes['bike_id'] != null) {
            bikeInfo = await supabase
                .from('bikes')
                .select('*')
                .eq('id', sessionRes['bike_id'])
                .maybeSingle();
          } else if (app['renewal_gso_bike_id'] != null) {
            // For renewals, also check renewal_gso_bike_id
            bikeInfo = await supabase
                .from('bikes')
                .select('*')
                .eq('id', app['renewal_gso_bike_id'])
                .maybeSingle();
          }
          
          return {
            ...app, 
            'borrowing_sessions': sessionRes,
            'bike_info': bikeInfo,
          };
        } catch (_) {
          return {...app, 'borrowing_sessions': null, 'bike_info': null};
        }
      }));
      setState(() => renewalActiveBorrows = enriched);
    } catch (e) {
      debugPrint('Fetch renewal borrows error: $e');
    }
  }

  Future<void> _fetchShortTermBorrows() async {
    if (userCampus == null) return;
    try {
      final response = await supabase
          .from('short_term_borrowing_requests')
          .select('*')
          .eq('status', selectedShortTermStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);

      final requests = List<Map<String, dynamic>>.from(response);
      final enriched = await Future.wait(requests.map((req) async {
        try {
          final sessionId = req['session_id'];
          if (sessionId == null) return {...req, 'borrowing_sessions': null};
          final sessionRes = await supabase
              .from('borrowing_sessions')
              .select('id, bike_id, start_time, end_time, status')
              .eq('id', sessionId)
              .maybeSingle();
          return {...req, 'borrowing_sessions': sessionRes};
        } catch (_) {
          return {...req, 'borrowing_sessions': null};
        }
      }));
      setState(() => shortTermBorrows = enriched);
    } catch (e) {
      debugPrint('Fetch short term borrows error: $e');
    }
  }

  void _showReturnDialog(Map<String, dynamic> app, String type) {
    final session = app['borrowing_sessions'];
    final sessionId = session != null ? session['id']?.toString() : null;
    final applicantName = type == 'short_term'
        ? (app['full_name'] ?? 'Unknown')
        : '${app['first_name'] ?? app['firstName'] ?? ''} ${app['last_name'] ?? app['lastName'] ?? ''}'.trim();
    final bikeNumber = type == 'short_term'
        ? (app['assigned_bike_number'] ?? 'N/A')
        : (app['renewal_gso_bike_number'] ?? app['assigned_bike_number'] ?? app['bike_number'] ?? app['bikeNumber'] ?? 'N/A');
    final applicationId = app['id']?.toString() ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReturnDialog(
        applicationId: applicationId,
        sessionId: sessionId,
        applicantName: applicantName,
        bikeNumber: bikeNumber,
        applicationType: type,
        startTime: session?['start_time'],
        bikeInfo: app['bike_info'],
        userType: app['user_type'],
        suspensionCount: app['suspension_count'] ?? 0,
        onReturned: () async {
          await _fetchAll();
          setState(() {});
        },
      ),
    );
  }

  void _showRenewalBikeInspectionDialog(Map<String, dynamic> app) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RenewalBikeInspectionDialog(
        application: app,
        userCampus: userCampus,
        onComplete: () async {
          await _fetchAll();
          setState(() {});
        },
      ),
    );
  }


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
                          const SizedBox(height: 32),
                          _buildMainToggle(),
                          const SizedBox(height: 20),
                          _buildStatusFilter(),
                          const SizedBox(height: 24),
                          if (selectedTab == 'new')
                            _buildNewBorrowsList()
                          else if (selectedTab == 'renewal')
                            _buildRenewalBorrowsList()
                          else if (selectedTab == 'short_term')
                            _buildShortTermList(),
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
                    colors: [Color(0xFF00695C), Color(0xFF26A69A)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_return_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GSO Bike Return & Inspection',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Process returns & inspections'
                      : 'Process bike returns & inspections',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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

  Widget _buildMainToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mainToggleBtn('new', 'New Borrowers', Icons.fiber_new_rounded, null),
          _mainToggleBtn('renewal', 'Renewal Inspection',
              Icons.autorenew_rounded, const Color(0xFF7B1FA2)),
          if (_isShortTermEnabled)
            _mainToggleBtn('short_term', 'Short Term',
                Icons.access_time_rounded, const Color(0xFFF57C00)),
        ],
      ),
    );
  }

  Widget _mainToggleBtn(
      String value, String label, IconData icon, Color? activeColor) {
    final isSelected = selectedTab == value;
    final color = activeColor ?? const Color(0xFF00695C);
    return GestureDetector(
      onTap: () => setState(() => selectedTab = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
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
                size: 18,
                color: isSelected ? Colors.white : Colors.grey[500]),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey[500])),
          ],
        ),
      ),
    );
  }
  Widget _userTypeToggle(String value, String label, IconData icon) {
  final isSelected = selectedRenewalUserType == value;
  final color = const Color(0xFF7B1FA2);
  return GestureDetector(
    onTap: () {
      setState(() {
        selectedRenewalUserType = value;
        // Reset to a valid status for the selected type
        selectedRenewalStatus = 'renewal_medical_approved';
      });
      _fetchRenewalBorrows();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: isSelected
            ? [BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))]
            : [],
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey[500])),
        ],
      ),
    ),
  );
}

  Widget _buildStatusFilter() {
    if (selectedTab == 'new') {
      return Row(children: [
        _statusChip(
            value: 'active',
            label: 'Active Borrows',
            icon: Icons.pedal_bike_rounded,
            color: const Color(0xFF1565C0),
            isNew: true),
        const SizedBox(width: 12),
        _statusChip(
            value: 'ride_completed',
            label: 'Returned',
            icon: Icons.assignment_turned_in_rounded,
            color: const Color(0xFF00695C),
            isNew: true),
      ]);
    } else if (selectedTab == 'renewal') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Student / Personnel toggle ──
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _userTypeToggle('student', 'Student', Icons.school_rounded),
              _userTypeToggle('personnel', 'Personnel', Icons.badge_rounded),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Status chips ──
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _renewalStatusChip('renewal_medical_approved', 'Pending Inspection',
                Icons.search_rounded, const Color(0xFFF57C00)),
            const SizedBox(width: 12),
            _renewalStatusChip('renewal_bike_damage_reported', 'Damage Reported',
                Icons.report_problem_rounded, const Color(0xFFD32F2F)),
            const SizedBox(width: 12),
            _renewalStatusChip('active_renewal', 'Active Renewal',
                Icons.pedal_bike_rounded, const Color(0xFF1565C0)),
            const SizedBox(width: 12),
            // Only show this chip for students
            if (selectedRenewalUserType == 'student')
              _renewalStatusChip('renewal_pending_next_sem', 'Pending Next Sem',
                  Icons.schedule_rounded, Colors.teal),
          ]),
        ),
      ],
    );

    } else if (selectedTab == 'short_term') {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _shortTermStatusChip('active', 'Active',
              Icons.directions_bike_rounded, const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _shortTermStatusChip('completed', 'Completed',
              Icons.task_alt_rounded, Colors.teal),
          const SizedBox(width: 12),
          _shortTermStatusChip('overdue', 'Overdue',
              Icons.warning_amber_rounded, Colors.deepOrange),
          const SizedBox(width: 12),
          _shortTermStatusChip('returned_terminated', 'Returned Late',
              Icons.assignment_late_rounded, Colors.orange),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _renewalStatusChip(
      String value, String label, IconData icon, Color color) {
    final isSelected = selectedRenewalStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedRenewalStatus = value);
        _fetchRenewalBorrows();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }

  Widget _shortTermStatusChip(
      String value, String label, IconData icon, Color color) {
    final isSelected = selectedShortTermStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedShortTermStatus = value);
        _fetchShortTermBorrows();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
    required bool isNew,
  }) {
    final isSelected = selectedNewStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedNewStatus = value);
        _fetchNewBorrows();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isSelected ? Colors.white : color),
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

  // ── New Borrows ─────────────────────────────────────────────

  Widget _buildNewBorrowsList() {
    if (newActiveBorrows.isEmpty) {
      return _emptyState(selectedNewStatus == 'active'
          ? 'No active borrows at the moment'
          : 'No returned bikes yet');
    }
    return Column(
        children: newActiveBorrows
            .map((app) => _borrowCard(app, 'new'))
            .toList());
  }

  // ── Renewal Borrows ─────────────────────────────────────────

  Widget _buildRenewalBorrowsList() {
    if (renewalActiveBorrows.isEmpty) {
      return _emptyState(_getRenewalEmptyMessage());
    }
    return Column(
        children: renewalActiveBorrows
            .map((app) => _renewalInspectionCard(app))
            .toList());
  }

  String _getRenewalEmptyMessage() {
    switch (selectedRenewalStatus) {
      case 'renewal_medical_approved':
        return selectedRenewalUserType == 'student'
            ? 'No students pending bike inspection'
            : 'No personnel pending bike inspection';
      case 'renewal_bike_damage_reported':
        return 'No damage reports to verify';
      case 'active_renewal':
        return selectedRenewalUserType == 'student'
            ? 'No active student renewals'
            : 'No active personnel renewals';
      case 'renewal_pending_next_sem':
        return 'No students pending next semester';
      default:
        return 'No renewal applications';
    }
  }

  Widget _renewalInspectionCard(Map<String, dynamic> app) {
    final firstName = app['first_name'] ?? '';
    final lastName = app['last_name'] ?? '';
    final userType = app['user_type'] ?? 'student';
    final status = app['status'] ?? '';
    final bikeNumber = app['renewal_gso_bike_number'] ?? app['assigned_bike_number'] ?? 'N/A';
    final suspensionCount = app['suspension_count'] ?? 0;
    final isDamageReported = status == 'renewal_bike_damage_reported';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'renewal_medical_approved':
        statusColor = const Color(0xFFF57C00);
        statusLabel = 'Pending Inspection';
        statusIcon = Icons.search_rounded;
        break;
      case 'renewal_bike_damage_reported':
        statusColor = const Color(0xFFD32F2F);
        statusLabel = 'Damage Reported';
        statusIcon = Icons.report_problem_rounded;
        break;
      case 'active_renewal':
        statusColor = const Color(0xFF1565C0);
        statusLabel = 'Active Renewal';
        statusIcon = Icons.pedal_bike_rounded;
        break;
      case 'renewal_pending_next_sem':
        statusColor = Colors.teal;
        statusLabel = 'Pending Next Sem';
        statusIcon = Icons.schedule_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = status.replaceAll('_', ' ').toUpperCase();
        statusIcon = Icons.info_rounded;
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
        border: Border.all(
          color: isDamageReported 
              ? const Color(0xFFD32F2F).withOpacity(0.4)
              : statusColor.withOpacity(0.2), 
          width: isDamageReported ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('$firstName $lastName',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                      const SizedBox(width: 8),
                      _badge('Renewal', const Color(0xFF7B1FA2)),
                      const SizedBox(width: 6),
                      _badge(
                        userType == 'student' ? 'Student' : 'Personnel',
                        userType == 'student' 
                            ? const Color(0xFF1565C0) 
                            : const Color(0xFF388E3C),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      userType == 'student'
                          ? 'SR Code: ${app['sr_code'] ?? app['id_no'] ?? "N/A"}'
                          : 'Employee No: ${app['employee_no'] ?? app['id_no'] ?? "N/A"}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.pedal_bike_rounded,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('Bike No: $bikeNumber',
                          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                      if (suspensionCount > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Prior Offense: $suspensionCount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[900],
                            ),
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    _statusBadge(statusLabel, statusColor),
                  ],
                ),
              ),
            ],
          ),
          
          // Show damage details if reported
          if (isDamageReported && app['renewal_gso_damage_remarks'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, 
                        color: Color(0xFFD32F2F), size: 16),
                    const SizedBox(width: 6),
                    const Text('Self-Reported Damage',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD32F2F))),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    app['renewal_gso_damage_remarks'] ?? 'No details provided',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Action buttons based on status
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (status == 'renewal_medical_approved' || 
                  status == 'renewal_bike_damage_reported')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showRenewalBikeInspectionDialog(app),
                  icon: const Icon(Icons.bike_scooter_rounded, size: 18),
                  label: Text(
                    isDamageReported ? 'Verify Damage' : 'Inspect Bike',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (status == 'active_renewal')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showReturnDialog(app, 'renewal'),
                  icon: const Icon(Icons.assignment_return_rounded, size: 18),
                  label: const Text('Process Return',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Short Term Borrows ──────────────────────────────────────

  Widget _buildShortTermList() {
    if (shortTermBorrows.isEmpty) {
      return _emptyState('No $selectedShortTermStatus short-term borrows');
    }
    return Column(
        children: shortTermBorrows
            .map((req) => _shortTermCard(req))
            .toList());
  }

  Widget _shortTermCard(Map<String, dynamic> req) {
    final fullName = req['full_name'] ?? 'Unknown';
    final bikeNumber = req['assigned_bike_number'] ?? 'N/A';
    final status = req['status'] as String? ?? '';
    final session = req['borrowing_sessions'];
    final startTime = session?['start_time'];
    final userType = req['user_type'] ?? '';

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'active':
        statusColor = const Color(0xFF1565C0);
        statusLabel = 'Active';
        break;
      case 'completed':
        statusColor = Colors.teal;
        statusLabel = 'Completed';
        break;
      case 'overdue':
        statusColor = Colors.deepOrange;
        statusLabel = 'Overdue';
        break;
      case 'returned_terminated':
        statusColor = Colors.orange;
        statusLabel = 'Returned Late';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = status.toUpperCase();
    }

    String startTimeLabel = 'N/A';
    if (startTime != null) {
      try {
        final dt = DateTime.parse(startTime.toString()).toLocal();
        startTimeLabel =
            '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    String getInitials(String name) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2) return parts[0][0] + parts[parts.length - 1][0];
      if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0];
      return 'U';
    }

    final isActive = status == 'active' || status == 'overdue';

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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.1),
              border: Border.all(color: statusColor, width: 2),
            ),
            child: req['profile_pic_url'] != null &&
                    req['profile_pic_url'].toString().isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      req['profile_pic_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(getInitials(fullName),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: statusColor)),
                      ),
                    ),
                  )
                : Center(
                    child: Text(getInitials(fullName),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(fullName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  _badge('Short Term', const Color(0xFFF57C00)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: userType == 'student'
                          ? Colors.blue[100]
                          : Colors.green[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      userType.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: userType == 'student'
                              ? Colors.blue[900]
                              : Colors.green[900]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    userType == 'student'
                        ? 'SR: ${req['sr_code'] ?? 'N/A'}'
                        : 'Emp: ${req['employee_no'] ?? 'N/A'}',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.pedal_bike_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Bike No: $bikeNumber',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.access_time_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Started: $startTimeLabel',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                ]),
                const SizedBox(height: 8),
                _statusBadge(statusLabel, statusColor),
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReturnDialog(req, 'short_term'),
              icon: const Icon(Icons.assignment_return_rounded, size: 18),
              label: const Text('Process Return',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _borrowCard(Map<String, dynamic> app, String type) {
    final firstName = app['first_name'] ?? app['firstName'] ?? '';
    final lastName = app['last_name'] ?? app['lastName'] ?? '';
    final bikeNumber = app['bike_number'] ?? app['bikeNumber'] ?? app['assigned_bike_number'] ?? 'N/A';
    final status = app['status'] ?? '';
    final srCode = app['sr_code'] ?? app['srCode'];
    final employeeNo = app['employee_no'] ?? app['employeeNo'];
    final idNumber = app['id_number'];
    final session = app['borrowing_sessions'];
    final startTime = session?['start_time'];

    final isActive = status == 'active' || status == 'renewal_gso';
    final isReturned = status == 'ride_completed';

    final Color statusColor = isActive
        ? const Color(0xFF1565C0)
        : isReturned
            ? const Color(0xFF00695C)
            : Colors.grey;

    final String statusLabel = isActive
        ? 'Currently Borrowed'
        : isReturned
            ? 'Returned'
            : status;

    String displayId = '';
    if (srCode != null && srCode.toString().isNotEmpty) {
      displayId = 'SR Code: $srCode';
    } else if (employeeNo != null && employeeNo.toString().isNotEmpty) {
      displayId = 'Employee No: $employeeNo';
    } else if (idNumber != null && idNumber.toString().isNotEmpty) {
      displayId = 'ID: $idNumber';
    }

    String startTimeLabel = 'N/A';
    if (startTime != null) {
      try {
        final dt = DateTime.parse(startTime.toString()).toLocal();
        startTimeLabel =
            '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
        border:
            Border.all(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isReturned
                  ? Icons.assignment_turned_in_rounded
                  : Icons.pedal_bike_rounded,
              color: statusColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('$firstName $lastName',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 8),
                  _badge('New', const Color(0xFF1565C0)),
                ]),
                const SizedBox(height: 4),
                Text(displayId,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.pedal_bike_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Bike No: $bikeNumber',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(width: 12),
                  Icon(Icons.access_time_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Borrowed: $startTimeLabel',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                ]),
                const SizedBox(height: 10),
                _statusBadge(statusLabel, statusColor),
              ],
            ),
          ),
          if (isActive)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReturnDialog(app, type),
              icon: const Icon(Icons.assignment_return_rounded, size: 18),
              label: const Text('Process Return',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 72, color: Colors.grey[300]),
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
// RENEWAL BIKE INSPECTION DIALOG
// ═══════════════════════════════════════════════════════════════════
class _RenewalBikeInspectionDialog extends StatefulWidget {
  final Map<String, dynamic> application;
  final String? userCampus;
  final VoidCallback onComplete;

  const _RenewalBikeInspectionDialog({
    required this.application,
    required this.userCampus,
    required this.onComplete,
  });

  @override
  State<_RenewalBikeInspectionDialog> createState() =>
      _RenewalBikeInspectionDialogState();
}

class _RenewalBikeInspectionDialogState
    extends State<_RenewalBikeInspectionDialog> {
  final supabase = Supabase.instance.client;

  bool _isSubmitting = false;
  String _inspectionResult = 'no_damage'; // 'no_damage' or 'damaged'

  // Condition checklist
  bool _frameOk = true;
  bool _wheelsOk = true;
  bool _brakesOk = true;
  bool _chainGearOk = true;
  bool _saddleOk = true;
  bool _lightsOk = true;

  // Damage details
  final TextEditingController _damageRemarksController = TextEditingController();
  Uint8List? _damagePhotoBytes;
  String? _damagePhotoName;

  // GSO signature
  final TextEditingController _gsoNameController = TextEditingController();

  bool get _isStudent => widget.application['user_type'] == 'student';
  bool get _isDamageReported =>
      widget.application['status'] == 'renewal_bike_damage_reported';
  int get _suspensionCount => widget.application['suspension_count'] ?? 0;


  bool get _canSubmit =>
      _gsoNameController.text.trim().isNotEmpty &&
      (_inspectionResult == 'no_damage' || _damageRemarksController.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _loadGsoName();
    
    // If damage was self-reported, pre-fill remarks
    if (_isDamageReported && widget.application['renewal_gso_damage_remarks'] != null) {
      _damageRemarksController.text = widget.application['renewal_gso_damage_remarks'];
      _inspectionResult = 'damaged';
    }
    
    _gsoNameController.addListener(() => setState(() {}));
    _damageRemarksController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _damageRemarksController.dispose();
    _gsoNameController.dispose();
    super.dispose();
  }

  Future<void> _loadGsoName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final profile = await supabase
            .from('profiles')
            .select('email')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && mounted) {
          final email = profile['email'] as String;
          _gsoNameController.text =
              email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Error loading GSO name: $e');
    }
  }

  Future<void> _pickDamagePhoto() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final bytes = result.files.first.bytes;
      final fileName = result.files.first.name;
      if (bytes != null) {
        setState(() {
          _damagePhotoBytes = bytes;
          _damagePhotoName = fileName;
        });
      }
    }
  }

  Future<String?> _uploadDamagePhoto() async {
    if (_damagePhotoBytes == null) return null;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';
      final path = 'damage_photos/${userId}_${timestamp}_$_damagePhotoName';
      await supabase.storage.from('bike-images').uploadBinary(path, _damagePhotoBytes!);
      return supabase.storage.from('bike-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload damage photo error: $e');
      return null;
    }
  }

  Future<void> _submitInspection() async {
  if (!_canSubmit) return;
  setState(() => _isSubmitting = true);

  try {
    final applicationId = widget.application['id'];
    final now = DateTime.now().toUtc().toIso8601String();
    final currentUserId = supabase.auth.currentUser?.id;

    if (_inspectionResult == 'no_damage') {
      // NO DAMAGE PATH
      if (_isStudent) {
        // Student: No damage → renewal_pending_next_sem
        await supabase.from('borrowing_applications_version2').update({
          'status': 'renewal_pending_next_sem',
          'renewal_gso_checked_by': _gsoNameController.text.trim(),
          'updated_at': now,
        }).eq('id', applicationId);

        // Return the bike to available
        final bikeId = widget.application['renewal_gso_bike_id'] ??
            widget.application['assigned_bike_id'];
        if (bikeId != null) {
          await supabase.from('bikes').update({
            'status': 'available',
            'current_user_id': null,
          }).eq('id', bikeId);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student set to pending next semester. Bike returned.'),
              backgroundColor: Colors.teal,
            ),
          );
        }

        widget.onComplete();
        if (mounted) Navigator.pop(context);

      } else {
        // Personnel: No damage → open release dialog immediately
        // DON'T change status here, let the mobile app handle it after QR scan
        await supabase.from('borrowing_applications_version2').update({
          'renewal_gso_checked_by': _gsoNameController.text.trim(),
          'updated_at': now,
          // status stays as renewal_medical_approved
        }).eq('id', applicationId);

        if (mounted) {
          Navigator.pop(context); // close inspection dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => _PersonnelRenewalReleaseDialog(
              application: {
                ...widget.application,
                'renewal_gso_checked_by': _gsoNameController.text.trim(),
              },
              onComplete: widget.onComplete,
            ),
          );
        }
      }

    } else {
      // DAMAGED PATH
      String? damagePhotoUrl;
      if (_damagePhotoBytes != null) {
        damagePhotoUrl = await _uploadDamagePhoto();
      }

      final bikeId = widget.application['renewal_gso_bike_id'] ??
          widget.application['assigned_bike_id'];

      int? reportId;
      if (bikeId != null) {
        final reportResponse = await supabase.from('bike_reports').insert({
          'bike_id': bikeId,
          'application_id': applicationId,
          'is_renewal': true,
          'report_type': 'damage',
          'description': _damageRemarksController.text.trim(),
          'photo_url': damagePhotoUrl,
          'reported_by': currentUserId,
          'status': 'pending',
          'created_at': now,
        }).select('id').single();
        reportId = reportResponse['id'];
      }

      if (_suspensionCount >= 1) {
        // 2nd offense → terminated
        await supabase.from('borrowing_applications_version2').update({
          'status': 'terminated',
          'renewal_gso_checked_by': _gsoNameController.text.trim(),
          'renewal_gso_damage_remarks': _damageRemarksController.text.trim(),
          'renewal_gso_damage_photo_url': damagePhotoUrl,
          'renewal_gso_damage_report_id': reportId,
          'renewal_terminated_at': now,
          'renewal_terminated_by': currentUserId,
          'renewal_terminated_remarks': 'Second offense - automatic termination',
          'updated_at': now,
        }).eq('id', applicationId);
      } else {
        // 1st offense → forward to discipline/HRMO
        final nextStatus = _isStudent ? 'forwarded_discipline' : 'forwarded_hrmo';

        await supabase.from('borrowing_applications_version2').update({
          'status': 'renewal_bike_damaged',
          'renewal_gso_checked_by': _gsoNameController.text.trim(),
          'renewal_gso_damage_remarks': _damageRemarksController.text.trim(),
          'renewal_gso_damage_photo_url': damagePhotoUrl,
          'renewal_gso_damage_report_id': reportId,
          'updated_at': now,
        }).eq('id', applicationId);

        await supabase.from('borrowing_applications_version2').update({
          'status': nextStatus,
          'renewal_forwarded_by': _gsoNameController.text.trim(),
          'renewal_forwarded_remarks': 'Bike damage confirmed during inspection',
          'updated_at': now,
        }).eq('id', applicationId);
      }

      // Set bike to maintenance
      if (bikeId != null) {
        await supabase.from('bikes').update({
          'status': 'maintenance',
          'current_user_id': null,
        }).eq('id', bikeId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _suspensionCount >= 1
                  ? 'Second offense detected. Application terminated.'
                  : 'Damage reported. Forwarded to ${_isStudent ? 'Discipline Office' : 'HRMO'}.',
            ),
            backgroundColor: _suspensionCount >= 1 ? Colors.red : Colors.orange,
          ),
        );
      }

      widget.onComplete();
      if (mounted) Navigator.pop(context);
    }

  } catch (e) {
    debugPrint('Submit inspection error: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    setState(() => _isSubmitting = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final firstName = widget.application['first_name'] ?? '';
    final lastName = widget.application['last_name'] ?? '';
    final bikeNumber = widget.application['renewal_gso_bike_number'] ?? 
                       widget.application['assigned_bike_number'] ?? 'N/A';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 800),
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
                    gradient: const LinearGradient(
                        colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bike_scooter_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isDamageReported 
                            ? 'Verify Damage Report' 
                            : 'Bike Inspection',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                      ),
                      Text(
                        '$firstName $lastName • Bike #$bikeNumber',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _typeBadge(_isStudent ? 'Student' : 'Personnel',
                    _isStudent ? const Color(0xFF1565C0) : const Color(0xFF388E3C)),
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

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Warning if prior offense
                    if (_suspensionCount > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFD32F2F).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFD32F2F), size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Prior Offense Record',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD32F2F)),
                                  ),
                                  Text(
                                    _suspensionCount >= 1
                                        ? 'This borrower has $_suspensionCount prior offense(s). Another damage will result in TERMINATION.'
                                        : 'First offense will result in 1-semester suspension.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red[800]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Self-reported damage notice
                    if (_isDamageReported) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFF57C00).withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: Color(0xFFF57C00), size: 18),
                              const SizedBox(width: 8),
                              const Text('Self-Reported Damage',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF57C00))),
                            ]),
                            const SizedBox(height: 8),
                            Text(
                              'Borrower reported: ${widget.application['renewal_gso_damage_remarks'] ?? 'No details'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Condition Checklist
                    const Text('Bike Condition Checklist',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text('Check each component during inspection:',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 14),

                    _conditionCheck('Frame & Body', 'No visible damage or cracks',
                        _frameOk, (v) => setState(() => _frameOk = v!)),
                    _conditionCheck('Wheels & Tires', 'Properly inflated, no damage',
                        _wheelsOk, (v) => setState(() => _wheelsOk = v!)),
                    _conditionCheck('Brakes', 'Front and rear functioning',
                        _brakesOk, (v) => setState(() => _brakesOk = v!)),
                    _conditionCheck('Chain & Gears', 'Lubricated, shifting properly',
                        _chainGearOk, (v) => setState(() => _chainGearOk = v!)),
                    _conditionCheck('Saddle & Handlebars', 'Secured and adjusted',
                        _saddleOk, (v) => setState(() => _saddleOk = v!)),
                    _conditionCheck('Lights & Reflectors', 'Present and working',
                        _lightsOk, (v) => setState(() => _lightsOk = v!)),

                    const SizedBox(height: 24),

                    // Inspection Result
                    const Text('Inspection Result *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _resultOption(
                            'no_damage',
                            'No Damage',
                            Icons.check_circle_rounded,
                            const Color(0xFF388E3C),
                            _isStudent
                                ? 'Bike returned, student waits for next semester'
                                : 'Ready for QR scan activation',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _resultOption(
                            'damaged',
                            'Damaged',
                            Icons.report_problem_rounded,
                            const Color(0xFFD32F2F),
                            _suspensionCount >= 1
                                ? 'TERMINATION (2nd offense)'
                                : (_isStudent
                                    ? 'Forward to Discipline Office'
                                    : 'Forward to HRMO'),
                          ),
                        ),
                      ],
                    ),

                    // Damage details (if damaged selected)
                    if (_inspectionResult == 'damaged') ...[
                      const SizedBox(height: 20),

                      const Text('Damage Details *',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 8),

                      TextField(
                        controller: _damageRemarksController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Describe the damage in detail...',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFD32F2F), width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text('Damage Photo (Optional)',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 8),

                      GestureDetector(
                        onTap: _pickDamagePhoto,
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[400]!),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: _damagePhotoBytes == null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo_rounded,
                                          size: 32, color: Colors.grey[400]),
                                      const SizedBox(height: 8),
                                      Text('Click to upload photo',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500])),
                                    ],
                                  ),
                                )
                              : Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(_damagePhotoBytes!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            color: Colors.white),
                                        onPressed: () => setState(() {
                                          _damagePhotoBytes = null;
                                          _damagePhotoName = null;
                                        }),
                                        style: IconButton.styleFrom(
                                            backgroundColor:
                                                Colors.black54),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // GSO Name
                    const Text('GSO Officer Name *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _gsoNameController,
                      decoration: InputDecoration(
                        hintText: 'Enter officer name',
                        prefixIcon: const Icon(Icons.badge_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: Colors.grey[600])),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canSubmit
                        ? (_inspectionResult == 'damaged'
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF388E3C))
                        : Colors.grey[300],
                    foregroundColor:
                        _canSubmit ? Colors.white : Colors.grey[500],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSubmitting || !_canSubmit ? null : _submitInspection,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          _inspectionResult == 'damaged'
                              ? Icons.report_problem_rounded
                              : Icons.check_circle_rounded,
                          size: 18),
                  label: Text(
                    _isSubmitting
                        ? 'Processing...'
                        : _inspectionResult == 'damaged'
                            ? (_suspensionCount >= 1 
                                ? 'Confirm Termination'
                                : 'Report Damage & Forward')
                            : 'Confirm No Damage',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _conditionCheck(String label, String description, bool value,
      void Function(bool?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFD32F2F))),
                Text(description,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          Icon(
            value ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: value ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _resultOption(String value, String label, IconData icon, Color color,
      String description) {
    final isSelected = _inspectionResult == value;
    return GestureDetector(
      onTap: () => setState(() => _inspectionResult = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey[400], size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : Colors.grey[600])),
            const SizedBox(height: 4),
            Text(description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// RETURN DIALOG (for active borrows)
// ═══════════════════════════════════════════════════════════════════
class _ReturnDialog extends StatefulWidget {
  final String applicationId;
  final String? sessionId;
  final String applicantName;
  final String bikeNumber;
  final String applicationType;
  final dynamic startTime;
  final Map<String, dynamic>? bikeInfo;
  final String? userType;
  final int suspensionCount;
  final VoidCallback onReturned;

  const _ReturnDialog({
    required this.applicationId,
    required this.sessionId,
    required this.applicantName,
    required this.bikeNumber,
    required this.applicationType,
    required this.startTime,
    this.bikeInfo,
    this.userType,
    this.suspensionCount = 0,
    required this.onReturned,
  });

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _showingQr = false;
  bool _isReturned = false;
  bool _isSubmitting = false;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool get _isRenewal => widget.applicationType == 'renewal';
  bool get _isShortTerm => widget.applicationType == 'short_term';

  String get _qrData =>
      'RETURN_${widget.sessionId ?? widget.applicationId}';

  String get _completedStatus =>
      _isShortTerm ? 'completed' : 'ride_completed';

  String get _durationLabel {
    if (widget.startTime == null) return 'N/A';
    try {
      final start =
          DateTime.parse(widget.startTime.toString()).toLocal();
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
      final dt =
          DateTime.parse(widget.startTime.toString()).toLocal();
      final months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'N/A';
    }
  }

  Color get _accentColor => _isShortTerm
      ? const Color(0xFFF57C00)
      : _isRenewal
          ? const Color(0xFF4A148C)
          : const Color(0xFF004D40);

  Color get _accentLight => _isShortTerm
      ? const Color(0xFFFFF3E0)
      : _isRenewal
          ? const Color(0xFFF3E5F5)
          : const Color(0xFFE0F2F1);

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
    if (_channel != null) supabase.removeChannel(_channel!);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _generateReturnQr() async {
    if (widget.sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No active session found.'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await supabase.from('borrowing_sessions').update({
        'return_initiated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.sessionId!);
    } catch (e) {
      debugPrint('Optional return_initiated_at update skipped: $e');
    }

    setState(() {
      _showingQr = true;
      _isSubmitting = false;
    });

    _startRealtimeListener();
    _startPollingFallback();
  }

  void _startRealtimeListener() {
    if (widget.sessionId == null) return;
    final channelName =
        'return_${widget.applicationType}_${widget.sessionId}_${DateTime.now().millisecondsSinceEpoch}';
    _channel = supabase.channel(channelName);
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'borrowing_sessions',
          callback: (payload) {
            final newStatus = payload.newRecord['status'];
            final recordId = payload.newRecord['id'].toString();
            if (recordId == widget.sessionId &&
                (newStatus == _completedStatus ||
                    newStatus == 'returned_terminated') &&
                !_isReturned &&
                mounted) {
              _onReturnDetected();
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Return Realtime: $status, error: $error');
          if (status == RealtimeSubscribeStatus.closed && !_isReturned) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && !_isReturned) _startRealtimeListener();
            });
          }
        });
  }

  void _startPollingFallback() {
    if (widget.sessionId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isReturned) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final row = await supabase
            .from('borrowing_sessions')
            .select('status')
            .eq('id', widget.sessionId!)
            .maybeSingle();
        if (row != null &&
            (row['status'] == _completedStatus ||
                row['status'] == 'returned_terminated') &&
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
    widget.onReturned();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
            Expanded(
              child: _showingQr ? _buildQrView() : _buildSummaryView(),
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
                colors: [_accentColor, _accentColor.withOpacity(0.7)]),
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
                _showingQr ? 'Waiting for Borrower' : 'Process Bike Return',
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accentColor),
          ),
          child: Text(
            _qrData,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _accentColor),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildSummaryView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _accentLight,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: _accentColor.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: _accentColor, size: 20),
                  const SizedBox(width: 8),
                  Text('Return Summary',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _accentColor)),
                  const Spacer(),
                  _typeBadge(),
                ]),
                const SizedBox(height: 16),
                _summaryRow(
                    Icons.person_rounded, 'Borrower', widget.applicantName),
                const SizedBox(height: 10),
                _summaryRow(Icons.pedal_bike_rounded, 'Bike Number',
                    widget.bikeNumber),
                const SizedBox(height: 10),
                _summaryRow(Icons.play_circle_outline_rounded,
                    'Borrow Start', _startTimeLabel),
                const SizedBox(height: 10),
                _summaryRow(Icons.timer_outlined, 'Duration So Far',
                    _durationLabel),
                const SizedBox(height: 10),
                _summaryRow(Icons.tag_rounded, 'Session ID',
                    widget.sessionId ?? 'N/A'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Return Process',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700])),
                const SizedBox(height: 12),
                _instructionRow(
                    '1', 'Click "Generate Return QR" below'),
                _instructionRow(
                    '2', 'Show QR code to the borrower'),
                _instructionRow(
                    '3', 'Borrower scans → face verification'),
                _instructionRow(
                    '4', 'Borrower confirms return on their phone'),
                _instructionRow('5',
                    'Status auto-updates to "$_completedStatus" ✅'),
              ],
            ),
          ),

          if (widget.sessionId == null) ...[
            const SizedBox(height: 16),
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
                        'No active session found. Please verify manually.',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFD32F2F)))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _accentColor),
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

  Widget _instructionRow(String number, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(99)),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge() {
    final label = _isShortTerm
        ? 'Short Term'
        : _isRenewal
            ? 'Renewal'
            : 'New';
    final color = _isShortTerm
        ? const Color(0xFFF57C00)
        : _isRenewal
            ? const Color(0xFF7B1FA2)
            : const Color(0xFF1565C0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  Widget _buildQrView() {
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
                        'Borrower completed return! Bike successfully returned.',
                  )
                : _statusBanner(
                    key: const ValueKey('waiting'),
                    color: _accentColor,
                    bgColor: _accentLight,
                    icon: null,
                    message:
                        'Waiting for borrower to complete return on the PedalHub app…',
                  ),
          ),

          const SizedBox(height: 24),

          Text(
            _isReturned
                ? '✅  Bike returned successfully!'
                : 'Ask the borrower to scan this QR',
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
              final glowColor =
                  _isReturned ? const Color(0xFF00695C) : _accentColor;
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: glowColor.withOpacity(
                          _isReturned ? 1.0 : _pulseAnimation.value),
                      width: _isReturned ? 3 : 2),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.2 *
                          (_isReturned ? 1 : _pulseAnimation.value)),
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
                      eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: _accentColor),
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
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _accentColor.withOpacity(0.3))),
            child: Text(
              _qrData,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: _accentColor),
            ),
          ),

          const SizedBox(height: 20),

          if (!_isReturned) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Borrower completes on their phone:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 10),
                  _stepRow('1',
                      'Scan QR → validates RETURN-{session_id}'),
                  _stepRow('2', 'Face verification'),
                  _stepRow('3', 'Review return details'),
                  _stepRow('4',
                      'Confirm → status set to "$_completedStatus"'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _accentLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _accentColor.withOpacity(0.2))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Borrower',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500)),
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
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500)),
                        Text(widget.bikeNumber,
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
                        Text('Duration',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500)),
                        Text(_durationLabel,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A))),
                      ],
                    ),
                  ),
                ],
              ),
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

  Widget _stepRow(String number, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(99)),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[700])),
          ),
        ],
      ),
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
          Text('QR active — waiting for borrower to scan…',
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: Colors.grey[600])),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.sessionId != null
                ? _accentColor
                : Colors.grey[300],
            foregroundColor: widget.sessionId != null
                ? Colors.white
                : Colors.grey[500],
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: widget.sessionId != null ? 2 : 0,
          ),
          onPressed: _isSubmitting || widget.sessionId == null
              ? null
              : _generateReturnQr,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.qr_code_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'Preparing…' : 'Generate Return QR',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
class _PersonnelRenewalReleaseDialog extends StatefulWidget {
  final Map<String, dynamic> application;
  final VoidCallback onComplete;

  const _PersonnelRenewalReleaseDialog({
    required this.application,
    required this.onComplete,
  });

  @override
  State<_PersonnelRenewalReleaseDialog> createState() =>
      _PersonnelRenewalReleaseDialogState();
}

class _PersonnelRenewalReleaseDialogState
    extends State<_PersonnelRenewalReleaseDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _isSubmitting = false;
  bool _showingQr = false;
  bool _isReleased = false;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _officerNameController = TextEditingController();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  bool _isDrawMode = true;
  bool _hasSignature = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;

  String get _applicationId => widget.application['id'].toString();
  String get _applicantName =>
      '${widget.application['first_name'] ?? ''} ${widget.application['last_name'] ?? ''}'.trim();
  String get _bikeNumber =>
      widget.application['renewal_gso_bike_number'] ??
      widget.application['assigned_bike_number'] ??
      'N/A';
  dynamic get _bikeId =>
      widget.application['renewal_gso_bike_id'] ??
      widget.application['assigned_bike_id'];

  String get _qrData => 'RENEWAL-$_applicationId';

  bool get _canGenerateQr =>
      _hasSignature && _officerNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadOfficerName();
    _signatureController.addListener(() {
      setState(() {
        _hasSignature =
            _signatureController.isNotEmpty || _uploadedImageBytes != null;
      });
    });
    _officerNameController.addListener(() => setState(() {}));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _officerNameController.dispose();
    _pollTimer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel!);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadOfficerName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final profile = await supabase
            .from('profiles')
            .select('email')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && mounted) {
          final email = profile['email'] as String;
          _officerNameController.text =
              email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Error loading officer name: $e');
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
      final path = 'gso_signatures/${userId}_${timestamp}_$fileName';
      await supabase.storage.from('signatures').uploadBinary(path, bytes);
      return supabase.storage.from('signatures').getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _generateQr() async {
    if (!_canGenerateQr) return;
    setState(() => _isSubmitting = true);

    try {
      Uint8List? sigBytes;
      String fileName;
      if (_isDrawMode) {
        sigBytes = await _signatureController.toPngBytes();
        if (sigBytes == null) throw Exception('Failed to export signature');
        fileName = 'drawn_signature.png';
      } else {
        sigBytes = _uploadedImageBytes!;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      final signatureUrl = await _uploadSignature(sigBytes, fileName);
      if (signatureUrl == null) throw Exception('Signature upload failed');

      final now = DateTime.now().toUtc().toIso8601String();

      // Save GSO signature info — bike stays the same
      await supabase.from('borrowing_applications_version2').update({
        'renewal_gso_checked_by': _officerNameController.text.trim(),
        'renewal_gso_signature_url': signatureUrl,
        'updated_at': now,
      }).eq('id', _applicationId);

      // Mark the existing bike as reserved until QR scan confirms
      if (_bikeId != null) {
        await supabase.from('bikes').update({
          'status': 'in_use',
          'current_user_id': null,
        }).eq('id', _bikeId);
      }

      setState(() {
        _showingQr = true;
        _isSubmitting = false;
      });

      _startRealtimeListener();
      _startPollingFallback();
    } catch (e) {
      debugPrint('Generate QR error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _startRealtimeListener() {
    final channelName =
        'personnel_renewal_${_applicationId}_${DateTime.now().millisecondsSinceEpoch}';
    _channel = supabase.channel(channelName,
        opts: const RealtimeChannelConfig(ack: true));
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'borrowing_applications_version2',
          callback: (payload) {
            final newStatus = payload.newRecord['status'];
            final recordId = payload.newRecord['id'].toString();
            if (recordId == _applicationId &&
                newStatus == 'active_renewal' &&
                !_isReleased &&
                mounted) {
              _onReleaseDetected();
            }
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.closed && !_isReleased) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && !_isReleased) _startRealtimeListener();
            });
          }
        });
  }

  void _startPollingFallback() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isReleased) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final row = await supabase
            .from('borrowing_applications_version2')
            .select('status')
            .eq('id', _applicationId)
            .maybeSingle();
        if (row != null && row['status'] == 'active_renewal' && mounted) {
          _onReleaseDetected();
        }
      } catch (e) {
        debugPrint('Poll error: $e');
      }
    });
  }

  void _onReleaseDetected() {
    if (_isReleased) return;
    setState(() => _isReleased = true);
    _pollTimer?.cancel();
    _pulseController.stop();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 780),
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
                    gradient: const LinearGradient(
                        colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _showingQr
                        ? Icons.qr_code_2_rounded
                        : Icons.autorenew_rounded,
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
                        _showingQr
                            ? 'Waiting for Personnel'
                            : 'Personnel Renewal Release',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                      ),
                      Text(
                        _showingQr
                            ? 'Ask personnel to scan QR with the PedalHub app'
                            : '$_applicantName • Bike #$_bikeNumber',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF388E3C).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF388E3C)),
                  ),
                  child: Text(
                    _qrData,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF388E3C)),
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
              child: _showingQr ? _buildQrView() : _buildFormView(),
            ),

            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF388E3C).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF388E3C), size: 16),
                  const SizedBox(width: 6),
                  const Text('Bike Inspection Passed',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF388E3C),
                          fontSize: 13)),
                ]),
                const SizedBox(height: 6),
                Text(
                  'No damage found. Personnel will keep their current bike. Provide your signature and generate the QR for them to scan.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.pedal_bike_rounded,
                      size: 14, color: Color(0xFF388E3C)),
                  const SizedBox(width: 6),
                  Text(
                    'Assigned Bike: #$_bikeNumber',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF388E3C)),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Officer name
          const Text('GSO Officer Name *',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          TextField(
            controller: _officerNameController,
            decoration: InputDecoration(
              hintText: 'Enter officer full name',
              prefixIcon: const Icon(Icons.badge_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          // Signature
          const Text('GSO Signature *',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Draw or upload your signature:',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
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
                                icon: const Icon(Icons.upload_file, size: 20),
                                label: const Text('Upload Signature'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF388E3C),
                                    foregroundColor: Colors.white),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_uploadedImageBytes!,
                                  fit: BoxFit.contain)),
                ),
              ),
              const SizedBox(width: 10),
              Column(children: [
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () {
                    _signatureController.clear();
                    setState(() {
                      _uploadedImageBytes = null;
                      _hasSignature = false;
                    });
                  },
                ),
                IconButton(
                  icon:
                      Icon(_isDrawMode ? Icons.upload_file : Icons.edit),
                  tooltip: _isDrawMode
                      ? 'Switch to Upload'
                      : 'Switch to Draw',
                  onPressed: () {
                    setState(() {
                      _isDrawMode = !_isDrawMode;
                      _uploadedImageBytes = null;
                      _hasSignature = _signatureController.isNotEmpty;
                    });
                  },
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _isReleased
                ? _statusBanner(
                    key: const ValueKey('released'),
                    color: const Color(0xFF388E3C),
                    bgColor: const Color(0xFFE8F5E9),
                    icon: Icons.check_circle_rounded,
                    message:
                        'Personnel scanned QR! Renewal is now active.',
                  )
                : _statusBanner(
                    key: const ValueKey('waiting'),
                    color: const Color(0xFF388E3C),
                    bgColor: const Color(0xFFE8F5E9),
                    icon: null,
                    message:
                        'Waiting for personnel to scan QR on the PedalHub app…',
                  ),
          ),
          const SizedBox(height: 24),

          // Assigned bike banner
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF388E3C).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF388E3C).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.pedal_bike_rounded,
                  color: Color(0xFF388E3C), size: 18),
              const SizedBox(width: 10),
              Text(
                'Keeping: Bike #$_bikeNumber',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF388E3C)),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final glowColor = _isReleased
                  ? const Color(0xFF388E3C)
                  : const Color(0xFF388E3C);
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: glowColor.withOpacity(
                          _isReleased ? 1.0 : _pulseAnimation.value),
                      width: _isReleased ? 3 : 2),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.2 *
                          (_isReleased ? 1 : _pulseAnimation.value)),
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
                          color: Color(0xFF388E3C)),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A1A1A)),
                    ),
                    if (_isReleased)
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Center(
                          child: Icon(Icons.check_circle_rounded,
                              color: Color(0xFF388E3C), size: 80),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFF388E3C).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF388E3C).withOpacity(0.3))),
            child: Text(
              _qrData,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Color(0xFF388E3C)),
            ),
          ),
          const SizedBox(height: 20),
          if (!_isReleased)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Personnel completes on their phone:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 10),
                  _stepRow('1', 'Scan QR code'),
                  _stepRow('2', 'Face verification'),
                  _stepRow('3', 'Confirm → status = active_renewal'),
                ],
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
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _stepRow(String number, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: const Color(0xFF388E3C),
                borderRadius: BorderRadius.circular(99)),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_showingQr && _isReleased) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF388E3C),
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

    if (_showingQr && !_isReleased) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('QR is active — waiting for personnel…',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: Colors.grey[600])),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _canGenerateQr
                ? const Color(0xFF388E3C)
                : Colors.grey[300],
            foregroundColor:
                _canGenerateQr ? Colors.white : Colors.grey[500],
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: _canGenerateQr ? 2 : 0,
          ),
          onPressed: _isSubmitting || !_canGenerateQr ? null : _generateQr,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.qr_code_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'Uploading…' : 'Generate QR Code',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}