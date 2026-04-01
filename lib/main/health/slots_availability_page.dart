import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/health_drawer.dart';
import 'package:pedalhub_admin/models/appointment_slots.dart';

class HealthDashboardPage extends StatefulWidget {
  const HealthDashboardPage({super.key});

  @override
  State<HealthDashboardPage> createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  List<AppointmentSlot> slots = [];
  bool isLoading = true;
  String selectedFilter = 'upcoming';
  String? userCampus;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // ── Color palette
  static const _primary = Color(0xFFD32F2F);
  static const _primaryLight = Color.fromARGB(255, 233, 52, 52);
  static const _surface = Color(0xFFF8FAF9);
  static const _cardBg = Colors.white;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadUserCampusAndSlots();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // LOAD USER CAMPUS THEN FETCH
  // ─────────────────────────────────────────────
  Future<void> _loadUserCampusAndSlots() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      _loadSlots();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) _showSnack('Error loading user profile: $e', isError: true);
    }
  }

  // ================= FETCH SLOTS =================
  Future<void> _loadSlots() async {
    if (userCampus == null) return;
    setState(() => isLoading = true);
    _fadeController.reset();

    try {
      final now = DateTime.now();
      late final List response;

      if (selectedFilter == 'past') {
        response = await supabase
            .from('appointment_slots_version2')
            .select()
            .ilike('campus', userCampus!)
            .order('appointment_date', ascending: false)
            .order('appointment_time', ascending: false);
      } else {
        response = await supabase
            .from('appointment_slots_version2')
            .select()
            .ilike('campus', userCampus!)
            .order('appointment_date', ascending: true)
            .order('appointment_time', ascending: true);
      }

      final fetchedSlots =
          response.map((json) => AppointmentSlot.fromJson(json)).toList();

      // ====== AUTO-DISABLE PAST SLOTS ======
      for (var slot in fetchedSlots) {
        final slotDateTime = DateTime(
          slot.appointmentDate.year,
          slot.appointmentDate.month,
          slot.appointmentDate.day,
          slot.appointmentTime.hour,
          slot.appointmentTime.minute,
        );
        if (slotDateTime.isBefore(now) && slot.isAvailable) {
          await supabase
              .from('appointment_slots_version2')
              .update({'is_available': false}).eq('id', slot.id);
        }
      }

      // ====== CLIENT-SIDE FILTERING ======
      final filteredSlots = fetchedSlots.where((slot) {
        final slotDateTime = DateTime(
          slot.appointmentDate.year,
          slot.appointmentDate.month,
          slot.appointmentDate.day,
          slot.appointmentTime.hour,
          slot.appointmentTime.minute,
        );
        if (selectedFilter == 'upcoming') {
          return slotDateTime.isAfter(now) ||
              slotDateTime.isAtSameMomentAs(now);
        } else if (selectedFilter == 'past') {
          return slotDateTime.isBefore(now);
        }
        return true;
      }).toList();

      setState(() {
        slots = filteredSlots;
        isLoading = false;
      });
      _fadeController.forward();
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) _showSnack('Error loading slots: $e', isError: true);
    }
  }

  // ─────────────────────────────────────────────
  // SNACK BAR HELPER
  // ─────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFD93025) : _primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ================= SHOW ADD SLOT DIALOG =================
  Future<void> _showAddSlotDialog() async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    int maxSlots = 1;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            width: 480,
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header band
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                  decoration: const BoxDecoration(
                    color: _primary,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'New Appointment Slot',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Campus chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _primary.withOpacity(0.2), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded,
                                size: 15, color: _primary),
                            const SizedBox(width: 8),
                            Text(
                              userCampus?.toUpperCase() ?? '—',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Date picker
                      _dialogLabel('Date'),
                      const SizedBox(height: 8),
                      _dialogPickerButton(
                        icon: Icons.calendar_month_rounded,
                        label: DateFormat('EEE, MMM d yyyy').format(selectedDate),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            builder: (ctx, child) =>
                                _datePickerTheme(ctx, child),
                          );
                          if (date != null) {
                            setDialogState(() => selectedDate = date);
                          }
                        },
                      ),
                      const SizedBox(height: 18),

                      // Time picker
                      _dialogLabel('Time'),
                      const SizedBox(height: 8),
                      _dialogPickerButton(
                        icon: Icons.schedule_rounded,
                        label: selectedTime.format(context),
                        onTap: () async {
                          final now = DateTime.now();
                          final isToday =
                              selectedDate.year == now.year &&
                                  selectedDate.month == now.month &&
                                  selectedDate.day == now.day;

                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );

                          if (time != null) {
                            if (isToday &&
                                (time.hour < TimeOfDay.now().hour ||
                                    (time.hour == TimeOfDay.now().hour &&
                                        time.minute <
                                            TimeOfDay.now().minute))) {
                              if (mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    title: const Text('Invalid Time'),
                                    content: const Text(
                                        'You cannot select a past time for today.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return;
                            }
                            setDialogState(() => selectedTime = time);
                          }
                        },
                      ),
                      const SizedBox(height: 18),

                      // Max slots stepper
                      _dialogLabel('Maximum Slots'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _stepperButton(
                              icon: Icons.remove,
                              onTap: maxSlots > 1
                                  ? () => setDialogState(() => maxSlots--)
                                  : null,
                            ),
                            SizedBox(
                              width: 52,
                              child: Text(
                                '$maxSlots',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _primary),
                              ),
                            ),
                            _stepperButton(
                              icon: Icons.add,
                              onTap: () => setDialogState(() => maxSlots++),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12)),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _addSlot(
                                  selectedDate, selectedTime, maxSlots);
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Add Slot'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 13),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogLabel(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey[700],
            letterSpacing: 0.4),
      );

  Widget _dialogPickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _primary),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton(
      {required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: onTap == null ? Colors.grey[100] : _primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              size: 18,
              color: onTap == null ? Colors.grey[400] : _primary),
        ),
      ),
    );
  }

  Widget _datePickerTheme(BuildContext ctx, Widget? child) {
    return Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: const ColorScheme.light(
            primary: _primary, onPrimary: Colors.white),
      ),
      child: child!,
    );
  }

  // ================= ADD SLOT =================
  Future<void> _addSlot(DateTime date, TimeOfDay time, int maxSlots) async {
    try {
      final timeString =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

      await supabase.from('appointment_slots_version2').insert({
        'appointment_date': date.toIso8601String().split('T')[0],
        'appointment_time': timeString,
        'max_slots': maxSlots,
        'booked_slots': 0,
        'is_available': true,
        'campus': userCampus!.toUpperCase(),
      });

      if (mounted) {
        _showSnack('Slot added successfully!');
        _loadSlots();
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().contains('duplicate')
              ? 'A slot already exists for this date and time.'
              : 'Error: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  // ================= TOGGLE SLOT =================
  Future<void> _toggleSlotAvailability(AppointmentSlot slot) async {
    try {
      await supabase
          .from('appointment_slots_version2')
          .update({'is_available': !slot.isAvailable}).eq('id', slot.id);

      if (mounted) {
        _showSnack(slot.isAvailable ? 'Slot disabled.' : 'Slot enabled.');
        _loadSlots();
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  // ================= VIEW BOOKINGS =================
  Future<void> _viewBookings(AppointmentSlot slot) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          width: 580,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1565C0),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Appointment Bookings',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          Text(slot.formattedDateTime,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: FutureBuilder<List<dynamic>>(
                  future: supabase
                      .from('medical_appointments_version2')
                      .select(
                          '*, borrowing_applications_version2(first_name, last_name, email_address, phone_number)')
                      .eq('slot_id', slot.id)
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                            'Error loading bookings: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red)),
                      );
                    }
                    final bookings = snapshot.data ?? [];
                    if (bookings.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  shape: BoxShape.circle),
                              child: Icon(Icons.event_busy_rounded,
                                  size: 40, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 14),
                            Text('No bookings yet',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: bookings.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final booking = bookings[index];
                          final app = booking['borrowing_applications'];
                          final status = booking['status'] ?? 'scheduled';
                          final statusColor = status == 'completed'
                              ? const Color(0xFF1A6B3A)
                              : status == 'cancelled'
                                  ? const Color(0xFFD93025)
                                  : const Color(0xFFE67E00);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: statusColor.withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor:
                                      statusColor.withOpacity(0.12),
                                  child: Icon(
                                    status == 'completed'
                                        ? Icons.check_circle_rounded
                                        : status == 'cancelled'
                                            ? Icons.cancel_rounded
                                            : Icons.schedule_rounded,
                                    color: statusColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${app?['first_name'] ?? 'Unknown'} ${app?['last_name'] ?? ''}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14),
                                      ),
                                      if (app?['email_address'] != null) ...[
                                        const SizedBox(height: 2),
                                        Text(app['email_address'],
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600])),
                                      ],
                                      if (app?['phone_number'] != null)
                                        Text(app['phone_number'],
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: statusColor,
                                        letterSpacing: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= DELETE SLOT =================
  Future<void> _deleteSlot(AppointmentSlot slot) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD93025), size: 22),
            SizedBox(width: 8),
            Text('Delete Slot', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          slot.bookedSlots > 0
              ? 'This slot has ${slot.bookedSlots} booking(s). Are you sure you want to delete it?'
              : 'Are you sure you want to delete this slot?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD93025),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('appointment_slots_version2')
            .delete()
            .eq('id', slot.id);

        if (mounted) {
          _showSnack('Slot deleted successfully.');
          _loadSlots();
        }
      } catch (e) {
        if (mounted) _showSnack('Error: $e', isError: true);
      }
    }
  }

  // ================= FILTER TAB =================
  Widget _filterTab(String value, String label, IconData icon) {
    final isSelected = selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => selectedFilter = value);
        _loadSlots();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SLOT CARD =================
  Widget _slotCard(AppointmentSlot slot, int index) {
    final slotDateTime = DateTime(
      slot.appointmentDate.year,
      slot.appointmentDate.month,
      slot.appointmentDate.day,
      slot.appointmentTime.hour,
      slot.appointmentTime.minute,
    );
    final bool past = slotDateTime.isBefore(DateTime.now());
    final double fillRatio =
        slot.maxSlots > 0 ? slot.bookedSlots / slot.maxSlots : 0;
    final Color fillColor = fillRatio >= 1
        ? const Color(0xFFD93025)
        : fillRatio >= 0.7
            ? const Color(0xFFE67E00)
            : _primary;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: past
                ? Colors.grey.shade200
                : slot.isAvailable
                    ? Colors.grey.shade200
                    : Colors.orange.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date block
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: past
                      ? Colors.grey[100]
                      : _primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('MMM')
                          .format(slot.appointmentDate)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: past ? Colors.grey[500] : _primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      DateFormat('d').format(slot.appointmentDate),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: past ? Colors.grey[500] : _primary,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      DateFormat('EEE')
                          .format(slot.appointmentDate)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: past ? Colors.grey[400] : Colors.grey[600],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ── Middle info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 5),
                        Text(
                          slot.appointmentTime.format(context),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: past
                                  ? Colors.grey[500]
                                  : Colors.grey[800]),
                        ),
                        const SizedBox(width: 10),
                        if (past)
                          _chip('Past', Colors.blueGrey.shade400)
                        else if (!slot.isAvailable)
                          _chip('Disabled', Colors.orange.shade700)
                        else if (slot.isFull)
                          _chip('Full', const Color(0xFFD93025))
                        else
                          _chip('Open', _primaryLight),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Capacity bar
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Capacity',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${slot.bookedSlots}/${slot.maxSlots}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: fillColor,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: fillRatio.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Colors.grey[200],
                            valueColor:
                                AlwaysStoppedAnimation<Color>(fillColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ── Action buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (slot.bookedSlots > 0)
                    _actionBtn(
                      label: 'View (${slot.bookedSlots})',
                      icon: Icons.people_rounded,
                      color: const Color(0xFF1565C0),
                      onTap: () => _viewBookings(slot),
                    ),
                  if (slot.bookedSlots > 0) const SizedBox(height: 6),
                  if (!past)
                    _actionBtn(
                      label: slot.isAvailable ? 'Disable' : 'Enable',
                      icon: slot.isAvailable
                          ? Icons.block_rounded
                          : Icons.check_circle_rounded,
                      color: slot.isAvailable
                          ? Colors.orange.shade700
                          : _primary,
                      onTap: () => _toggleSlotAvailability(slot),
                    ),
                  if (!past) const SizedBox(height: 6),
                  if (!past)
                    _actionBtn(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFD93025),
                      onTap: () => _deleteSlot(slot),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.3),
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  // ================= STATS ROW =================
  Widget _statsRow() {
    final now = DateTime.now();
    final upcoming = slots
        .where((s) => DateTime(s.appointmentDate.year, s.appointmentDate.month,
                s.appointmentDate.day, s.appointmentTime.hour,
                s.appointmentTime.minute)
            .isAfter(now))
        .length;
    final totalBooked = slots.fold<int>(0, (sum, s) => sum + s.bookedSlots);
    final available = slots.where((s) => s.isAvailable).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          _statCard('Total Slots', '${slots.length}',
              Icons.calendar_month_rounded, _primary),
          const SizedBox(width: 12),
          _statCard('Upcoming', '$upcoming', Icons.upcoming_rounded,
              const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _statCard('Bookings', '$totalBooked', Icons.people_rounded,
              const Color(0xFFE67E00)),
          const SizedBox(width: 12),
          _statCard('Available', '$available',
              Icons.event_available_rounded, _primaryLight),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      drawer: const HealthDrawer(),
      body: Column(
        children: [
          // App header with menu button
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

          // Page header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Medical Appointments',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A1A)),
                      ),
                      const SizedBox(height: 4), // a little spacing
                      Text(
                        'Manage and schedule medical appointment slots for your campus', // ← your subheader
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      if (userCampus != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(height: 8),
                            Icon(Icons.location_on_rounded,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              userCampus!.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadSlots,
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: userCampus != null ? _showAddSlotDialog : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Slot',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // Stats row
          if (!isLoading && slots.isNotEmpty) ...[
            _statsRow(),
            const SizedBox(height: 12),
          ],

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _filterTab(
                        'upcoming', 'Upcoming', Icons.upcoming_rounded),
                    _filterTab('past', 'Past', Icons.history_rounded),
                    _filterTab('all', 'All',
                        Icons.calendar_view_month_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Slot list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : slots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 20)
                                ],
                              ),
                              child: Icon(Icons.event_busy_rounded,
                                  size: 52, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'No slots found',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[700]),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap "Add Slot" to create one',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: userCampus != null
                                  ? _showAddSlotDialog
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add Slot'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.only(bottom: 24, top: 4),
                        itemCount: slots.length,
                        itemBuilder: (context, index) =>
                            _slotCard(slots[index], index),
                      ),
          ),
        ],
      ),
    );
  }
}