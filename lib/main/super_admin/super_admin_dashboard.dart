import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_page.dart';
import 'dart:async';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String _selectedRoleFilter = 'ALL';

  List<Map<String, dynamic>> get _filteredAccounts {
    return _accounts.where((account) {
      final matchesRole = _selectedRoleFilter == 'ALL' ||
          account['role'] == _selectedRoleFilter;
      final query = _searchQuery.toLowerCase();
      final matchesSearch = query.isEmpty ||
          (account['email'] ?? '').toLowerCase().contains(query) ||
          (account['role'] ?? '').toLowerCase().contains(query) ||
          (account['campus'] ?? '').toLowerCase().contains(query);
      return matchesRole && matchesSearch;
    }).toList();
  }

  Map<String, dynamic>? _semester;
  bool _isSemesterLoading = true;

  Map<String, dynamic>? _settings;
  bool _settingsLoading = true;

  Timer? _timer;
  Duration _remainingTime = Duration.zero;

  final List<String> _roles = [
    'GSO', 'SDO', 'HEALTH', 'VICE', 'CHANCELLOR', 'HRMO', 'DISCIPLINE'
  ];

  final List<String> _campuses = [
    'LIMA',
    'PABLO BORBON',
    'ALANGILAN',
    'LIPA',
    'ARASOF NASUGBU',
    'JPLPC MALVAR',
    'LEMERY',
    'ROSARIO',
    'SAN JUAN',
    'BALAYAN',
    'LOBO',
    'MABINI',
  ];

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
    _fetchSemester();
    _fetchSettings();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─── Semester ────────────────────────────────────────────────

  Future<void> _fetchSemester() async {
    setState(() => _isSemesterLoading = true);
    final data = await _supabase
        .from('semester')
        .select()
        .limit(1)
        .maybeSingle();
    setState(() {
      _semester = data;
      _isSemesterLoading = false;
    });
  }

  Future<void> _fetchSettings() async {
    setState(() => _settingsLoading = true);

    final data = await _supabase
        .from('system_settings')
        .select()
        .limit(1)
        .single();

    setState(() {
      _settings = data;
      _settingsLoading = false;
    });

    _startTimer();
  }

  Future<void> _updateSettings(Map<String, dynamic> payload) async {
    await _supabase
        .from('system_settings')
        .update(payload)
        .eq('id', _settings!['id']);

    await _fetchSettings();
  }

  void _startTimer() {
    _timer?.cancel();

    if (_settings == null) return;
    if (_settings!['is_test_mode'] != true) return;

    final int minutes = _settings!['test_cycle_minutes'];
    final endTime = DateTime.now().add(Duration(minutes: minutes));

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = endTime.difference(DateTime.now());

      if (remaining.isNegative) {
        timer.cancel();
        setState(() {
          _remainingTime = Duration.zero;
        });
      } else {
        setState(() {
          _remainingTime = remaining;
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Future<void> _saveSemester({
    required String label,
    required String academicYear,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final payload = {
      'label': label,
      'academic_year': academicYear,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
    };

    if (_semester == null) {
      await _supabase.from('semester').insert(payload);
    } else {
      await _supabase
          .from('semester')
          .update(payload)
          .eq('id', _semester!['id']);
    }

    await _fetchSemester();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semester saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showSemesterDialog() {
    final labelController = TextEditingController(
      text: _semester?['label'] ?? '',
    );
    final academicYearController = TextEditingController(
      text: _semester?['academic_year'] ?? '',
    );

    DateTime? startDate = _semester?['start_date'] != null
        ? DateTime.parse(_semester!['start_date'])
        : null;
    DateTime? endDate = _semester?['end_date'] != null
        ? DateTime.parse(_semester!['end_date'])
        : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Semester'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Semester Label (e.g. 1st Sem 2025)',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: academicYearController,
                  decoration: const InputDecoration(
                    labelText: 'Academic Year (e.g. 2025-2026)',
                    prefixIcon: Icon(Icons.school_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      startDate != null
                          ? '${startDate!.month}/${startDate!.day}/${startDate!.year}'
                          : 'Select start date',
                      style: TextStyle(
                        color: startDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate ?? (startDate ?? DateTime.now()),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'End Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      endDate != null
                          ? '${endDate!.month}/${endDate!.day}/${endDate!.year}'
                          : 'Select end date',
                      style: TextStyle(
                        color: endDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (labelController.text.trim().isEmpty ||
                    academicYearController.text.trim().isEmpty ||
                    startDate == null ||
                    endDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all fields.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                if (endDate!.isBefore(startDate!)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('End date must be after start date.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                await _saveSemester(
                  label: labelController.text.trim(),
                  academicYear: academicYearController.text.trim(),
                  startDate: startDate!,
                  endDate: endDate!,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Accounts ────────────────────────────────────────────────

  Future<void> _fetchAccounts() async {
    setState(() => _isLoading = true);
    final data = await _supabase
        .from('profiles')
        .select()
        .neq('role', 'super_admin');
    setState(() {
      _accounts = List<Map<String, dynamic>>.from(data);
      _isLoading = false;
    });
  }

  Future<void> _createAccount(
      String email, String password, String role, String campus) async {
    try {
      await _supabase.functions.invoke('create-admin', body: {
        'action': 'create',
        'email': email,
        'password': password,
        'role': role,
        'campus': campus,
      });
      await _fetchAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateAccount(
      String userId, String email, String password, String role, String campus) async {
    try {
      await _supabase.functions.invoke('create-admin', body: {
        'action': 'update',
        'userId': userId,
        'email': email,
        if (password.isNotEmpty) 'password': password,
        'role': role,
        'campus': campus,
      });
      await _fetchAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAccount(String userId) async {
    try {
      await _supabase.functions.invoke('create-admin', body: {
        'action': 'delete',
        'userId': userId,
      });
      await _fetchAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCreateDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = _roles.first;
    String selectedCampus = _campuses.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Admin Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: _roles.map((role) => DropdownMenuItem(
                    value: role,
                    child: Text(role),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedRole = value!);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCampus,
                  decoration: const InputDecoration(
                    labelText: 'Campus',
                    prefixIcon: Icon(Icons.location_city_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _campuses.map((campus) => DropdownMenuItem(
                    value: campus,
                    child: Text(campus),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedCampus = value!);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (emailController.text.trim().isEmpty ||
                    passwordController.text.trim().isEmpty) return;
                Navigator.pop(context);
                await _createAccount(
                  emailController.text.trim(),
                  passwordController.text.trim(),
                  selectedRole,
                  selectedCampus,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> account) {
    final emailController = TextEditingController(text: account['email']);
    final passwordController = TextEditingController();
    String selectedRole = account['role'];
    String selectedCampus = account['campus'] ?? _campuses.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Admin Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'New Password (leave blank to keep)',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: _roles.map((role) => DropdownMenuItem(
                    value: role,
                    child: Text(role),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedRole = value!);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCampus,
                  decoration: const InputDecoration(
                    labelText: 'Campus',
                    prefixIcon: Icon(Icons.location_city_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _campuses.map((campus) => DropdownMenuItem(
                    value: campus,
                    child: Text(campus),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedCampus = value!);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateAccount(
                  account['id'],
                  emailController.text.trim(),
                  passwordController.text.trim(),
                  selectedRole,
                  selectedCampus,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete ${account['email']}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAccount(account['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    final d = DateTime.parse(isoDate);
    return '${d.month}/${d.day}/${d.year}';
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Super Admin Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD32F2F),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await _supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFFD32F2F),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Account', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Semester Card ──────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Color(0xFFD32F2F)),
                      const SizedBox(width: 8),
                      const Text(
                        'Active Semester',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showSemesterDialog,
                        icon: Icon(
                          _semester == null ? Icons.add : Icons.edit,
                          size: 18,
                        ),
                        label: Text(_semester == null ? 'Set' : 'Edit'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  _isSemesterLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _semester == null
                          ? const Text(
                              'No semester set yet.',
                              style: TextStyle(color: Colors.grey),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _infoRow(Icons.label_outline, 'Semester', _semester!['label']),
                                const SizedBox(height: 6),
                                _infoRow(Icons.school_outlined, 'Academic Year', _semester!['academic_year']),
                                const SizedBox(height: 6),
                                _infoRow(Icons.play_circle_outline, 'Start Date', _formatDate(_semester!['start_date'])),
                                const SizedBox(height: 6),
                                _infoRow(Icons.stop_circle_outlined, 'End Date', _formatDate(_semester!['end_date'])),
                              ],
                            ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── System Testing Mode Card ───────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _settingsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'System Testing Mode',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Enable Test Mode'),
                          subtitle: const Text('Compress semester lifecycle for demo'),
                          value: _settings?['is_test_mode'] ?? false,
                          onChanged: (value) {
                            _updateSettings({'is_test_mode': value});
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          value: _settings?['test_cycle_minutes'] ?? 10,
                          decoration: const InputDecoration(
                            labelText: 'Test Cycle Duration',
                            border: OutlineInputBorder(),
                          ),
                          items: [5, 10, 15].map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text('$e minutes'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            _updateSettings({'test_cycle_minutes': value});
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_settings?['is_test_mode'] == true)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer, color: Colors.red),
                                const SizedBox(width: 10),
                                const Text(
                                  'Cycle Ends In:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Text(
                                  _formatDuration(_remainingTime),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Short Term Borrowing Card ──────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _settingsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Short Term Borrowing',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Enable Short Term'),
                          subtitle: const Text('Allow short-term bike borrowing'),
                          value: _settings?['is_short_term'] ?? false,
                          activeColor: const Color(0xFFD32F2F),
                          onChanged: (value) {
                            _updateSettings({'is_short_term': value});
                          },
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Pending Next Semester Activations ──────────────
          _PendingNextSemSection(supabase: _supabase),

          const SizedBox(height: 16),

          // ── Admin Accounts Header ──────────────────────────
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Admin Accounts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          // ── Search Bar ────────────────────────────────────
          TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search by email, role, or campus...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFFD32F2F)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Role Filter Chips ──────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', ..._roles].map((role) {
                final isSelected = _selectedRoleFilter == role;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      role,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFFD32F2F),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedRoleFilter = role),
                    selectedColor: const Color(0xFFD32F2F),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFD32F2F)
                          : Colors.grey.shade300,
                    ),
                    checkmarkColor: Colors.white,
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // ── Result Count ───────────────────────────────────
          if (!_isLoading && _accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${_filteredAccounts.length} of ${_accounts.length} account${_accounts.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),

          // ── Accounts List ──────────────────────────────────
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_accounts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No accounts yet.\nTap + Add Account to create one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else if (_filteredAccounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No accounts match your search.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 15, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_filteredAccounts.length, (index) {
              final account = _filteredAccounts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD32F2F),
                    child: Text(
                      account['role'][0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    account['email'],
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Role: ${account['role']}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      Text(
                        'Campus: ${account['campus'] ?? 'N/A'}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF1976D2)),
                        onPressed: () => _showEditDialog(account),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showDeleteDialog(account),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Pending Next Semester Section ───────────────────────────────────────────

class _PendingNextSemSection extends StatefulWidget {
  final SupabaseClient supabase;
  const _PendingNextSemSection({required this.supabase});

  @override
  State<_PendingNextSemSection> createState() => _PendingNextSemSectionState();
}

class _PendingNextSemSectionState extends State<_PendingNextSemSection> {
  List<Map<String, dynamic>> _pending = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  Future<void> _fetchPending() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.supabase
          .from('renewal_applications')
          .select(
            'id, full_name, first_name, last_name, '
            'original_application_id, created_at',
          )
          .eq('status', 'renewal_pending_next_sem')
          .order('created_at', ascending: true);
      setState(() {
        _pending = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _activateRenewal(Map<String, dynamic> renewal) async {
    try {
      final semester = await widget.supabase
          .from('semester')
          .select('end_date')
          .limit(1)
          .maybeSingle();

      if (semester == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active semester set. Please set a semester first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final semesterEnd = DateTime.parse(semester['end_date'].toString());
      final now = DateTime.now();

      final application = await widget.supabase
          .from('borrowing_applications')
          .select('user_id, assigned_bike_id, assigned_bike_number')
          .eq('id', renewal['original_application_id'])
          .single();

      await widget.supabase.from('borrowing_sessions').insert({
        'user_id': application['user_id'],
        'application_id': renewal['original_application_id'],
        'bike_id': application['assigned_bike_id'],
        'session_type': 'semestral',
        'status': 'active',
        'start_time': now.toIso8601String(),
        'expected_return_time': semesterEnd.toIso8601String(),
      });

      await widget.supabase
          .from('borrowing_applications')
          .update({
            'status': 'active',
            'bike_collected_at': now.toIso8601String(),
          })
          .eq('id', renewal['original_application_id']);

      await widget.supabase
          .from('renewal_applications')
          .update({
            'status': 'renewal_active',
            'activated_at': now.toIso8601String(),
          })
          .eq('id', renewal['id']);

      await _fetchPending();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${renewal['first_name']} ${renewal['last_name']} '
              'renewal activated successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error activating renewal: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    if (_pending.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: Color(0xFF1976D2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending Next Semester Activations (${_pending.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _fetchPending,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const Divider(),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These students returned their bikes and have an approved renewal. '
                      'Activate them once the new semester begins.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._pending.map(
              (renewal) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Icon(
                      Icons.person,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${renewal['first_name'] ?? ''} '
                    '${renewal['last_name'] ?? ''}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Renewal #${renewal['id']} • '
                    'App #${renewal['original_application_id']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _showActivateDialog(renewal),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Activate',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActivateDialog(Map<String, dynamic> renewal) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Activate Renewal'),
        content: Text(
          'Activate next semester ride for '
          '${renewal['first_name']} ${renewal['last_name']}?\n\n'
          'This will create a new active session using the current '
          "semester's end date.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _activateRenewal(renewal);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
  }
}