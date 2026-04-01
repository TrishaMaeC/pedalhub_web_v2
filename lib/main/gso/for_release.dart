import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/models/borrowing_application.dart';
import 'package:pedalhub_admin/widgets/rejection_reason_dialog.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:qr_flutter/qr_flutter.dart';

class ForReleasePage extends StatefulWidget {
  const ForReleasePage({super.key});

  @override
  State<ForReleasePage> createState() => _ForReleasePageState();
}

class _ForReleasePageState extends State<ForReleasePage> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String selectedTab = 'new';
  String selectedNewStatus = 'for_release';
  String selectedRenewalStatus = 'renewal_medical_approved';
  String selectedShortTermStatus = 'pending';

  List<BorrowingApplicationV2Model> newApplications = [];
  List<Map<String, dynamic>> renewalApplications = [];
  List<Map<String, dynamic>> shortTermRequests = [];

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
        _fetchNewApplications(),
        _fetchRenewalApplications(),
        if (_isShortTermEnabled) _fetchShortTermRequests(),
      ]);
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchNewApplications() async {
    if (userCampus == null) return;
    try {
      final response = await supabase
          .from('borrowing_applications_version2')
          .select('*')
          .eq('status', selectedNewStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);
      setState(() {
        newApplications =
            response.map((e) => BorrowingApplicationV2Model.fromJson(e)).toList();
      });
    } catch (e) {
      debugPrint('Fetch new error: $e');
    }
  }

  Future<void> _fetchRenewalApplications() async {
    if (userCampus == null) return;
    try {
      final response = await supabase
          .from('renewal_applications')
          .select('*')
          .eq('status', selectedRenewalStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);
      setState(() {
        renewalApplications = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Fetch renewal error: $e');
    }
  }

  Future<void> _fetchShortTermRequests() async {
    if (userCampus == null) return;
    try {
      final response = await supabase
          .from('short_term_borrowing_requests')
          .select('*')
          .eq('status', selectedShortTermStatus)
          .ilike('campus', userCampus!)
          .order('created_at', ascending: false);
      setState(() {
        shortTermRequests = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Fetch short term error: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchBikeInfo(int? sessionId) async {
    if (sessionId == null) return null;
    try {
      final session = await supabase
          .from('borrowing_sessions')
          .select('bike_id')
          .eq('id', sessionId)
          .maybeSingle();
      if (session == null || session['bike_id'] == null) return null;
      return await supabase
          .from('bikes')
          .select('*')
          .eq('id', session['bike_id'])
          .maybeSingle();
    } catch (e) {
      debugPrint('Fetch bike error: $e');
      return null;
    }
  }

  void _showReleaseDialog(BorrowingApplicationV2Model app) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReleaseDialog(
        applicationId: app.id.toString(),
        applicantName: '${app.firstName} ${app.lastName}',
        bikeNumber: app.assignedBikeNumber ?? 'N/A',
        applicationType: 'new',
        bikeInfo: null,
        userCampus: userCampus,
        onApproved: () async {
          await _fetchNewApplications();
          setState(() {});
        },
        onRejected: () async {
          await _fetchNewApplications();
          setState(() {});
        },
      ),
    );
  }

  void _showBikeConditionDialog(Map<String, dynamic> app) async {
    final sessionId = app['session_id'] != null
        ? int.tryParse(app['session_id'].toString())
        : null;
    final bikeInfo = await _fetchBikeInfo(sessionId);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReleaseDialog(
        applicationId: app['id'].toString(),
        applicantName:
            '${app['first_name'] ?? ''} ${app['last_name'] ?? ''}'.trim(),
        bikeNumber: app['bike_number'] ?? 'N/A',
        applicationType: 'renewal',
        bikeInfo: bikeInfo,
        userCampus: userCampus,
        onApproved: () async {
          await _fetchRenewalApplications();
          setState(() {});
        },
        onRejected: () async {
          await _fetchRenewalApplications();
          setState(() {});
        },
      ),
    );
  }

  void _showShortTermReleaseDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReleaseDialog(
        applicationId: request['id'].toString(),
        applicantName: request['full_name'] ?? 'Unknown',
        bikeNumber: 'TBD',
        applicationType: 'short_term',
        bikeInfo: null,
        userCampus: userCampus,
        shortTermRequest: request,
        onApproved: () async {
          await _fetchShortTermRequests();
          setState(() {});
        },
        onRejected: () async {
          await _fetchShortTermRequests();
          setState(() {});
        },
      ),
    );
  }

  void _showShortTermDeclineDialog(Map<String, dynamic> request) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decline short-term request from ${request['full_name'] ?? 'this user'}?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection (optional)',
                border: OutlineInputBorder(),
                hintText: 'Enter reason...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await supabase
                    .from('short_term_borrowing_requests')
                    .update({
                      'status': 'rejected',
                      'rejection_reason': reasonController.text.trim(),
                      'reviewed_by': supabase.auth.currentUser?.id,
                      'reviewed_at': DateTime.now().toIso8601String(),
                      'updated_at': DateTime.now().toIso8601String(),
                    })
                    .eq('id', request['id']);
                await _fetchShortTermRequests();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Request declined.'),
                      backgroundColor: Colors.orange,
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
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  void _showShortTermDetails(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Request Details',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (request['profile_pic_url'] != null &&
                          request['profile_pic_url']
                              .toString()
                              .isNotEmpty) ...[
                        Center(
                          child: CircleAvatar(
                            radius: 40,
                            backgroundImage:
                                NetworkImage(request['profile_pic_url']),
                            onBackgroundImageError: (_, __) {},
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _detailRow(
                          'Full Name', request['full_name'] ?? 'N/A'),
                      _detailRow('User Type',
                          (request['user_type'] ?? 'N/A').toUpperCase()),
                      if (request['user_type'] == 'student')
                        _detailRow(
                            'SR Code', request['sr_code'] ?? 'N/A'),
                      if (request['user_type'] == 'staff')
                        _detailRow('Employee No.',
                            request['employee_no'] ?? 'N/A'),
                      _detailRow(
                          'Phone', request['phone_number'] ?? 'N/A'),
                      _detailRow('Campus',
                          (request['campus'] ?? 'N/A').toUpperCase()),
                      const Divider(height: 24),
                      _detailRow('Destination',
                          request['destination_name'] ?? 'N/A'),
                      _detailRow('Address',
                          request['destination_address'] ?? 'N/A'),
                      _detailRow('Duration',
                          '${request['selected_duration_minutes']} minutes'),
                      _detailRow('Purpose',
                          request['borrowing_description'] ?? 'N/A'),
                      _detailRow(
                          'Status',
                          (request['status'] ?? '')
                              .toUpperCase()
                              .replaceAll('_', ' ')),
                      if (request['assigned_bike_number'] != null)
                        _detailRow('Assigned Bike',
                            'Bike #${request['assigned_bike_number']}'),
                      if (request['gso_officer_name'] != null)
                        _detailRow(
                            'GSO Officer', request['gso_officer_name']),
                      if (request['rejection_reason'] != null &&
                          request['rejection_reason']
                              .toString()
                              .isNotEmpty)
                        _detailRow('Rejection Reason',
                            request['rejection_reason']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void openPdf(String? url) {
    if (url != null && url.isNotEmpty) {
      html.window.open(url, '_blank');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No PDF available'),
            backgroundColor: Colors.orange),
      );
    }
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
                          if (selectedTab != 'bulk') ...[
                            _buildStatusFilter(),
                            const SizedBox(height: 24),
                          ],
                          if (selectedTab == 'new')
                            _buildNewApplicationsList()
                          else if (selectedTab == 'renewal')
                            _buildRenewalApplicationsList()
                          else if (selectedTab == 'short_term')
                            _buildShortTermList()
                          else if (selectedTab == 'bulk')
                            _BulkReleaseSection(
                              userCampus: userCampus,
                              supabase: supabase,
                            ),
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
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.pedal_bike_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GSO Supply Release',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Manage bike releases'
                      : 'Manage bike releases',
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
          _mainToggleBtn(
              'new', 'New Applications', Icons.fiber_new_rounded, null),
          _mainToggleBtn('renewal', 'Renewal Applications',
              Icons.autorenew_rounded, null),
          if (_isShortTermEnabled)
            _mainToggleBtn('short_term', 'Short Term',
                Icons.access_time_rounded, const Color(0xFFF57C00)),
          if (_isShortTermEnabled)
            _mainToggleBtn('bulk', 'Bulk Release',
                Icons.electric_bike_rounded, const Color(0xFF388E3C)),
        ],
      ),
    );
  }

  Widget _mainToggleBtn(
      String value, String label, IconData icon, Color? activeColor) {
    final isSelected = selectedTab == value;
    final color = activeColor ?? const Color(0xFF1565C0);
    return GestureDetector(
      onTap: () => setState(() => selectedTab = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    color:
                        isSelected ? Colors.white : Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilter() {
    if (selectedTab == 'new') {
      return Row(children: [
        _statusChip(
            value: 'for_release',
            label: 'Pending Release',
            icon: Icons.inventory_rounded,
            color: const Color(0xFFF57C00),
            isNew: true),
        const SizedBox(width: 12),
        _statusChip(
            value: 'active',
            label: 'Released',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF388E3C),
            isNew: true),
      ]);
    } else if (selectedTab == 'renewal') {
      return Row(children: [
        _statusChip(
            value: 'renewal_chancellor',
            label: 'Pending Release',
            icon: Icons.inventory_rounded,
            color: const Color(0xFFF57C00),
            isNew: false),
        const SizedBox(width: 12),
        _statusChip(
            value: 'renewal_gso',
            label: 'Released',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF388E3C),
            isNew: false),
        const SizedBox(width: 12),
        _statusChip(
            value: 'renewal_gso_rejected',
            label: 'Rejected',
            icon: Icons.cancel_rounded,
            color: const Color(0xFFD32F2F),
            isNew: false),
      ]);
    } else if (selectedTab == 'short_term') {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _shortTermStatusChip('pending', 'Pending',
              Icons.hourglass_top_rounded, const Color(0xFFF57C00)),
          const SizedBox(width: 12),
          _shortTermStatusChip('approved', 'Approved',
              Icons.check_circle_rounded, const Color(0xFF388E3C)),
          const SizedBox(width: 12),
          _shortTermStatusChip('active', 'Active',
              Icons.directions_bike_rounded, const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _shortTermStatusChip('completed', 'Completed',
              Icons.task_alt_rounded, Colors.teal),
          const SizedBox(width: 12),
          _shortTermStatusChip('overdue', 'Overdue',
              Icons.warning_amber_rounded, Colors.deepOrange),
          const SizedBox(width: 12),
          _shortTermStatusChip('rejected', 'Rejected',
              Icons.cancel_rounded, const Color(0xFFD32F2F)),
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
        _fetchShortTermRequests();
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
        if (isNew) _fetchNewApplications();
        else _fetchRenewalApplications();
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

  Widget _buildNewApplicationsList() {
    if (newApplications.isEmpty) {
      return _emptyState(selectedNewStatus == 'for_release'
          ? 'No pending releases'
          : 'No released applications');
    }
    return Column(
        children: newApplications
            .map((app) => _newApplicationCard(app))
            .toList());
  }

  Widget _newApplicationCard(BorrowingApplicationV2Model app) {
    final isPending = app.status == 'for_release';
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
          color: isPending
              ? const Color(0xFFF57C00).withOpacity(0.2)
              : const Color(0xFF388E3C).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isPending
                  ? const Color(0xFFF57C00).withOpacity(0.1)
                  : const Color(0xFF388E3C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isPending
                  ? Icons.inventory_rounded
                  : Icons.check_circle_rounded,
              color: isPending
                  ? const Color(0xFFF57C00)
                  : const Color(0xFF388E3C),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('${app.firstName} ${app.lastName}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 8),
                  _badge('New', const Color(0xFF1565C0)),
                ]),
                const SizedBox(height: 4),
                Text(
                app.userType == 'student'
                    ? 'SR Code: ${app.idNo ?? "N/A"}'
                    : 'Employee No: ${app.idNo ?? "N/A"}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
                const SizedBox(height: 2),
                Text('Control No: ${app.controlNumber ?? "Pending"}',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[500])),
                const SizedBox(height: 10),
                _statusBadge(
                  isPending ? 'Pending Release' : 'Released',
                  isPending
                      ? const Color(0xFFF57C00)
                      : const Color(0xFF388E3C),
                ),
              ],
            ),
          ),
          if (isPending)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF388E3C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showReleaseDialog(app),
              icon: const Icon(Icons.check_box_rounded, size: 18),
              label: const Text('Mark as Released',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildRenewalApplicationsList() {
    if (renewalApplications.isEmpty) {
      return _emptyState(
        selectedRenewalStatus == 'renewal_chancellor'
            ? 'No pending renewal releases'
            : selectedRenewalStatus == 'renewal_gso'
                ? 'No released renewals'
                : 'No rejected renewals',
      );
    }
    return Column(
        children: renewalApplications
            .map((app) => _renewalApplicationCard(app))
            .toList());
  }

  Widget _renewalApplicationCard(Map<String, dynamic> app) {
    final firstName = app['first_name'] ?? '';
    final lastName = app['last_name'] ?? '';
    final idNumber = app['id_number'] ?? 'N/A';
    final bikeNumber = app['bike_number'] ?? 'N/A';
    final status = app['status'] ?? '';
    final isPending = status == 'renewal_chancellor';
    final isApproved = status == 'renewal_gso';
    final Color statusColor = isPending
        ? const Color(0xFFF57C00)
        : isApproved
            ? const Color(0xFF388E3C)
            : const Color(0xFFD32F2F);
    final String statusLabel = isPending
        ? 'Pending Release'
        : isApproved
            ? 'Released'
            : 'Rejected';

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
                borderRadius: BorderRadius.circular(14)),
            child: Icon(
              isPending
                  ? Icons.inventory_rounded
                  : isApproved
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
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
                  _badge('Renewal', const Color(0xFF7B1FA2)),
                ]),
                const SizedBox(height: 4),
                Text('ID: $idNumber',
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
                ]),
                const SizedBox(height: 10),
                _statusBadge(statusLabel, statusColor),
              ],
            ),
          ),
          if (isPending)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showBikeConditionDialog(app),
              icon: const Icon(Icons.bike_scooter_rounded, size: 18),
              label: const Text('Check Bike & Release',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildShortTermList() {
    if (shortTermRequests.isEmpty) {
      return _emptyState(
          'No $selectedShortTermStatus short-term requests');
    }
    return Column(
      children:
          shortTermRequests.map((req) => _shortTermCard(req)).toList(),
    );
  }

  Widget _shortTermCard(Map<String, dynamic> request) {
    final fullName = request['full_name'] ?? 'Unknown';
    final userType = request['user_type'] ?? '';
    final status = request['status'] as String? ?? '';
    final isPending = status == 'pending';

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'pending':
        statusColor = const Color(0xFFF57C00);
        statusLabel = 'Pending';
        break;
      case 'approved':
        statusColor = const Color(0xFF388E3C);
        statusLabel = 'Approved';
        break;
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
      case 'rejected':
        statusColor = const Color(0xFFD32F2F);
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = status.toUpperCase();
    }

    String getInitials(String name) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2)
        return parts[0][0] + parts[parts.length - 1][0];
      if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0];
      return 'U';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
              child: request['profile_pic_url'] != null &&
                      request['profile_pic_url'].toString().isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        request['profile_pic_url'],
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
                          ? 'SR: ${request['sr_code'] ?? 'N/A'}'
                          : 'Emp: ${request['employee_no'] ?? 'N/A'}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_rounded,
                        size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        request['destination_name'] ?? 'N/A',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.timer_rounded,
                        size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${request['selected_duration_minutes']} minutes',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _statusBadge(statusLabel, statusColor),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isPending) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () =>
                        _showShortTermReleaseDialog(request),
                    icon: const Icon(Icons.qr_code_rounded, size: 16),
                    label: const Text('Release',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () =>
                        _showShortTermDeclineDialog(request),
                    icon: const Icon(Icons.cancel_rounded, size: 16),
                    label: const Text('Decline',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showShortTermDetails(request),
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('Details',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
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
// BULK RELEASE SECTION
// ═══════════════════════════════════════════════════════════════════
class _BulkReleaseSection extends StatefulWidget {
  final String? userCampus;
  final SupabaseClient supabase;

  const _BulkReleaseSection({
    required this.userCampus,
    required this.supabase,
  });

  @override
  State<_BulkReleaseSection> createState() => _BulkReleaseSectionState();
}

class _BulkReleaseSectionState extends State<_BulkReleaseSection> {
  List<Map<String, dynamic>> _availableBikes = [];
  List<Map<String, dynamic>> _eventBikes = [];
  List<int> _selectedBikeIds = [];
  bool _loadingBikes = false;
  bool _isSubmitting = false;
  bool _isEndingEvent = false;

  final TextEditingController _eventNameController = TextEditingController();
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  bool _isDrawMode = true;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _hasSignature = false;

  bool get _selectAll =>
      _availableBikes.isNotEmpty &&
      _selectedBikeIds.length == _availableBikes.length;

  bool get _canSubmit =>
      _selectedBikeIds.isNotEmpty &&
      _eventNameController.text.trim().isNotEmpty &&
      _hasSignature;

  @override
  void initState() {
    super.initState();
    _loadBikes();
    _signatureController.addListener(() {
      setState(() => _hasSignature =
          _signatureController.isNotEmpty || _uploadedImageBytes != null);
    });
    _eventNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _eventNameController.dispose();
    super.dispose();
  }

  Future<void> _loadBikes() async {
    setState(() => _loadingBikes = true);
    try {
      final available = await widget.supabase
          .from('bikes')
          .select('id, bike_number, campus, status')
          .eq('status', 'available')
          .filter('campus', 'ilike', widget.userCampus ?? '')
          .order('bike_number');

      final eventBikes = await widget.supabase
          .from('bikes')
          .select(
              'id, bike_number, campus, status, event_name, event_released_at')
          .eq('status', 'event_use')
          .filter('campus', 'ilike', widget.userCampus ?? '')
          .order('event_name');

      setState(() {
        _availableBikes = List<Map<String, dynamic>>.from(available);
        _eventBikes = List<Map<String, dynamic>>.from(eventBikes);
        _selectedBikeIds = [];
      });
    } catch (e) {
      debugPrint('Load bikes error: $e');
    } finally {
      setState(() => _loadingBikes = false);
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
      final userId = widget.supabase.auth.currentUser?.id ?? 'unknown';
      final path = 'gso_signatures/${userId}_${timestamp}_$fileName';
      await widget.supabase.storage
          .from('signatures')
          .uploadBinary(path, bytes);
      return widget.supabase.storage
          .from('signatures')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _submitBulkRelease() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      Uint8List? sigBytes;
      String fileName;
      if (_isDrawMode) {
        sigBytes = await _signatureController.toPngBytes();
        if (sigBytes == null) throw Exception('Failed to export signature');
        fileName = 'bulk_event_signature.png';
      } else {
        sigBytes = _uploadedImageBytes!;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      final signatureUrl = await _uploadSignature(sigBytes, fileName);
      if (signatureUrl == null) throw Exception('Signature upload failed');

      final now = DateTime.now().toUtc().toIso8601String();
      final currentUserId = widget.supabase.auth.currentUser?.id;
      final eventName = _eventNameController.text.trim();

      await widget.supabase.from('bikes').update({
        'status': 'event_use',
        'event_name': eventName,
        'event_signature_url': signatureUrl,
        'event_released_by': currentUserId,
        'event_released_at': now,
      }).inFilter('id', _selectedBikeIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedBikeIds.length} bike${_selectedBikeIds.length > 1 ? 's' : ''} released for "$eventName" successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _signatureController.clear();
      _eventNameController.clear();
      setState(() {
        _uploadedImageBytes = null;
        _hasSignature = false;
        _selectedBikeIds = [];
      });

      await _loadBikes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showEndEventDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.flag_rounded, color: Color(0xFFD32F2F)),
          const SizedBox(width: 8),
          const Text('End Event'),
        ]),
        content: Text(
          'This will return all ${_eventBikes.length} bike${_eventBikes.length > 1 ? 's' : ''} currently on event use back to available.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _endEvent();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            child: const Text('End Event'),
          ),
        ],
      ),
    );
  }

  Future<void> _endEvent() async {
    setState(() => _isEndingEvent = true);
    try {
      final allEventBikeIds =
          _eventBikes.map((b) => b['id'] as int).toList();
      await widget.supabase.from('bikes').update({
        'status': 'available',
        'event_name': null,
        'event_signature_url': null,
        'event_released_by': null,
        'event_released_at': null,
      }).inFilter('id', allEventBikeIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${allEventBikeIds.length} bike${allEventBikeIds.length > 1 ? 's' : ''} returned successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadBikes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isEndingEvent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_eventBikes.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFD32F2F).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.electric_bike_rounded,
                    color: Color(0xFFD32F2F), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active Event',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F))),
                      Text(
                        '${_eventBikes.length} bike${_eventBikes.length > 1 ? 's' : ''} currently out for event use.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.red[800]),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _eventBikes
                            .map((b) =>
                                b['event_name'] as String? ?? 'Unknown')
                            .toSet()
                            .map((name) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F)
                                        .withOpacity(0.1),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                        color: const Color(0xFFD32F2F)
                                            .withOpacity(0.4)),
                                  ),
                                  child: Text(name,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFD32F2F))),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed:
                      _isEndingEvent ? null : _showEndEventDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isEndingEvent
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.flag_rounded, size: 18),
                  label: Text(
                    _isEndingEvent ? 'Ending...' : 'End Event',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF388E3C).withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.electric_bike_rounded,
                  color: Color(0xFF388E3C), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bulk Release for Event',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20))),
                    Text(
                      'Select available bikes, enter the event name, and provide your signature.',
                      style: TextStyle(
                          fontSize: 13, color: Colors.green[800]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF388E3C)),
                onPressed: _loadBikes,
                tooltip: 'Refresh bikes',
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Available Bikes (${_availableBikes.length})',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            if (_availableBikes.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_selectAll) {
                      _selectedBikeIds = [];
                    } else {
                      _selectedBikeIds = _availableBikes
                          .map((b) => b['id'] as int)
                          .toList();
                    }
                  });
                },
                icon: Icon(
                  _selectAll
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 18,
                  color: const Color(0xFF388E3C),
                ),
                label: Text(
                  _selectAll ? 'Deselect All' : 'Select All',
                  style: const TextStyle(color: Color(0xFF388E3C)),
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        _loadingBikes
            ? const Center(child: CircularProgressIndicator())
            : _availableBikes.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFD32F2F)
                                .withOpacity(0.3))),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFD32F2F), size: 18),
                      SizedBox(width: 8),
                      Text('No available bikes at your campus.',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFD32F2F))),
                    ]),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _availableBikes.map((bike) {
                      final id = bike['id'] as int;
                      final isSelected = _selectedBikeIds.contains(id);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedBikeIds.remove(id);
                            } else {
                              _selectedBikeIds.add(id);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF388E3C)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF388E3C)
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                        color: const Color(0xFF388E3C)
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.pedal_bike_rounded,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text('Bike #${bike['bike_number']}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A))),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

        if (_selectedBikeIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${_selectedBikeIds.length} bike${_selectedBikeIds.length > 1 ? 's' : ''} selected',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF388E3C)),
          ),
        ],

        const SizedBox(height: 24),

        const Text('Event Name *',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        TextField(
          controller: _eventNameController,
          decoration: InputDecoration(
            hintText: 'e.g. Campus Sports Fest 2025',
            prefixIcon: const Icon(Icons.event_rounded,
                color: Color(0xFF388E3C)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: Color(0xFF388E3C), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
        ),

        const SizedBox(height: 24),

        const Text('GSO Officer Signature *',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 4),
        Text('Draw or upload your signature:',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 12),

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
                              icon: const Icon(Icons.upload_file,
                                  size: 20),
                              label: const Text('Upload Signature'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF388E3C),
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

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _canSubmit ? const Color(0xFF388E3C) : Colors.grey[300],
              foregroundColor:
                  _canSubmit ? Colors.white : Colors.grey[500],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: _canSubmit ? 2 : 0,
            ),
            onPressed:
                _isSubmitting || !_canSubmit ? null : _submitBulkRelease,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.electric_bike_rounded, size: 20),
            label: Text(
              _isSubmitting
                  ? 'Releasing...'
                  : 'Release ${_selectedBikeIds.isEmpty ? '' : '${_selectedBikeIds.length} '}Bike${_selectedBikeIds.length == 1 ? '' : 's'} for Event',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// UNIFIED RELEASE DIALOG
// ═══════════════════════════════════════════════════════════════════
class _ReleaseDialog extends StatefulWidget {
  final String applicationId;
  final String applicantName;
  final String bikeNumber;
  final String applicationType;
  final Map<String, dynamic>? bikeInfo;
  final String? userCampus;
  final Map<String, dynamic>? shortTermRequest;
  final VoidCallback onApproved;
  final VoidCallback onRejected;

  const _ReleaseDialog({
    required this.applicationId,
    required this.applicantName,
    required this.bikeNumber,
    required this.applicationType,
    required this.bikeInfo,
    required this.userCampus,
    this.shortTermRequest,
    required this.onApproved,
    required this.onRejected,
  });

  @override
  State<_ReleaseDialog> createState() => _ReleaseDialogState();
}

class _ReleaseDialogState extends State<_ReleaseDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  bool _isSubmitting = false;
  bool _showingQr = false;
  bool _isReleased = false;

  RealtimeChannel? _channel;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<Map<String, dynamic>> _availableBikes = [];
  Map<String, dynamic>? _selectedBike;
  bool _loadingBikes = false;

  bool _frameOk = true;
  bool _wheelsOk = true;
  bool _brakesOk = true;
  bool _chaingearOk = true;
  bool _saddleOk = true;
  bool _lightsOk = true;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  bool _isDrawMode = true;
  bool _hasSignature = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  final TextEditingController _officerNameController =
      TextEditingController();

  bool get _isRenewal => widget.applicationType == 'renewal';
  bool get _isShortTerm => widget.applicationType == 'short_term';

  String get _qrData => _isShortTerm
      ? 'SHORT-${widget.applicationId}'
      : '${_isRenewal ? 'RENEWAL' : 'NEW'}-${widget.applicationId}';

  String get _tableName => _isRenewal
      ? 'renewal_applications'
      : _isShortTerm
          ? 'short_term_borrowing_requests'
          : 'borrowing_applications_version2';

  // ← FIXED: polling waits for 'active' (set by app after QR scan)
  String get _releasedStatus => _isShortTerm
      ? 'active'
      : _isRenewal
          ? 'active_renewal'
          : 'active';

  bool get _allConditionsOk =>
      _frameOk &&
      _wheelsOk &&
      _brakesOk &&
      _chaingearOk &&
      _saddleOk &&
      _lightsOk;

  bool get _canGenerateQr =>
      _hasSignature &&
      _officerNameController.text.trim().isNotEmpty &&
      (_isRenewal || _selectedBike != null);

  Color get _accentColor => _isShortTerm
      ? const Color(0xFFF57C00)
      : _isRenewal
          ? const Color(0xFF7B1FA2)
          : const Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _loadOfficerName();
    _loadAvailableBikes();

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
        CurvedAnimation(
            parent: _pulseController, curve: Curves.easeInOut));
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

  Future<void> _loadAvailableBikes() async {
    if (_isRenewal) return;
    setState(() => _loadingBikes = true);
    try {
      final response = await supabase
          .from('bikes')
          .select('id, bike_number, campus, status')
          .eq('status', 'available')
          .filter('campus', 'ilike', widget.userCampus ?? '')
          .order('bike_number');
      setState(() {
        _availableBikes = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Load bikes error: $e');
    } finally {
      setState(() => _loadingBikes = false);
    }
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

  Future<String?> _uploadSignature(
      Uint8List bytes, String fileName) async {
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
      final currentUserId = supabase.auth.currentUser?.id;

      if (_isShortTerm) {
        // ── SHORT TERM ────────────────────────────────────────
        // Save GSO details + bike assignment + set to approved
        // Wala pang bike status update or session insert
        // App na bahala sa lahat after QR scan + face recog
        await supabase
            .from('short_term_borrowing_requests')
            .update({
              'gso_officer_name': _officerNameController.text.trim(),
              'gso_signature_url': signatureUrl,
              'reviewed_by': currentUserId,
              'reviewed_at': now,
              'updated_at': now,
              'assigned_bike_id': _selectedBike!['id'],
              'assigned_bike_number': _selectedBike!['bike_number'],
              'status': 'approved',
            })
            .eq('id', int.parse(widget.applicationId));

        // ← NO bike update here
        // ← NO session insert here
        // App will: update bike to in_use, insert session, set status to active
      } else if (_isRenewal) {
        // ── RENEWAL ───────────────────────────────────────────
        await supabase.from('renewal_applications').update({
          'gso_officer_name': _officerNameController.text.trim(),
          'gso_signature_url': signatureUrl,
          'gso_date_signed': now,
        }).eq('id', widget.applicationId);
      } else {
        // ── NEW APPLICATION ───────────────────────────────────
        final application = await supabase
            .from('borrowing_applications_version2')
            .select('user_id')
            .eq('id', widget.applicationId)
            .single();
        final borrowerUserId = application['user_id'];

        await supabase.from('borrowing_applications_version2').update({
          'gso_officer_name': _officerNameController.text.trim(),
          'gso_signature_url': signatureUrl,
          'gso_date_signed': now,
          'assigned_bike_id': _selectedBike!['id'],
          'assigned_bike_number': _selectedBike!['bike_number'],
        }).eq('id', widget.applicationId);

        await supabase.from('bikes').update({
          'status': 'in_use',
          'current_user_id': borrowerUserId,
        }).eq('id', _selectedBike!['id']);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _startRealtimeListener() {
  final channelName =
      'release_${widget.applicationType}_${widget.applicationId}_${DateTime.now().millisecondsSinceEpoch}';
  
  _channel = supabase.channel(channelName,
    opts: const RealtimeChannelConfig(ack: true),
  );
  
  _channel!
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: _tableName,
        callback: (payload) {
          debugPrint('Realtime payload received: ${payload.newRecord}');
          final newStatus = payload.newRecord['status'];
          final recordId = payload.newRecord['id'].toString();
          if (recordId == widget.applicationId &&
              newStatus == _releasedStatus &&
              !_isReleased &&
              mounted) {
            _onReleaseDetected();
          }
        },
      )
      .subscribe((status, [error]) {
        debugPrint('Realtime status: $status, error: $error');
        // If closed unexpectedly, retry after 2 seconds
        if (status == RealtimeSubscribeStatus.closed && !_isReleased) {
          debugPrint('Channel closed unexpectedly, retrying...');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_isReleased) {
              _startRealtimeListener();
            }
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
            .from(_tableName)
            .select('status')
            .eq('id', _isShortTerm
                ? int.parse(widget.applicationId)
                : widget.applicationId)
            .maybeSingle();
        if (row != null &&
            row['status'] == _releasedStatus &&
            mounted) {
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
    widget.onApproved();
  }

  void _reject() {
    Navigator.pop(context);
    if (_isShortTerm) return;
    RejectionReasonDialog.show(
      context: context,
      applicantName: widget.applicantName,
      onReject: (reason) async {
        try {
          final rejectedStatus =
              _isRenewal ? 'renewal_gso_rejected' : 'rejected';
          await supabase.from(_tableName).update({
            'status': rejectedStatus,
            'rejection_reason': reason,
          }).eq('id', widget.applicationId);

          if (!_isRenewal && _selectedBike != null) {
            await supabase
                .from('bikes')
                .update({'status': 'available'})
                .eq('id', _selectedBike!['id']);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${_isRenewal ? 'Renewal' : 'New'} application rejected.'),
                backgroundColor: Colors.orange));
          }
          widget.onRejected();
        } catch (e) {
          debugPrint('Reject error: $e');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
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
              child: _showingQr ? _buildQrView() : _buildFormView(),
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
                : _isShortTerm
                    ? Icons.access_time_rounded
                    : _isRenewal
                        ? Icons.pedal_bike_rounded
                        : Icons.inventory_rounded,
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
                    ? 'Waiting for Borrower'
                    : _isShortTerm
                        ? 'Short Term Release'
                        : _isRenewal
                            ? 'Bike Condition Check'
                            : 'GSO Release',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A)),
              ),
              Text(
                _showingQr
                    ? 'Ask borrower to scan QR with the PedalHub app'
                    : widget.applicantName,
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

  Widget _buildFormView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isShortTerm && widget.shortTermRequest != null) ...[
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
                    const Icon(Icons.access_time_rounded,
                        color: Color(0xFFF57C00), size: 16),
                    const SizedBox(width: 6),
                    const Text('Short Term Request Details',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF57C00),
                            fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  _infoChip(
                      Icons.location_on_rounded,
                      widget.shortTermRequest![
                              'destination_name'] ??
                          'N/A'),
                  const SizedBox(height: 4),
                  _infoChip(
                      Icons.timer_rounded,
                      '${widget.shortTermRequest!['selected_duration_minutes']} minutes'),
                  const SizedBox(height: 4),
                  _infoChip(
                      Icons.notes_rounded,
                      widget.shortTermRequest![
                              'borrowing_description'] ??
                          'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_isRenewal) ...[
            _buildBikeInfoCard(),
            const SizedBox(height: 24),
            const Text('Bike Condition Checklist',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 4),
            Text('Check each component before approving:',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 14),
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFD32F2F)
                            .withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFD32F2F), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'One or more components are in poor condition. Consider rejecting.',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFD32F2F)))),
                ]),
              ),
            ],
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),
          ],

          if (!_isRenewal) ...[
            const Text('Assign Bike *',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 8),
            _loadingBikes
                ? const Center(child: CircularProgressIndicator())
                : _availableBikes.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFD32F2F)
                                    .withOpacity(0.3))),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFD32F2F), size: 18),
                          SizedBox(width: 8),
                          Text('No available bikes at the moment.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFD32F2F))),
                        ]),
                      )
                    : DropdownButtonFormField<Map<String, dynamic>>(
                        value: _selectedBike,
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.pedal_bike_rounded),
                          hintText: 'Select a bike to assign',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        items: _availableBikes.map<DropdownMenuItem<Map<String, dynamic>>>((bike) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: bike,
                            child: Text(
                              'Bike #${bike['bike_number']} — ${bike['campus'] ?? 'N/A'}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setState(() => _selectedBike = val),
                      ),
            const SizedBox(height: 20),
          ],

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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          const Text('GSO Signature *',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Draw or upload your signature:',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                                icon: const Icon(Icons.upload_file,
                                    size: 20),
                                label:
                                    const Text('Upload Signature'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: _accentColor,
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
                  icon: Icon(
                      _isDrawMode ? Icons.upload_file : Icons.edit),
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
          const SizedBox(height: 8),
          Text(
            _isDrawMode
                ? 'Draw your signature in the box above'
                : 'Click "Upload Signature" to choose an image file',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildBikeInfoCard() {
    final bike = widget.bikeInfo;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF1565C0).withOpacity(0.3))),
      child: bike == null
          ? Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text(
                      'No bike linked to this session. Please verify manually.',
                      style:
                          TextStyle(fontWeight: FontWeight.w500))),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.pedal_bike_rounded,
                      color: Color(0xFF1565C0), size: 20),
                  const SizedBox(width: 8),
                  Text('Bike #${bike['bike_number'] ?? 'N/A'}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0))),
                  const SizedBox(width: 12),
                  _bikeBadge(bike['status'] ?? 'N/A'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _bikeInfoChip(Icons.location_on_rounded,
                      bike['campus'] ?? 'N/A'),
                  const SizedBox(width: 12),
                  _bikeInfoChip(
                      Icons.route_rounded,
                      '${bike['total_distance_km']?.toStringAsFixed(1) ?? '0'} km'),
                  const SizedBox(width: 12),
                  _bikeInfoChip(Icons.directions_bike_rounded,
                      '${bike['total_rides'] ?? 0} rides'),
                ]),
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
                    message: _isShortTerm
                        ? 'Borrower scanned QR & completed face verification! Bike is now active.'
                        : 'Borrower completed all steps! Application is now released.',
                  )
                : _statusBanner(
                    key: const ValueKey('waiting'),
                    color: const Color(0xFFF57C00),
                    bgColor: const Color(0xFFFFF8E1),
                    icon: null,
                    message: _isShortTerm
                        ? 'Waiting for borrower to scan QR & complete face verification…'
                        : 'Waiting for borrower to complete Steps 1–3 on the PedalHub app…',
                  ),
          ),
          const SizedBox(height: 28),
          Text(
            _isReleased
                ? '✅  All steps completed!'
                : 'Ask the borrower to scan this QR',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _isReleased
                    ? const Color(0xFF388E3C)
                    : Colors.grey[700]),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final glowColor =
                  _isReleased ? const Color(0xFF388E3C) : _accentColor;
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
                      eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: _accentColor),
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
                  Text(
                    'Borrower will complete on their phone:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 10),
                  if (_isShortTerm) ...[
                    _stepRow('1', 'Scan QR code'),
                    _stepRow('2', 'Face verification'),
                    _stepRow('3',
                        'Confirm → bike activated, status = active'),
                  ] else ...[
                    _stepRow('1',
                        'Signature pad — "Received by" + agreement'),
                    _stepRow('2', 'Face verification (semestral)'),
                    _stepRow('3',
                        'Agreement checkbox + confirm → updates status'),
                  ],
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
          Text('QR is active — waiting for borrower…',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[500])),
          if (!_isShortTerm)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: _reject,
              icon: const Icon(Icons.cancel_rounded, size: 18),
              label: const Text('Reject',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
        if (!_isShortTerm) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: _reject,
            icon: const Icon(Icons.cancel_rounded, size: 18),
            label: const Text('Reject',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _canGenerateQr ? _accentColor : Colors.grey[300],
            foregroundColor:
                _canGenerateQr ? Colors.white : Colors.grey[500],
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: _canGenerateQr ? 2 : 0,
          ),
          onPressed:
              _isSubmitting || !_canGenerateQr ? null : _generateQr,
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

  Widget _conditionCheck(String label, String description, bool value,
      void Function(bool?) onChanged) {
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

  Widget _bikeBadge(String status) {
    final color = status == 'in_use'
        ? const Color(0xFF1565C0)
        : status == 'available'
            ? const Color(0xFF388E3C)
            : status == 'maintenance'
                ? const Color(0xFFD32F2F)
                : Colors.grey;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color)),
      child: Text(status.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  Widget _bikeInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(label,
            style:
                TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }
}