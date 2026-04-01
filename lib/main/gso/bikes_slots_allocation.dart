import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/gso_drawer.dart';

class BikeManagementPage extends StatefulWidget {
  const BikeManagementPage({super.key});

  @override
  State<BikeManagementPage> createState() => _BikeManagementPageState();
}

class _BikeManagementPageState extends State<BikeManagementPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> bikes = [];
  bool isLoading = true;

  // ── Logged-in user's campus (fetched from profiles table)
  String? userCampus;

  @override
  void initState() {
    super.initState();
    _loadUserCampusAndData();
  }

  // ─────────────────────────────────────────────
  // LOAD USER CAMPUS THEN FETCH
  // ─────────────────────────────────────────────
  Future<void> _loadUserCampusAndData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      // Normalize to lowercase so ilike matching works regardless of casing
      setState(() => userCampus = (profile['campus'] as String).toLowerCase());
      _loadData();
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user profile: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ================= LOAD ALL DATA =================
  Future<void> _loadData() async {
    // Guard: don't fetch until campus is loaded
    if (userCampus == null) return;

    setState(() => isLoading = true);

    try {
      final bikesData = await supabase
          .from('bikes')
          .select()
          .ilike('campus', userCampus!)
          .order('bike_number', ascending: true);

      setState(() {
        bikes = List<Map<String, dynamic>>.from(bikesData);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ================= ADD BIKE DIALOG =================
  Future<void> _showAddBikeDialog() async {
    int quantityToAdd = 1;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ===== HEADER =====
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Bike(s)',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const Divider(),
                const SizedBox(height: 16),

                // ===== CAMPUS DISPLAY (read-only, from profile) =====
                const Text(
                  'Campus',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    userCampus?.toUpperCase() ?? 'Loading...',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 20),

                // ===== NUMBER OF BIKES =====
                const Text(
                  'Number of Bikes to Add',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    IconButton(
                      onPressed: quantityToAdd > 1
                          ? () => setDialogState(() => quantityToAdd--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),

                    Text(
                      '$quantityToAdd',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),

                    IconButton(
                      onPressed: () => setDialogState(() => quantityToAdd++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),

                    const SizedBox(width: 16),

                    Text(
                      quantityToAdd == 1 ? '1 bike' : '$quantityToAdd bikes',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ===== INFO BOX =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Bikes will be named automatically (BIKE 1, BIKE 2, etc.)',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ===== BUTTONS =====
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),

                    const SizedBox(width: 8),

                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _addBikesInBulk(quantityToAdd, userCampus!.toUpperCase());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        quantityToAdd == 1 ? 'Add Bike' : 'Add $quantityToAdd Bikes',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= ADD BIKES IN BULK =================
  Future<void> _addBikesInBulk(int quantity, String campus) async {
    try {
      final existingBikes = await supabase.from('bikes').select('bike_number');
      final existingBikeNumbers = existingBikes.map((b) => b['bike_number'] as String).toSet();

      int highestNumber = 0;
      for (var bikeNumber in existingBikeNumbers) {
        final numberMatch = RegExp(r'BIKE (\d+)').firstMatch(bikeNumber);
        if (numberMatch != null) {
          final num = int.parse(numberMatch.group(1)!);
          if (num > highestNumber) highestNumber = num;
        }
      }

      int successCount = 0;
      int failCount = 0;
      int currentNumber = highestNumber + 1;

      for (int i = 0; i < quantity; i++) {
        String bikeNumber;
        do {
          bikeNumber = 'BIKE $currentNumber';
          currentNumber++;
        } while (existingBikeNumbers.contains(bikeNumber));

        try {
          await _addBike(bikeNumber, campus);
          existingBikeNumbers.add(bikeNumber);
          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('Failed to add $bikeNumber: $e');
        }
      }

      if (mounted) {
        _loadData();
        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failCount == 0
                    ? 'Successfully added $successCount bike${successCount > 1 ? 's' : ''}!'
                    : 'Added $successCount bike${successCount > 1 ? 's' : ''}, $failCount failed',
              ),
              backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to add bikes'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ================= ADD SINGLE BIKE =================
  Future<void> _addBike(String bikeNumber, String campus) async {
    try {
      await supabase.from('bikes').insert({
        'bike_number': bikeNumber,
        'status': 'available',
        'campus': campus,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ================= DELETE BIKE =================
  Future<void> _deleteBike(int bikeId, String bikeNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bike'),
        content: Text('Are you sure you want to delete $bikeNumber?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('bikes').delete().eq('id', bikeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bike deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ================= BIKE CARD =================
  Widget _buildBikeCard(Map<String, dynamic> bike) {
    final status = bike['status'];

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'available':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'in_use':
        statusColor = Colors.orange;
        statusIcon = Icons.pedal_bike;
        break;
      case 'maintenance':
        statusColor = Colors.red;
        statusIcon = Icons.build;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          bike['bike_number'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Campus: ${bike['campus']}"),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteBike(bike['id'], bike['bike_number']),
        ),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const GsoDrawer(),
      body: Column(
        children: [
          // ===== HEADER =====
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

          // ===== PAGE HEADER =====
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bike Management System',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (userCampus != null)
                      Text(
                        'Campus: ${userCampus!.toUpperCase()}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: userCampus != null ? _showAddBikeDialog : null,
                      icon: const Icon(Icons.pedal_bike),
                      label: const Text('Add Bike'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadData,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ===== BIKES LIST =====
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      if (bikes.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No bikes yet. Add one to get started!'),
                          ),
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                        children: [
                          // Dynamic header
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '🚲 Bikes in ${userCampus?.toUpperCase() ?? ''}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),

                          // Bike cards
                          ...bikes.map((bike) => _buildBikeCard(bike)),

                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}