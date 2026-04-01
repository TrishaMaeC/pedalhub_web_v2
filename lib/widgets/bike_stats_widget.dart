import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BikeStatsWidget extends StatefulWidget {
  final String campus;

  const BikeStatsWidget({
    super.key,
    required this.campus,
  });

  @override
  State<BikeStatsWidget> createState() => BikeStatsWidgetState();
}

class BikeStatsWidgetState extends State<BikeStatsWidget> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  int totalActive = 0;
  int totalAvailableBikes = 0;
  int totalBikesOut = 0;
  int totalReturned = 0;
  int totalMaintenance = 0;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  @override
  void didUpdateWidget(BikeStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campus != widget.campus) {
      _fetchStats();
    }
  }

  Future<void> _fetchStats() async {
    setState(() => isLoading = true);
    try {
      final active = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'active')
          .ilike('campus', widget.campus);

      final returned = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'completed')
          .ilike('campus', widget.campus);

      final availableBikes = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'available')
          .ilike('campus', widget.campus);

      final bikesOut = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'in_use')
          .ilike('campus', widget.campus);

      final maintenance = await supabase
          .from('bikes')
          .select('id')
          .inFilter('status', ['maintenance', 'for_maintenance'])
          .ilike('campus', widget.campus);

      if (mounted) {
        setState(() {
          totalActive = (active as List).length;
          totalReturned = (returned as List).length;
          totalAvailableBikes = (availableBikes as List).length;
          totalBikesOut = (bikesOut as List).length;
          totalMaintenance = (maintenance as List).length;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('STATS ERROR: $e');
      setState(() => isLoading = false);
    }
  }

  // Public method so parent pages can trigger a refresh
  Future<void> refresh() => _fetchStats();

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
          ),
        ),
      );
    }

    return Row(
      children: [
        _statCard('Total Active Borrowers', totalActive, Icons.people_rounded, const Color(0xFF1565C0)),
        const SizedBox(width: 16),
        _statCard('Available Bikes', totalAvailableBikes, Icons.pedal_bike_rounded, const Color(0xFF388E3C)),
        const SizedBox(width: 16),
        _statCard('Bikes Currently Out', totalBikesOut, Icons.directions_bike_rounded, const Color(0xFFF57C00)),
        const SizedBox(width: 16),
        _statCard('Returned / Completed', totalReturned, Icons.check_circle_rounded, const Color(0xFF6A1B9A)),
        const SizedBox(width: 16),
        _statCard('Under Maintenance', totalMaintenance, Icons.build_rounded, const Color(0xFFD32F2F)),
      ],
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}