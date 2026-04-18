// lib/pages/health_evaluation_page.dart

// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/health_drawer.dart';
import 'package:pedalhub_admin/models/borrowing_application.dart';
import 'package:pedalhub_admin/widgets/physical_examination_dialog.dart';
import 'package:pedalhub_admin/widgets/med_cert.dart';
import 'package:pedalhub_admin/widgets/reassessment_comparison_dialog.dart';
import 'package:intl/intl.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';

class HealthEvaluationPage extends StatefulWidget {
  const HealthEvaluationPage({super.key});

  @override
  State<HealthEvaluationPage> createState() => _HealthEvaluationPageState();
}

class _HealthEvaluationPageState extends State<HealthEvaluationPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String selectedTab = 'pending';
  String examFilter = 'all';

  // ── Reassessment sub-filter: 'pending' | 'approved' | 'all'
  String reassessmentFilter = 'pending';

  String pendingFilter = 'all';
  List<BorrowingApplicationV2Model> applications = [];
  DateTime selectedAppointmentDate = DateTime.now();
  TimeOfDay clinicEndTime = const TimeOfDay(hour: 23, minute: 0);

  // Counts for badge display
  int _reassessmentPendingCount = 0;
  int _reassessmentApprovedCount = 0;

  // Timer to auto-refresh the pending list every minute
  Timer? _autoRefreshTimer;

  // Logged-in user's campus (fetched from profiles table)
  String? userCampus;

  // ─────────────────────────────────────────────
  // STATUS HELPERS
  // ─────────────────────────────────────────────

  bool _isRenewalStatus(String status) => status.startsWith('renewal_');

  // Statuses shown in the Pending tab.
  static const List<String> _pendingStatuses = [
    'medical_scheduled',
    'renewal_medical_scheduled',
  ];

  // Statuses that feed the Reassessment → Pending sub-filter.
  static const List<String> _reassessmentPendingStatuses = [
    'reassessment_requested',         // new application
    'renewal_medical_reassessment',   // renewal
  ];

  // Statuses that feed the Reassessment → Approved sub-filter.
  static const List<String> _reassessmentApprovedStatuses = [
    'for_reassessment',               // new application approved
    'renewal_for_reassessment',       // renewal approved
  ];

  // History tab pass / fail statuses.
  static const List<String> _historyPassStatuses = [
    'fit_to_use',
    'renewal_medical_approved',
  ];
  static const List<String> _historyFailStatuses = [
    'health_rejected',
    'health_reject_final',
    'renewal_health_rejected_final',
    'renewal_medical_rejected',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserCampusAndInit();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (selectedTab == 'pending' && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // LOAD USER CAMPUS THEN INIT
  // ─────────────────────────────────────────────
  Future<void> _loadUserCampusAndInit() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      checkClinicClosingTime();
      fetchApplications();
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

  Future<void> pickClinicEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: clinicEndTime,
    );
    if (picked != null) setState(() => clinicEndTime = picked);
  }

  // ─────────────────────────────────────────────
  // GET APPOINTMENT DATE-TIME (LOCAL, NOT UTC)
  // ─────────────────────────────────────────────
  Future<DateTime?> getAppointmentDateTime(int applicationId) async {
    final response = await supabase
        .from('medical_appointments_version2')
        .select('appointment_date, appointment_time')
        .eq('application_id', applicationId)
        .order('appointment_date', ascending: false)
        .order('appointment_time', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    final date = DateTime.parse(response['appointment_date'] as String);
    final timeParts = (response['appointment_time'] as String).split(':');

    return DateTime(
      date.year, date.month, date.day,
      int.parse(timeParts[0]), int.parse(timeParts[1]),
    );
  }

  // ─────────────────────────────────────────────
  // CHECK EXAM AVAILABILITY
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>> checkExamAvailability(
      int applicationId, String status) async {
    // Walk-in re-exam after reassessment approval — always allowed during
    // clinic hours; no appointment slot required.
    if (status == 'for_reassessment' || status == 'renewal_for_reassessment') {
      final now = DateTime.now();
      final clinicEnd = DateTime(
        now.year, now.month, now.day,
        clinicEndTime.hour, clinicEndTime.minute,
      );
      return {
        "allowed": now.isBefore(clinicEnd),
        "availableAt": null,
        "walkIn": true,
      };
    }

    final appt = await getAppointmentDateTime(applicationId);
    if (appt == null) {
      return {"allowed": false, "availableAt": null, "walkIn": false};
    }

    final now = DateTime.now();
    final availableTime = appt.subtract(const Duration(minutes: 30));
    final clinicEnd = DateTime(
      now.year, now.month, now.day,
      clinicEndTime.hour, clinicEndTime.minute,
    );

    final bool allowed =
        now.isAfter(availableTime) && now.isBefore(clinicEnd);

    debugPrint(
        '[ExamAvail] appId=$applicationId | now=$now | availableAt=$availableTime | clinicEnd=$clinicEnd | allowed=$allowed');

    return {
      "allowed": allowed,
      "availableAt": availableTime,
      "walkIn": false,
    };
  }

  Widget _smallFilterButton(String value, String label) {
    final isSelected = pendingFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () {
          setState(() => pendingFilter = value);
          fetchApplications();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange : Colors.grey[300],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? Colors.orange : Colors.grey),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> checkClinicClosingTime() async {
    final today = DateTime.now();
    final todayString =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final response = await supabase
        .from('clinic_settings')
        .select()
        .eq('date', todayString)
        .maybeSingle();

    if (response == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showClosingTimeModal(todayString);
      });
    } else {
      final timeParts = (response['closing_time'] as String).split(':');
      setState(() {
        clinicEndTime = TimeOfDay(
          hour: int.parse(timeParts[0]),
          minute: int.parse(timeParts[1]),
        );
      });
    }
  }

  void _showClosingTimeModal(String todayString) {
    TimeOfDay selectedTime = clinicEndTime;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Set Clinic Closing Time",
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      "Please select today's clinic closing time.\n"
                      "This will apply to all examinations for the day.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setModalState(() => selectedTime = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue),
                          ),
                          child: Text(
                            selectedTime.format(context),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          onPressed: () async {
                            await supabase.from('clinic_settings').insert({
                              "date": todayString,
                              "closing_time":
                                  "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00"
                            });
                            setState(() => clinicEndTime = selectedTime);
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Save Closing Time",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // SHOW PAST EXAM RESULTS (for renewal pending cards)
  // ─────────────────────────────────────────────
  Future<void> _showPastExamResultsAndProceed(
      BorrowingApplicationV2Model app) async {
    List<dynamic> examHistory = [];
    try {
      examHistory = await supabase
          .from('physical_examinations')
          .select('*')
          .eq('application_id', app.id)
          .order('examination_date', ascending: false);
    } catch (e) {
      debugPrint('Error fetching past exams: $e');
    }

    if (!mounted) return;

    if (examHistory.isEmpty) {
      _showExaminationDialog(app);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 680,
          constraints: const BoxConstraints(maxHeight: 620),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Past Examination Results',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${app.firstName} ${app.lastName}',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.purple),
                        ),
                        child: const Text(
                          'RENEWAL',
                          style: TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: examHistory.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final exam = entry.value as Map<String, dynamic>;
                      return _buildPastExamCard(exam, isLatest: idx == 0);
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showExaminationDialog(app);
                    },
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text(
                      'Proceed to Examination',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPastExamCard(Map<String, dynamic> exam,
      {bool isLatest = false}) {
    final examDate =
        exam['examination_date']?.toString().split('T')[0] ?? 'N/A';
    final bmi = exam['bmi'] != null
        ? (exam['bmi'] as num).toStringAsFixed(1)
        : 'N/A';
    final bmiCategory = exam['bmi_category'] ?? 'N/A';
    final bp = exam['blood_pressure'] ?? 'N/A';
    final hr =
        exam['heart_rate'] != null ? '${exam['heart_rate']} bpm' : 'N/A';
    final physician = exam['physician_name'] ?? 'N/A';
    final remarks = exam['remarks'] ?? '';

    final List<String> failed = [];
    final checkFields = {
      'balance': 'Balance',
      'musculoskeletal': 'Musculo-Skeletal',
      'lungs': 'Lungs',
      'heart': 'Heart',
      'extremities': 'Extremities',
      'hearing': 'Hearing',
      'vision': 'Vision',
    };
    for (final entry in checkFields.entries) {
      if (exam[entry.key] == false) failed.add(entry.value);
    }
    final passed = failed.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLatest
            ? (passed ? Colors.green[50] : Colors.red[50])
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLatest
              ? (passed ? Colors.green : Colors.red)
              : Colors.grey[300]!,
          width: isLatest ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    passed ? Icons.check_circle : Icons.cancel,
                    color: passed ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    passed ? 'Fit to Use' : 'Not Fit to Use',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          passed ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                  if (isLatest) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LATEST',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                examDate,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _miniDetail('BMI', '$bmi ($bmiCategory)'),
              _miniDetail('BP', bp),
              _miniDetail('HR', hr),
              _miniDetail('Physician', physician),
            ],
          ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Failed: ${failed.join(', ')}',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.w600),
            ),
          ],
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Remarks: $remarks',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniDetail(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black54),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHOW EXAMINATION DIALOG
  // ─────────────────────────────────────────────
  void _showExaminationDialog(BorrowingApplicationV2Model app,
      {bool isReassessment = false}) {
    final isRenewal = _isRenewalStatus(app.status);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhysicalExaminationDialog(
        applicationId: app.id,
        studentName: '${app.firstName} ${app.lastName}',
        isReassessment: isReassessment,
        isRenewal: isRenewal,
        onCompleted: fetchApplications,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHOW REASSESSMENT DETAILS MODAL
  // Displays borrower info + ALL past examination records.
  // ─────────────────────────────────────────────
  Future<void> _showReassessmentDetailsModal(
      BorrowingApplicationV2Model app) async {
    List<dynamic> examHistory = [];
    try {
      examHistory = await supabase
          .from('physical_examinations')
          .select('*')
          .eq('application_id', app.id)
          .order('examination_date', ascending: false);
    } catch (e) {
      debugPrint('Error fetching exam history: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 720),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reassessment Request Details',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${app.firstName} ${app.lastName}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_isRenewalStatus(app.status))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.purple),
                          ),
                          child: const Text(
                            'RENEWAL',
                            style: TextStyle(
                                color: Colors.purple,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Borrower details ──
                      const Text(
                        'Borrower Information',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow('Full Name',
                          '${app.firstName} ${app.lastName}'),
                      _buildDetailRow('ID No', app.idNo ?? 'N/A'),
                      _buildDetailRow(
                          'Control No', app.controlNumber ?? 'Pending'),
                      _buildDetailRow('Gender', app.sex ?? 'N/A'),
                      _buildDetailRow(
                          'Date of Birth',
                          DateFormat('yyyy-MM-dd')
                              .format(app.dateOfBirth)),
                      _buildDetailRow(
                          'Phone', app.phoneNumber ?? 'N/A'),
                      _buildDetailRow('Address', app.presentAddress),
                      _buildDetailRow(
                          'Current Status', app.getStatusText()),
                      if (app.renewalReassessmentRequestedAt != null)
                        _buildDetailRow(
                          'Requested At',
                          DateFormat('yyyy-MM-dd HH:mm').format(
                              app.renewalReassessmentRequestedAt!),
                        ),
                      // ── Past exam results ──
                      if (examHistory.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.history,
                                color: Colors.deepPurple, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'Past Examination Records (${examHistory.length})',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...examHistory.asMap().entries.map((entry) =>
                            _buildPastExamCard(
                              entry.value as Map<String, dynamic>,
                              isLatest: entry.key == 0,
                            )),
                      ] else ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'No past examination records found.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // ─────────────────────────────────────────────
  // REASSESSMENT APPROVE / REJECT with confirmation
  //
  // NEW APPLICATION:
  //   Approve → 'for_reassessment'
  //   Reject  → 'health_rejected_final'
  //
  // RENEWAL:
  //   Approve → 'renewal_for_reassessment'
  //   Reject  → 'renewal_health_rejected_final'
  // ─────────────────────────────────────────────
  Future<void> _handleReassessmentDecision(
      BorrowingApplicationV2Model app, bool approve) async {
    final isRenewal = app.status == 'renewal_medical_reassessment';

    // ── Confirmation dialog ──
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve
            ? 'Approve Reassessment'
            : 'Reject Reassessment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'Are you sure you want to approve the reassessment request for ${app.firstName} ${app.lastName}?'
                  : 'Are you sure you want to reject the reassessment request for ${app.firstName} ${app.lastName}? This is a permanent decision.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: approve
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: approve ? Colors.green : Colors.red),
              ),
              child: Row(
                children: [
                  Icon(
                    approve ? Icons.check_circle : Icons.warning,
                    color: approve ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      approve
                          ? 'Status will change to: ${isRenewal ? 'Renewal For Reassessment' : 'For Reassessment'}\nThe borrower will be scheduled for a re-examination.'
                          : 'Status will change to: ${isRenewal ? 'Renewal Health Rejected (Final)' : 'Health Rejected (Final)'}\nThis action cannot be undone.',
                      style: TextStyle(
                        fontSize: 12,
                        color: approve
                            ? Colors.green[800]
                            : Colors.red[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (isRenewal) {
        final newStatus = approve
            ? 'renewal_for_reassessment'
            : 'renewal_health_rejected_final';

        await supabase.from('borrowing_applications_version2').update({
          "renewal_reassessment_reviewed_at":
              DateTime.now().toIso8601String(),
          "renewal_reassessment_approved": approve,
          "status": newStatus,
        }).eq("id", app.id);
      } else {
        // new application reassessment
        final newStatus =
            approve ? 'for_reassessment' : 'health_rejected_final';

        await supabase.from('borrowing_applications_version2').update({
          "reassessment_reviewed_at": DateTime.now().toIso8601String(),
          "reassessment_approved": approve,
          "status": newStatus,
        }).eq("id", app.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'Reassessment approved ✓ — borrower may now proceed to re-examination.'
                : 'Reassessment rejected.'),
            backgroundColor: approve ? Colors.green : Colors.red,
          ),
        );
      }

      fetchApplications();
    } catch (e) {
      debugPrint('ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // FETCH APPLICATIONS
  // ─────────────────────────────────────────────
  Future<void> fetchApplications() async {
  if (userCampus == null) return;

  setState(() => isLoading = true);

  try {
    List<dynamic> response = [];

    // =============================
    // PENDING TAB
    // =============================
    if (selectedTab == 'pending') {
      final dateString =
          '${selectedAppointmentDate.year.toString().padLeft(4, '0')}-'
          '${selectedAppointmentDate.month.toString().padLeft(2, '0')}-'
          '${selectedAppointmentDate.day.toString().padLeft(2, '0')}';

      List<dynamic> newApps = [];
      List<dynamic> renewalApps = [];
      List<dynamic> walkInApps = [];

      if (pendingFilter == 'all' || pendingFilter == 'new') {
        newApps = await supabase
            .from('borrowing_applications_version2')
            .select('*, medical_appointments_version2!left(appointment_date, appointment_time, status)')
            .eq('status', 'medical_scheduled')
            .ilike('campus', userCampus!)
            .order('appointment_date', referencedTable: 'medical_appointments_version2', ascending: false);
        for (var app in newApps) app['_isRenewal'] = false;
      }

      if (pendingFilter == 'all' || pendingFilter == 'renewal') {
        renewalApps = await supabase
            .from('borrowing_applications_version2')
            .select('*, medical_appointments_version2!left(appointment_date, appointment_time, status)')
            .eq('status', 'renewal_medical_scheduled')
            .ilike('campus', userCampus!)
            .order('appointment_date', referencedTable: 'medical_appointments_version2', ascending: false);
        for (var app in renewalApps) app['_isRenewal'] = true;

        walkInApps = await supabase
            .from('borrowing_applications_version2')
            .select('*')
            .inFilter('status', ['for_reassessment', 'renewal_for_reassessment'])
            .ilike('campus', userCampus!);
        for (var app in walkInApps) {
          app['_isRenewal'] = _isRenewalStatus(app['status'] as String);
          app['_isWalkIn'] = true;
        }
      }

      final scheduled = [...newApps, ...renewalApps].where((app) {
        try {
          final appointments = app['medical_appointments_version2'];
          List apptList = (appointments is List) ? appointments : (appointments != null ? [appointments] : []);
          if (apptList.isEmpty) return false;
          return (apptList.first['appointment_date'] ?? '') == dateString;
        } catch (e) {
          return false;
        }
      }).toList();

      response = [...scheduled, ...walkInApps];
      // ... (Keep your existing sorting logic here)
    }

    // =============================
    // REASSESSMENT TAB (Optimized)
    // =============================
    else if (selectedTab == 'reassessment') {
      // 1. Fetch all reassessment-related records in ONE call
      final allReassessments = await supabase
          .from('borrowing_applications_version2')
          .select('*')
          .inFilter('status', [
            'reassessment_requested',
            'renewal_medical_reassessment',
            'for_reassessment',
            'renewal_for_reassessment'
          ])
          .ilike('campus', userCampus!);

      // 2. Calculate badge counts locally (Much faster)
      _reassessmentPendingCount = allReassessments.where((e) => 
          e['status'] == 'reassessment_requested' || 
          e['status'] == 'renewal_medical_reassessment').length;
      
      _reassessmentApprovedCount = allReassessments.where((e) => 
          e['status'] == 'for_reassessment' || 
          e['status'] == 'renewal_for_reassessment').length;

      // 3. Filter the response based on the active sub-filter
      if (reassessmentFilter == 'pending') {
        response = allReassessments.where((e) => 
            e['status'] == 'reassessment_requested' || 
            e['status'] == 'renewal_medical_reassessment').toList();
      } else if (reassessmentFilter == 'approved') {
        response = allReassessments.where((e) => 
            e['status'] == 'for_reassessment' || 
            e['status'] == 'renewal_for_reassessment').toList();
      } else {
        response = allReassessments;
      }

      for (var app in response) {
        app['_isRenewal'] = _isRenewalStatus(app['status'] as String);
      }
    }

    // =============================
    // HISTORY TAB
    // =============================
    else {
      List<String> targetStatuses = (examFilter == 'pass') 
          ? _historyPassStatuses 
          : (examFilter == 'fail') ? _historyFailStatuses : [..._historyPassStatuses, ..._historyFailStatuses];

      response = await supabase
          .from('borrowing_applications_version2')
          .select('*')
          .inFilter('status', targetStatuses)
          .ilike('campus', userCampus!);

      for (var app in response) {
        app['_isRenewal'] = _isRenewalStatus(app['status'] as String);
      }
    }

    // Final Mapping
    applications = response
        .map((e) => BorrowingApplicationV2Model.fromJson(e))
        .toList();

  } catch (e) {
    debugPrint('FETCH ERROR: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => isLoading = false);
  }
}

  Future<void> _viewReassessmentHistory(
      BorrowingApplicationV2Model app) async {
    try {
      final examHistory = await supabase
          .from('physical_examinations')
          .select('*')
          .eq('application_id', app.id)
          .order('examination_date', ascending: false);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => ReassessmentComparisonDialog(
          studentName: '${app.firstName} ${app.lastName}',
          examinations: examHistory,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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

  Future<void> _generateMedicalCertificate(
    BorrowingApplicationV2Model app,
    Map<String, dynamic> examData,
  ) async {
    try {
      final now = DateTime.now();
      final age = now.year - app.dateOfBirth.year;

      final bool isFailed = [
        'health_rejected',
        'health_rejected_final',
        'renewal_health_rejected_final',
        'renewal_medical_rejected',
      ].contains(app.status);
      String diagnosis = isFailed ? 'Unfit to cycle' : 'Fit to cycle';

      List<String> abnormalFindings = [];
      if (examData['balance'] == false) abnormalFindings.add('Balance');
      if (examData['musculoskeletal'] == false)
        abnormalFindings.add('Musculo-Skeletal');
      if (examData['lungs'] == false) abnormalFindings.add('Lungs');
      if (examData['heart'] == false) abnormalFindings.add('Heart');
      if (examData['extremities'] == false)
        abnormalFindings.add('Extremities');
      if (examData['hearing'] == false) abnormalFindings.add('Hearing');
      if (examData['vision'] == false) abnormalFindings.add('Vision');

      String remarks = examData['remarks'] ?? '';
      if (abnormalFindings.isNotEmpty) {
        remarks =
            'Abnormal findings: ${abnormalFindings.join(', ')}. $remarks';
      }

      final certData = MedicalCertificateData(
        controlNumber: app.controlNumber ?? 'N/A',
        date: DateTime.now(),
        patientName: '${app.firstName} ${app.lastName}',
        age: age.toString(),
        sex: app.sex ?? 'N/A',
        civilStatus: 'Single',
        address: app.presentAddress,
        examDate: DateTime.parse(examData['examination_date']),
        diagnosis: diagnosis,
        remarks: remarks.trim(),
        purpose: 'Bicycle Loan Program',
        doctorName: examData['physician_name'] ?? '',
        licenseNumber: examData['physician_license_number'] ?? '',
      );

      await MedicalCertificateGenerator.previewCertificate(certData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void showApplicationDetails(BorrowingApplicationV2Model app) async {
    Map<String, dynamic>? examData;
    try {
      final response = await supabase
          .from('physical_examinations')
          .select('*')
          .eq('application_id', app.id)
          .order('examination_date', ascending: false)
          .limit(1)
          .maybeSingle();
      examData = response;
    } catch (e) {
      debugPrint('Error fetching exam: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Application Details',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Student Information',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue)),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          'Full Name', '${app.firstName} ${app.lastName}'),
                      _buildDetailRow('ID No', app.idNo ?? 'N/A'),
                      _buildDetailRow(
                          'Control Number', app.controlNumber ?? 'Pending'),
                      _buildDetailRow('Gender', app.sex ?? 'N/A'),
                      _buildDetailRow('Date of Birth',
                          DateFormat('yyyy-MM-dd').format(app.dateOfBirth)),
                      _buildDetailRow(
                          'Phone Number', app.phoneNumber ?? 'N/A'),
                      _buildDetailRow('Address', app.presentAddress),
                      if (app.distanceFromCampus != null)
                        _buildDetailRow(
                            'Distance', app.formattedDistance),
                      _buildDetailRow('Status', app.getStatusText()),
                      if (examData != null) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text('Latest Physical Examination',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.analytics,
                                      color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                      'BMI: ${examData['bmi']?.toStringAsFixed(1) ?? 'N/A'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getBMIColor(examData['bmi']),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      examData['bmi_category'] ?? 'N/A',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                  'Weight: ${examData['weight']} kg | Height: ${examData['height']} cm',
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('Blood Pressure',
                            examData['blood_pressure'] ?? 'N/A'),
                        _buildDetailRow('Heart Rate',
                            '${examData['heart_rate']} bpm'),
                        _buildDetailRow(
                            'Physician', examData['physician_name'] ?? 'N/A'),
                        _buildDetailRow(
                            'Exam Date',
                            examData['examination_date']
                                    ?.toString()
                                    .split('T')[0] ??
                                'N/A'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (examData != null)
                    ElevatedButton.icon(
                      onPressed: () =>
                          _generateMedicalCertificate(app, examData!),
                      icon: const Icon(Icons.medical_information),
                      label: const Text('Certificate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Color _getBMIColor(dynamic bmi) {
    if (bmi == null) return Colors.grey;
    final bmiValue = (bmi as num).toDouble();
    if (bmiValue < 18.5) return Colors.orange;
    if (bmiValue < 25.0) return Colors.green;
    if (bmiValue < 30.0) return Colors.orange;
    return Colors.red;
  }

  Widget tabButton(
      String value, String label, IconData icon, Color color) {
    final isSelected = selectedTab == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? color : Colors.grey[400],
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: isSelected ? 4 : 1,
        ),
        onPressed: () {
          setState(() {
            selectedTab = value;
            examFilter = 'all';
            reassessmentFilter = 'pending';
          });
          fetchApplications();
        },
        icon: Icon(icon),
        label:
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget filterButton(String value, String label, IconData icon,
      Color color, bool isReassessment) {
    final isSelected =
        isReassessment ? reassessmentFilter == value : examFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? color : Colors.grey[300],
          foregroundColor:
              isSelected ? Colors.white : Colors.grey[700],
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          elevation: isSelected ? 3 : 1,
        ),
        onPressed: () {
          setState(() {
            if (isReassessment) {
              reassessmentFilter = value;
            } else {
              examFilter = value;
            }
          });
          fetchApplications();
        },
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // REASSESSMENT FILTER BUTTON WITH BADGE
  // ─────────────────────────────────────────────
  Widget _reassessmentFilterButton(
    String value,
    String label,
    IconData icon,
    Color color,
    int badgeCount,
  ) {
    final isSelected = reassessmentFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? color : Colors.grey[300],
              foregroundColor:
                  isSelected ? Colors.white : Colors.grey[700],
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: isSelected ? 3 : 1,
            ),
            onPressed: () {
              setState(() => reassessmentFilter = value);
              fetchApplications();
            },
            icon: Icon(icon, size: 18),
            label: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                    minWidth: 20, minHeight: 20),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // APPLICATION CARD
  // ─────────────────────────────────────────────
  Widget applicationCard(BorrowingApplicationV2Model app) {
    final isPassed = _historyPassStatuses.contains(app.status);
    final isReassessmentTab = selectedTab == 'reassessment';
    final isRenewal = _isRenewalStatus(app.status);
    final isWalkIn =
        app.status == 'for_reassessment' ||
        app.status == 'renewal_for_reassessment';

    // Determine if this is a pending reassessment (needs approve/reject)
    // or an approved reassessment (ready for re-exam).
    final isReassessmentPending =
        app.status == 'reassessment_requested' ||
        app.status == 'renewal_medical_reassessment';
    final isReassessmentApproved =
        app.status == 'for_reassessment' ||
        app.status == 'renewal_for_reassessment';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ── Avatar icon ──
            CircleAvatar(
              radius: 30,
              backgroundColor: selectedTab == 'pending'
                  ? Colors.orange.withOpacity(0.2)
                  : isReassessmentTab
                      ? (isReassessmentApproved
                          ? Colors.teal.withOpacity(0.2)
                          : Colors.purple.withOpacity(0.2))
                      : isPassed
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
              child: Icon(
                selectedTab == 'pending'
                    ? Icons.pending_actions
                    : isReassessmentTab
                        ? (isReassessmentApproved
                            ? Icons.how_to_reg
                            : Icons.refresh)
                        : isPassed
                            ? Icons.check_circle
                            : Icons.cancel,
                size: 30,
                color: selectedTab == 'pending'
                    ? Colors.orange
                    : isReassessmentTab
                        ? (isReassessmentApproved
                            ? Colors.teal
                            : Colors.purple)
                        : isPassed
                            ? Colors.green
                            : Colors.red,
              ),
            ),
            const SizedBox(width: 16),

            // ── Info column ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${app.firstName} ${app.lastName}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    app.idNo != null && app.idNo!.isNotEmpty
                        ? 'ID No: ${app.idNo}'
                        : 'N/A',
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  if (isReassessmentTab &&
                      app.renewalReassessmentRequestedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Requested: ${DateFormat('yyyy-MM-dd HH:mm').format(app.renewalReassessmentRequestedAt!)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.purple),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: app.getStatusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: app.getStatusColor(), width: 1),
                    ),
                    child: Text(
                      app.getStatusText(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: app.getStatusColor(),
                      ),
                    ),
                  ),
                  if (isWalkIn && selectedTab == 'pending') ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'WALK-IN RE-EXAM',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Action buttons ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // ── PENDING TAB ──
                if (selectedTab == 'pending') ...[
                  FutureBuilder<Map<String, dynamic>>(
                    future: checkExamAvailability(app.id, app.status),
                    key: ValueKey(
                        'exam_${app.id}_${DateTime.now().minute}'),
                    builder: (context, snapshot) {
                      bool allowed = false;
                      DateTime? availableAt;
                      bool walkIn = false;

                      if (snapshot.connectionState ==
                              ConnectionState.done &&
                          snapshot.hasData) {
                        allowed = snapshot.data!["allowed"] as bool;
                        availableAt =
                            snapshot.data!["availableAt"] as DateTime?;
                        walkIn =
                            snapshot.data!["walkIn"] as bool? ?? false;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  allowed ? Colors.green : Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: allowed
                                ? () {
                                    if (isWalkIn) {
                                      _showExaminationDialog(app,
                                          isReassessment: true);
                                    } else if (isRenewal) {
                                      _showPastExamResultsAndProceed(app);
                                    } else {
                                      _showExaminationDialog(app);
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.health_and_safety,
                                size: 18),
                            label: Text(
                                walkIn ? 'Conduct Re-exam' : 'Conduct Exam'),
                          ),
                          if (!allowed && availableAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                "Available at ${TimeOfDay.fromDateTime(availableAt).format(context)}",
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.orange),
                              ),
                            ),
                          if (!allowed &&
                              availableAt == null &&
                              snapshot.connectionState ==
                                  ConnectionState.done &&
                              !walkIn)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                "No appointment found",
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ]

                // ── REASSESSMENT TAB — PENDING sub-filter ──
                else if (isReassessmentTab && isReassessmentPending) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _handleReassessmentDecision(app, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _handleReassessmentDecision(app, false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _showReassessmentDetailsModal(app),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Details'),
                  ),
                ]

                // ── REASSESSMENT TAB — APPROVED sub-filter ──
                else if (isReassessmentTab && isReassessmentApproved) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        _showExaminationDialog(app, isReassessment: true),
                    icon: const Icon(Icons.health_and_safety, size: 18),
                    label: const Text('Conduct Re-exam'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _viewReassessmentHistory(app),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('View History'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showReassessmentDetailsModal(app),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Details'),
                  ),
                ]

                // ── HISTORY TAB ──
                else if (selectedTab == 'examined') ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => showApplicationDetails(app),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Details'),
                  ),
                ],

                // ── RENEWAL badge (shared across tabs) ──
                if (isRenewal)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'RENEWAL',
                      style:
                          TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const HealthDrawer(),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Physical Examination Dashboard',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (userCampus != null)
                      Text(
                        'Campus: ${userCampus!.toUpperCase()}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600]),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: fetchApplications,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // ── Main tab buttons ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tabButton('pending', 'Pending Examination',
                    Icons.pending_actions, Colors.orange),
                tabButton('reassessment', 'Re-assessments', Icons.refresh,
                    Colors.purple),
                tabButton('examined', 'History', Icons.check_circle,
                    Colors.green),
              ],
            ),
          ),

          // ── Sub-filters ──
          if (selectedTab == 'pending') ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedAppointmentDate,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 30)),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(
                            () => selectedAppointmentDate = picked);
                        fetchApplications();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Icon(Icons.calendar_today,
                          size: 20, color: Colors.orange),
                    ),
                  ),
                  _smallFilterButton('all', 'All'),
                  _smallFilterButton('new', 'New'),
                  _smallFilterButton('renewal', 'Renewal'),
                  GestureDetector(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: Colors.blue),
                          const SizedBox(width: 6),
                          Text(
                            "Clinic closes ${clinicEndTime.format(context)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (selectedTab == 'examined') ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  filterButton('all', 'All', Icons.list, Colors.blue, false),
                  filterButton('pass', 'Passed', Icons.check_circle,
                      Colors.green, false),
                  filterButton(
                      'fail', 'Failed', Icons.cancel, Colors.red, false),
                ],
              ),
            ),
          ],

          // ── Reassessment sub-filters with badges ──
          if (selectedTab == 'reassessment') ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  _reassessmentFilterButton(
                    'pending',
                    'Pending Review',
                    Icons.pending,
                    Colors.orange,
                    _reassessmentPendingCount,
                  ),
                  _reassessmentFilterButton(
                    'approved',
                    'Approved (Re-exam)',
                    Icons.how_to_reg,
                    Colors.teal,
                    _reassessmentApprovedCount,
                  ),
                  _reassessmentFilterButton(
                    'all',
                    'All',
                    Icons.list,
                    Colors.purple,
                    0,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // ── List ──
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : applications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              selectedTab == 'pending'
                                  ? 'No pending examinations'
                                  : selectedTab == 'reassessment'
                                      ? (reassessmentFilter == 'pending'
                                          ? 'No pending reassessment requests'
                                          : reassessmentFilter == 'approved'
                                              ? 'No approved reassessments awaiting re-exam'
                                              : 'No reassessment requests')
                                      : 'No examination history',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: applications.length,
                        itemBuilder: (context, index) =>
                            applicationCard(applications[index]),
                      ),
          ),
        ],
      ),
    );
  }
}