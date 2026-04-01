// lib/main/student/student_portal_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class StudentPortalPage extends StatefulWidget {
  const StudentPortalPage({super.key});

  @override
  State<StudentPortalPage> createState() => _StudentPortalPageState();
}

class _StudentPortalPageState extends State<StudentPortalPage> {
  final supabase = Supabase.instance.client;
  final _srCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSearching = false;
  bool _hasSearched = false;

  Map<String, dynamic>? _liability;
  Map<String, dynamic>? _application;
  Map<String, dynamic>? _renewalApplication;
  Map<String, dynamic>? _disciplineRecord;

  @override
  void dispose() {
    _srCodeController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSearching = true;
      _hasSearched = false;
      _liability = null;
      _application = null;
      _renewalApplication = null;
      _disciplineRecord = null;
    });

    try {
      final srCode = _srCodeController.text.trim().toUpperCase();

      // 1. Find latest liability by sr_code
      final liabilityRes = await supabase
          .from('liabilities')
          .select('*')
          .eq('sr_code', srCode)
          .order('tagged_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (liabilityRes != null) {
        _liability = liabilityRes;

        // 2. Fetch linked application
        if (liabilityRes['application_id'] != null) {
          _application = await supabase
              .from('borrowing_applications')
              .select('*')
              .eq('id', liabilityRes['application_id'])
              .maybeSingle();
        }

        if (liabilityRes['renewal_application_id'] != null) {
          _renewalApplication = await supabase
              .from('renewal_applications')
              .select('*')
              .eq('id', liabilityRes['renewal_application_id'])
              .maybeSingle();
        }

        // 3. Check discipline record if forwarded
        if (liabilityRes['status'] == 'forwarded') {
          _disciplineRecord = await supabase
              .from('student_discipline')
              .select('*')
              .eq('liability_id', liabilityRes['id'])
              .maybeSingle();
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  _buildSearchCard(),
                  const SizedBox(height: 24),
                  if (_isSearching)
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF1565C0)),
                      ),
                    ),
                  if (_hasSearched && !_isSearching) _buildResults(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D47A1),
            Color(0xFF1976D2),
            Color(0xFF42A5F5),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white.withOpacity(0.85), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Back to Admin Login',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 2),
                ),
                child: const Icon(Icons.pedal_bike_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PedalHub',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  Text('Student Liability Portal',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Check Your Liability Status',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your SR Code to check if you have any pending liabilities from the bike borrowing program.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SEARCH CARD
  // ─────────────────────────────────────────────
  Widget _buildSearchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter Your SR Code',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            Text('e.g. 21-12345',
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _srCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. 21-12345',
                      prefixIcon: const Icon(Icons.badge_rounded,
                          color: Color(0xFF1565C0)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey[300]!)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1565C0), width: 2)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFF),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your SR Code';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSearching ? null : _search,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search_rounded),
                    label: Text(
                      _isSearching ? 'Searching...' : 'Search',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // RESULTS
  // ─────────────────────────────────────────────
  Widget _buildResults() {
    // No liability found
    if (_liability == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.green[50], shape: BoxShape.circle),
              child: Icon(Icons.check_circle_rounded,
                  color: Colors.green[600], size: 60),
            ),
            const SizedBox(height: 20),
            const Text('No Liability Found',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 8),
            Text(
              'Great news! Your SR Code has no pending liability records in the PedalHub system.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
          ],
        ),
      );
    }

    // Liability found
    final liabilityStatus = _liability!['status'] ?? 'pending';
    final isForwarded = liabilityStatus == 'forwarded';
    final app = _application ?? _renewalApplication;
    final isRenewal = _renewalApplication != null;

    return Column(
      children: [
        _buildStatusBanner(isForwarded),
        const SizedBox(height: 20),

        // Liability details
        _buildDetailCard(
          title: 'Liability Details',
          icon: Icons.flag_rounded,
          iconColor: const Color(0xFFD32F2F),
          children: [
            _detailRow(
                'Borrower Name', _liability!['borrower_name'] ?? 'N/A'),
            _detailRow('SR Code', _liability!['sr_code'] ?? 'N/A'),
            _detailRow('Campus',
                (_liability!['campus'] ?? 'N/A').toString().toUpperCase()),
            _detailRow('Bike Number', _liability!['bike_number'] ?? 'N/A'),
            _detailRow('Status', _formatStatus(liabilityStatus),
                valueColor: _getStatusColor(liabilityStatus)),
            _detailRow(
              'Tagged On',
              _liability!['tagged_at'] != null
                  ? DateFormat('MMMM dd, yyyy — hh:mm a').format(
                      DateTime.parse(_liability!['tagged_at']).toLocal())
                  : 'N/A',
            ),
            if (_liability!['remarks'] != null &&
                _liability!['remarks'].toString().isNotEmpty)
              _detailRow('Remarks', _liability!['remarks']),
          ],
        ),
        const SizedBox(height: 16),

        // Application details
        if (app != null)
          _buildDetailCard(
            title: isRenewal
                ? 'Renewal Application'
                : 'Borrowing Application',
            icon: isRenewal
                ? Icons.autorenew_rounded
                : Icons.assignment_rounded,
            iconColor: isRenewal
                ? const Color(0xFF7B1FA2)
                : const Color(0xFF1565C0),
            children: [
              _detailRow('Application Type',
                  isRenewal ? 'Renewal' : 'New Borrowing'),
              _detailRow(
                'Application Status',
                _formatStatus(app['status'] ?? 'N/A'),
                valueColor: const Color(0xFFD32F2F),
              ),
              if (app['bike_number'] != null)
                _detailRow('Bike Number', app['bike_number']),
              if (app['campus'] != null)
                _detailRow(
                    'Campus', app['campus'].toString().toUpperCase()),
              if (app['created_at'] != null)
                _detailRow(
                  'Application Date',
                  DateFormat('MMMM dd, yyyy').format(
                      DateTime.parse(app['created_at']).toLocal()),
                ),
            ],
          ),
        const SizedBox(height: 16),

        // Discipline record
        if (isForwarded && _disciplineRecord != null)
          _buildDetailCard(
            title: 'Student Discipline',
            icon: Icons.account_balance_rounded,
            iconColor: const Color(0xFF7B1FA2),
            children: [
              _detailRow(
                'Case Status',
                _formatStatus(_disciplineRecord!['status'] ?? 'open'),
                valueColor: const Color(0xFF7B1FA2),
              ),
              _detailRow(
                'Forwarded On',
                _disciplineRecord!['forwarded_at'] != null
                    ? DateFormat('MMMM dd, yyyy — hh:mm a').format(
                        DateTime.parse(
                                _disciplineRecord!['forwarded_at'])
                            .toLocal())
                    : 'N/A',
              ),
              if (_disciplineRecord!['notes'] != null &&
                  _disciplineRecord!['notes'].toString().isNotEmpty)
                _detailRow('Notes', _disciplineRecord!['notes']),
            ],
          ),
        const SizedBox(height: 16),

        _buildNextStepsCard(isForwarded),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // STATUS BANNER
  // ─────────────────────────────────────────────
  Widget _buildStatusBanner(bool isForwarded) {
    final color =
        isForwarded ? const Color(0xFF7B1FA2) : const Color(0xFFD32F2F);
    final bgColor = isForwarded
        ? const Color(0xFFF3E5F5)
        : const Color(0xFFFFEBEE);
    final icon =
        isForwarded ? Icons.account_balance_rounded : Icons.flag_rounded;
    final title = isForwarded
        ? 'Case Forwarded to Student Discipline'
        : 'You Have a Pending Liability';
    final subtitle = isForwarded
        ? 'Your case has been escalated to the Student Discipline Office. Please report immediately.'
        : 'Your bike borrowing has been terminated and a liability has been recorded against you.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: color.withOpacity(0.8),
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DETAIL CARD
  // ─────────────────────────────────────────────
  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? const Color(0xFF1A1A1A))),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // NEXT STEPS
  // ─────────────────────────────────────────────
  Widget _buildNextStepsCard(bool isForwarded) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF1565C0).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded,
                color: Color(0xFF1565C0), size: 20),
            const SizedBox(width: 8),
            const Text('What should you do?',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0))),
          ]),
          const SizedBox(height: 16),
          if (isForwarded) ...[
            _stepItem(
                '1', 'Go to the Student Discipline Office immediately.'),
            _stepItem('2', 'Bring a valid school ID and your SR Code.'),
            _stepItem('3', 'Explain your situation and settle the case.'),
            _stepItem('4',
                'Once resolved, contact the GSO to update your liability status.'),
          ] else ...[
            _stepItem(
                '1', 'Go to the GSO office and return the bike immediately.'),
            _stepItem('2', 'Coordinate with the GSO officer in charge.'),
            _stepItem('3',
                'Failure to return may result in escalation to Student Discipline.'),
          ],
        ],
      ),
    );
  }

  Widget _stepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
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
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFE65100);
      case 'forwarded':
        return const Color(0xFF7B1FA2);
      case 'resolved':
        return Colors.green;
      default:
        return const Color(0xFFD32F2F);
    }
  }
}