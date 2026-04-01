import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  String selectedRenewalStatus = 'renewal_gso';
  String selectedShortTermStatus = 'active';

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
          .from('borrowing_applications')
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
      final appsResponse = await supabase
          .from('renewal_applications')
          .select('*')
          .eq('status', selectedRenewalStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);

      final apps = List<Map<String, dynamic>>.from(appsResponse);
      final enriched = await Future.wait(apps.map((app) async {
        try {
          final sessionId = app['session_id'];
          if (sessionId == null) return {...app, 'borrowing_sessions': null};
          final sessionRes = await supabase
              .from('borrowing_sessions')
              .select('id, bike_id, start_time, end_time, status')
              .eq('id', sessionId)
              .maybeSingle();
          return {...app, 'borrowing_sessions': sessionRes};
        } catch (_) {
          return {...app, 'borrowing_sessions': null};
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
        : (app['bike_number'] ?? app['bikeNumber'] ?? 'N/A');
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
        onReturned: () async {
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
                const Text('GSO Bike Return',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Process bike returns'
                      : 'Process bike returns',
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
          _mainToggleBtn('renewal', 'Renewal Borrowers',
              Icons.autorenew_rounded, null),
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
      return Row(children: [
        _statusChip(
            value: 'renewal_gso',
            label: 'Active Borrows',
            icon: Icons.pedal_bike_rounded,
            color: const Color(0xFF7B1FA2),
            isNew: false),
        const SizedBox(width: 12),
        _statusChip(
            value: 'ride_completed',
            label: 'Returned',
            icon: Icons.assignment_turned_in_rounded,
            color: const Color(0xFF00695C),
            isNew: false),
      ]);
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
    final isSelected =
        isNew ? selectedNewStatus == value : selectedRenewalStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isNew) selectedNewStatus = value;
          else selectedRenewalStatus = value;
        });
        if (isNew) _fetchNewBorrows();
        else _fetchRenewalBorrows();
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
      return _emptyState(selectedRenewalStatus == 'renewal_gso'
          ? 'No active renewal borrows at the moment'
          : 'No returned renewal bikes yet');
    }
    return Column(
        children: renewalActiveBorrows
            .map((app) => _borrowCard(app, 'renewal'))
            .toList());
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
    final bikeNumber = app['bike_number'] ?? app['bikeNumber'] ?? 'N/A';
    final status = app['status'] ?? '';
    final srCode = app['sr_code'] ?? app['srCode'];
    final employeeNo = app['employee_no'] ?? app['employeeNo'];
    final idNumber = app['id_number'];
    final session = app['borrowing_sessions'];
    final startTime = session?['start_time'];

    final isActive = status == 'active' || status == 'renewal_gso';
    final isReturned = status == 'ride_completed';
    final isNew = type == 'new';

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
                  _badge(
                    isNew ? 'New' : 'Renewal',
                    isNew
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF7B1FA2),
                  ),
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
// RETURN DIALOG
// ═══════════════════════════════════════════════════════════════════
class _ReturnDialog extends StatefulWidget {
  final String applicationId;
  final String? sessionId;
  final String applicantName;
  final String bikeNumber;
  final String applicationType;
  final dynamic startTime;
  final VoidCallback onReturned;

  const _ReturnDialog({
    required this.applicationId,
    required this.sessionId,
    required this.applicantName,
    required this.bikeNumber,
    required this.applicationType,
    required this.startTime,
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

  // ── Short term polls borrowing_sessions for 'completed'
  // ── New/Renewal polls borrowing_sessions for 'ride_completed'
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
        // Always visible close button
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
                    'Status auto-updates to "${_completedStatus}" ✅'),
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