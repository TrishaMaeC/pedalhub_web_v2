import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/health_drawer.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final supabase = Supabase.instance.client;

  // ── Counters
  int totalExaminations = 0;
  int totalStudents = 0;
  int totalPersonnel = 0;
  int passCount = 0;
  int reassessmentCount = 0;
  int totalRenewals = 0;
  int totalNewApplications = 0;

  // ── Chart data
  Map<String, int> bmiCategoryDistribution = {};
  Map<String, int> healthConcerns = {};

  // ── Appointments
  List<Map<String, dynamic>> upcomingAppointments = [];

  bool isLoading = true;

  // ── Logged-in user's campus (fetched from profiles table)
  String? userCampus;

  @override
  void initState() {
    super.initState();
    _loadUserCampusAndDashboard();
  }

  // ─────────────────────────────────────────────
  // STEP 1 — LOAD USER CAMPUS
  // ─────────────────────────────────────────────
  Future<void> _loadUserCampusAndDashboard() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      await _loadDashboardData();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading user profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // STEP 2 — LOAD ALL DASHBOARD DATA
  // ─────────────────────────────────────────────
  Future<void> _loadDashboardData() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _loadExaminationStats(),
        _loadUpcomingAppointments(),
        _loadApplicationCounts(),
      ]);
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  // EXAMINATION STATS
  // Now: physical_examinations → borrowing_applications_version2
  // Uses is_renewal to distinguish renewal exams.
  // Uses user_type to distinguish student vs personnel.
  // Campus filter is done server-side via the joined table.
  // ─────────────────────────────────────────────
  Future<void> _loadExaminationStats() async {
    // Reset
    totalExaminations = 0;
    totalStudents = 0;
    totalPersonnel = 0;
    passCount = 0;
    reassessmentCount = 0;
    bmiCategoryDistribution = {};
    healthConcerns = {
      'Balance Issues': 0,
      'Musculoskeletal': 0,
      'Lung Concerns': 0,
      'Heart Concerns': 0,
      'Extremity Issues': 0,
      'Hearing Issues': 0,
      'Vision Issues': 0,
    };

    // Single query — join to borrowing_applications_version2 for campus + user_type
    // Filter campus server-side using ilike on the joined table
    final exams = await supabase
        .from('physical_examinations')
        .select('''
          id, bmi_category, is_reassessment, is_renewal,
          balance, musculoskeletal, lungs, heart,
          extremities, hearing, vision,
          borrowing_applications_version2!physical_examinations_application_id_fkey(
            user_type, campus
          )
        ''')
        .not('application_id', 'is', null);

    // Client-side campus filter
    // (physical_examinations has no campus column directly)
    final filtered = (exams as List).where((exam) {
      final app = exam['borrowing_applications_version2'];
      if (app == null) return false;
      final campus = (app['campus'] ?? '').toString().toLowerCase();
      return campus == userCampus;
    }).toList();

    totalExaminations = filtered.length;

    for (final exam in filtered) {
      // BMI distribution
      final category = (exam['bmi_category'] ?? 'Unknown') as String;
      bmiCategoryDistribution[category] =
          (bmiCategoryDistribution[category] ?? 0) + 1;

      // Pass vs reassessment
      if (exam['is_reassessment'] == true) {
        reassessmentCount++;
      } else {
        passCount++;
      }

      // Student vs personnel — use user_type from borrowing_applications_version2
      final app = exam['borrowing_applications_version2'];
      if (app != null) {
        final userType = (app['user_type'] ?? '').toString().toLowerCase();
        if (userType == 'personnel') {
          totalPersonnel++;
        } else {
          totalStudents++;
        }
      }

      // Health concerns
      if (exam['balance'] == false) {
        healthConcerns['Balance Issues'] = healthConcerns['Balance Issues']! + 1;
      }
      if (exam['musculoskeletal'] == false) {
        healthConcerns['Musculoskeletal'] =
            healthConcerns['Musculoskeletal']! + 1;
      }
      if (exam['lungs'] == false) {
        healthConcerns['Lung Concerns'] = healthConcerns['Lung Concerns']! + 1;
      }
      if (exam['heart'] == false) {
        healthConcerns['Heart Concerns'] = healthConcerns['Heart Concerns']! + 1;
      }
      if (exam['extremities'] == false) {
        healthConcerns['Extremity Issues'] =
            healthConcerns['Extremity Issues']! + 1;
      }
      if (exam['hearing'] == false) {
        healthConcerns['Hearing Issues'] = healthConcerns['Hearing Issues']! + 1;
      }
      if (exam['vision'] == false) {
        healthConcerns['Vision Issues'] = healthConcerns['Vision Issues']! + 1;
      }
    }
  }

  // ─────────────────────────────────────────────
  // UPCOMING APPOINTMENTS
  // Now uses: medical_appointments_version2
  // Joins borrowing_applications_version2 for name + campus
  // ─────────────────────────────────────────────
  Future<void> _loadUpcomingAppointments() async {
    final now = DateTime.now();
    final today = now.toIso8601String().split('T').first;
    final currentTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    final response = await supabase
        .from('medical_appointments_version2')
        .select('''
          id, appointment_date, appointment_time, status, appointment_type,
          borrowing_applications_version2!medical_appointments_version2_application_id_fkey(
            first_name, last_name, control_number, campus, user_type
          )
        ''')
        .eq('status', 'scheduled')
        .or(
          'appointment_date.gt.$today,and(appointment_date.eq.$today,appointment_time.gt.$currentTime)',
        )
        .order('appointment_date')
        .order('appointment_time')
        .limit(20); // fetch more, filter client-side

    // Filter by campus client-side
    final filtered = (response as List).where((appt) {
      final app = appt['borrowing_applications_version2'];
      if (app == null) return false;
      final campus = (app['campus'] ?? '').toString().toLowerCase();
      return campus == userCampus;
    }).take(5).toList();

    upcomingAppointments = List<Map<String, dynamic>>.from(filtered);
  }

  // ─────────────────────────────────────────────
  // APPLICATION COUNTS
  // New vs Renewal — both live in borrowing_applications_version2.
  // renewal_count > 0  → renewal
  // renewal_count == 0 → new application
  // ─────────────────────────────────────────────
  Future<void> _loadApplicationCounts() async {
    // All applications for this campus
    final allApps = await supabase
        .from('borrowing_applications_version2')
        .select('id, renewal_count')
        .ilike('campus', userCampus!);

    int renewals = 0;
    int newApps = 0;

    for (final app in (allApps as List)) {
      final renewalCount = (app['renewal_count'] ?? 0) as int;
      if (renewalCount > 0) {
        renewals++;
      } else {
        newApps++;
      }
    }

    setState(() {
      totalRenewals = renewals;
      totalNewApplications = newApps;
    });
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
                  builder: (context) => Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      color: const Color(0xFFD32F2F),
                      iconSize: 28,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFD32F2F)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading health data...',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFFD32F2F),
                    onRefresh: _loadDashboardData,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 900;
                        final isMobile = constraints.maxWidth < 600;
                        final padding = isDesktop ? 32.0 : 16.0;

                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(padding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPageHeader(isDesktop),
                              SizedBox(height: isDesktop ? 40 : 24),
                              _buildMetricsGrid(isDesktop, isMobile),
                              SizedBox(height: isDesktop ? 32 : 20),
                              isDesktop
                                  ? IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                              child: _buildHealthConcernsChart(
                                                  isDesktop)),
                                          const SizedBox(width: 24),
                                          Expanded(
                                              child: _buildUpcomingAppointments(
                                                  isDesktop)),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        _buildHealthConcernsChart(isDesktop),
                                        const SizedBox(height: 20),
                                        _buildUpcomingAppointments(isDesktop),
                                      ],
                                    ),
                              SizedBox(height: isDesktop ? 32 : 20),
                              isDesktop
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child:
                                                _buildBMICategoryChart(isDesktop)),
                                        const SizedBox(width: 24),
                                        Expanded(
                                            child:
                                                _buildResultChart(isDesktop)),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _buildBMICategoryChart(isDesktop),
                                        const SizedBox(height: 20),
                                        _buildResultChart(isDesktop),
                                      ],
                                    ),
                              SizedBox(height: isDesktop ? 32 : 20),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PAGE HEADER
  // ─────────────────────────────────────────────
  Widget _buildPageHeader(bool isDesktop) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isDesktop ? 12 : 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFE57373)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.health_and_safety_rounded,
              color: Colors.white, size: isDesktop ? 32 : 24),
        ),
        SizedBox(width: isDesktop ? 16 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Services Dashboard',
                style: TextStyle(
                  fontSize: isDesktop ? 32 : 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userCampus != null
                    ? 'Campus: ${userCampus!.toUpperCase()}  •  Medical appointments and health examination analytics'
                    : 'Medical appointments and health examination analytics',
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadDashboardData,
          color: Colors.grey[600],
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // METRICS GRID
  // ─────────────────────────────────────────────
  Widget _buildMetricsGrid(bool isDesktop, bool isMobile) {
    final metrics = [
      _MetricData(
        'Total Examinations',
        totalExaminations.toString(),
        Icons.assignment,
        const LinearGradient(
            colors: [Color(0xFF1976D2), Color(0xFF42A5F5)]),
      ),
      _MetricData(
        'Students Examined',
        totalStudents.toString(),
        Icons.school,
        const LinearGradient(
            colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]),
      ),
      _MetricData(
        'Personnel Examined',
        totalPersonnel.toString(),
        Icons.badge,
        const LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFFBA68C8)]),
      ),
      _MetricData(
        'Reassessments',
        reassessmentCount.toString(),
        Icons.warning,
        const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFE57373)]),
      ),
      _MetricData(
        'Total Renewals',
        totalRenewals.toString(),
        Icons.refresh_rounded,
        const LinearGradient(
            colors: [Color(0xFF0288D1), Color(0xFF4FC3F7)]),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 5 : (isMobile ? 2 : 3),
        mainAxisSpacing: isDesktop ? 20 : 12,
        crossAxisSpacing: isDesktop ? 20 : 12,
        childAspectRatio: isDesktop ? 1.6 : 1.5,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) =>
          _buildMetricCard(metrics[index], isDesktop),
    );
  }

  Widget _buildMetricCard(_MetricData data, bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 24 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 12 : 8),
            decoration: BoxDecoration(
              gradient: data.gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon,
                color: Colors.white, size: isDesktop ? 24 : 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: TextStyle(
                  fontSize: isDesktop ? 28 : 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: isDesktop ? 13 : 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HEALTH CONCERNS
  // ─────────────────────────────────────────────
  Widget _buildHealthConcernsChart(bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health Concerns',
                      style: TextStyle(
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  Text('Common medical issues identified',
                      style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: Colors.grey[600])),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.medical_services_rounded,
                    color: Color(0xFFD32F2F), size: 20),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          ...healthConcerns.entries.map((entry) {
            final maxValue =
                healthConcerns.values.fold(0, (a, b) => a > b ? a : b);
            final percentage =
                maxValue > 0 ? (entry.value / maxValue).toDouble() : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key,
                          style: TextStyle(
                              fontSize: isDesktop ? 13 : 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800])),
                      Text('${entry.value}',
                          style: TextStyle(
                              fontSize: isDesktop ? 13 : 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFD32F2F))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFD32F2F)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UPCOMING APPOINTMENTS
  // ─────────────────────────────────────────────
  Widget _buildUpcomingAppointments(bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upcoming Appointments',
                      style: TextStyle(
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  Text('Next scheduled check-ups',
                      style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: Colors.grey[600])),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.calendar_today_rounded,
                    color: Color(0xFF388E3C), size: 20),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          if (upcomingAppointments.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No upcoming appointments',
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: isDesktop ? 14 : 13)),
                  ],
                ),
              ),
            )
          else
            ...upcomingAppointments.map((appointment) {
              final appData =
                  appointment['borrowing_applications_version2'] ?? {};
              final date =
                  DateTime.tryParse(appointment['appointment_date'] ?? '') ??
                      DateTime.now();
              final time = appointment['appointment_time'] ?? '00:00:00';
              final timeStr = time.toString().length >= 5
                  ? time.toString().substring(0, 5)
                  : time.toString();
              final appointmentType =
                  (appointment['appointment_type'] ?? 'new').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(isDesktop ? 16 : 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Container(
                      width: isDesktop ? 56 : 48,
                      height: isDesktop ? 56 : 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF388E3C), Color(0xFF66BB6A)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(date.day.toString(),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isDesktop ? 20 : 16,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            [
                              'Jan','Feb','Mar','Apr','May','Jun',
                              'Jul','Aug','Sep','Oct','Nov','Dec'
                            ][date.month - 1],
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: isDesktop ? 11 : 10,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isDesktop ? 16 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${appData['first_name'] ?? ''} ${appData['last_name'] ?? ''}',
                            style: TextStyle(
                                fontSize: isDesktop ? 15 : 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1A1A1A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  size: 13, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(timeStr,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                              const SizedBox(width: 12),
                              Icon(Icons.badge_rounded,
                                  size: 13, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  appData['control_number'] ?? 'N/A',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Show appointment type badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: appointmentType == 'renewal'
                                      ? const Color(0xFFE3F2FD)
                                      : const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  appointmentType == 'renewal'
                                      ? 'Renewal'
                                      : 'New',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: appointmentType == 'renewal'
                                        ? const Color(0xFF0288D1)
                                        : const Color(0xFF388E3C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BMI CHART
  // ─────────────────────────────────────────────
  Widget _buildBMICategoryChart(bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BMI Categories',
                      style: TextStyle(
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  Text('Student health distribution',
                      style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: Colors.grey[600])),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.pie_chart_rounded,
                    color: Color(0xFFF57C00), size: 20),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 32 : 20),
          bmiCategoryDistribution.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.donut_large_rounded,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No BMI data available',
                            style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: isDesktop ? 14 : 13)),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: isDesktop ? 280 : 220,
                      child: PieChart(
                        PieChartData(
                          sections: _getBMIPieChartSections(isDesktop),
                          sectionsSpace: 3,
                          centerSpaceRadius: isDesktop ? 50 : 40,
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildBMILegend(isDesktop),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildBMILegend(bool isDesktop) {
    final colors = {
      'Underweight': const Color(0xFF42A5F5),
      'Normal': const Color(0xFF66BB6A),
      'Overweight': const Color(0xFFFFB74D),
      'Obese': const Color(0xFFEF5350),
    };

    return Wrap(
      spacing: isDesktop ? 16 : 12,
      runSpacing: 8,
      children: colors.entries.map((entry) {
        final count = bmiCategoryDistribution[entry.key] ?? 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: entry.value,
                  borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text('${entry.key} ($count)',
                style: TextStyle(
                    fontSize: isDesktop ? 12 : 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500)),
          ],
        );
      }).toList(),
    );
  }

  List<PieChartSectionData> _getBMIPieChartSections(bool isDesktop) {
    final colors = {
      'Underweight': const Color(0xFF42A5F5),
      'Normal': const Color(0xFF66BB6A),
      'Overweight': const Color(0xFFFFB74D),
      'Obese': const Color(0xFFEF5350),
    };

    final total =
        bmiCategoryDistribution.values.fold(0, (a, b) => a + b);

    return bmiCategoryDistribution.entries.map((entry) {
      final percentage =
          total > 0 ? (entry.value / total * 100) : 0;
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        color: colors[entry.key] ?? Colors.grey,
        radius: isDesktop ? 70 : 55,
        titleStyle: TextStyle(
          fontSize: isDesktop ? 14 : 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  // ─────────────────────────────────────────────
  // RENEWALS vs NEW APPLICATIONS BAR CHART
  // ─────────────────────────────────────────────
  Widget _buildResultChart(bool isDesktop) {
    final maxY =
        (totalNewApplications > totalRenewals
                ? totalNewApplications
                : totalRenewals)
            .toDouble() *
        1.2;

    return Container(
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Renewals vs New Applications',
                      style: TextStyle(
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  Text('Application type comparison',
                      style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: Colors.grey[600])),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.bar_chart_rounded,
                    color: Color(0xFF0288D1), size: 20),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          SizedBox(
            height: isDesktop ? 280 : 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY <= 0 ? 10 : maxY,
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                      toY: totalNewApplications.toDouble(),
                      color: const Color(0xFF388E3C),
                      width: isDesktop ? 48 : 36,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                      toY: totalRenewals.toDouble(),
                      color: const Color(0xFF0288D1),
                      width: isDesktop ? 48 : 36,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ]),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0:
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('New',
                                  style: TextStyle(
                                      fontSize: isDesktop ? 13 : 12,
                                      fontWeight: FontWeight.w600)),
                            );
                          case 1:
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('Renewals',
                                  style: TextStyle(
                                      fontSize: isDesktop ? 13 : 12,
                                      fontWeight: FontWeight.w600)),
                            );
                          default:
                            return const SizedBox();
                        }
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                            fontSize: isDesktop ? 11 : 10,
                            color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey[200]!, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendDot(const Color(0xFF388E3C),
                  'New Applications ($totalNewApplications)', isDesktop),
              const SizedBox(width: 24),
              _buildLegendDot(const Color(0xFF0288D1),
                  'Renewals ($totalRenewals)', isDesktop),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label, bool isDesktop) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: isDesktop ? 12 : 11,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// HELPER MODEL
// ─────────────────────────────────────────────
class _MetricData {
  final String title;
  final String value;
  final IconData icon;
  final Gradient gradient;

  const _MetricData(this.title, this.value, this.icon, this.gradient);
}