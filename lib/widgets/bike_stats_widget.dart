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
  
  // Vice Chancellor specific stats
  int totalFitToUse = 0; // Waiting for automated system processing
  int totalVicePending = 0; // Currently being ranked by system
  int totalAutoApproved = 0; // Auto-approved by system (for_release with decision_source = 'SYSTEM')
  int totalViceRejected = 0; // Not selected by ranking system
  int totalForRelease = 0; // All applications ready for GSO release (regardless of history)
  
  // Bike inventory stats
  int totalAvailableBikes = 0;
  int totalBikesInUse = 0;
  int totalMaintenance = 0;
  
  // Historical stats (all applications that passed through VC stage)
  int totalProcessedBySystem = 0; // Total applications processed by automated system

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
      // Applications waiting for automated system (fit_to_use)
      final fitToUse = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'fit_to_use')
          .ilike('campus', widget.campus);

      // Applications currently being ranked (vice_pending)
      final vicePending = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'vice_pending')
          .ilike('campus', widget.campus);

      // Auto-approved applications (for_release with decision_source = 'SYSTEM')
      final autoApproved = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'for_release')
          .eq('decision_source', 'SYSTEM')
          .ilike('campus', widget.campus);

      // Rejected by automated system (vice_rejected)
      final viceRejected = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'vice_rejected')
          .ilike('campus', widget.campus);

      // All applications ready for release (for_release status)
      final forRelease = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('status', 'for_release')
          .ilike('campus', widget.campus);

      // Total processed by automated system (for historical tracking)
      // This includes applications that have decision_source = 'SYSTEM' regardless of current status
      final processedBySystem = await supabase
          .from('borrowing_applications_version2')
          .select('id')
          .eq('decision_source', 'SYSTEM')
          .ilike('campus', widget.campus);

      // Bike inventory
      final availableBikes = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'available')
          .ilike('campus', widget.campus);

      final bikesInUse = await supabase
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
          totalFitToUse = (fitToUse as List).length;
          totalVicePending = (vicePending as List).length;
          totalAutoApproved = (autoApproved as List).length;
          totalViceRejected = (viceRejected as List).length;
          totalForRelease = (forRelease as List).length;
          totalProcessedBySystem = (processedBySystem as List).length;
          totalAvailableBikes = (availableBikes as List).length;
          totalBikesInUse = (bikesInUse as List).length;
          totalMaintenance = (maintenance as List).length;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('STATS ERROR: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Applications in automated system pipeline
          _statCard(
            'Pending Automated Review',
            totalFitToUse,
            Icons.pending_actions_rounded,
            const Color(0xFFF57C00),
            subtitle: 'Fit to Use - Awaiting System',
          ),
          const SizedBox(width: 16),
          _statCard(
            'System Processing',
            totalVicePending,
            Icons.autorenew_rounded,
            const Color(0xFF1976D2),
            subtitle: 'Automated Ranking In Progress',
          ),
          const SizedBox(width: 16),
          _statCard(
            'Auto-Approved',
            totalAutoApproved,
            Icons.check_circle_rounded,
            const Color(0xFF388E3C),
            subtitle: 'System Approved for Release',
          ),
          const SizedBox(width: 16),
          _statCard(
            'Not Selected',
            totalViceRejected,
            Icons.cancel_rounded,
            const Color(0xFFD32F2F),
            subtitle: 'Ranking Score Too Low',
          ),
          const SizedBox(width: 16),
          _statCard(
            'Ready for GSO Release',
            totalForRelease,
            Icons.local_shipping_rounded,
            const Color(0xFF6A1B9A),
            subtitle: 'All For Release Applications',
          ),
          const SizedBox(width: 16),
          
          // Divider
          Container(
            width: 2,
            height: 100,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          const SizedBox(width: 16),
          
          // Bike inventory
          _statCard(
            'Available Bikes',
            totalAvailableBikes,
            Icons.pedal_bike_rounded,
            const Color(0xFF00897B),
            subtitle: 'Ready for Assignment',
          ),
          const SizedBox(width: 16),
          _statCard(
            'Bikes In Use',
            totalBikesInUse,
            Icons.directions_bike_rounded,
            const Color(0xFF5E35B1),
            subtitle: 'Currently Borrowed',
          ),
          const SizedBox(width: 16),
          _statCard(
            'Under Maintenance',
            totalMaintenance,
            Icons.build_rounded,
            const Color(0xFFE64A19),
            subtitle: 'Maintenance/For Maintenance',
          ),
          const SizedBox(width: 16),
          
          // Historical stat
          _statCard(
            'Total System Processed',
            totalProcessedBySystem,
            Icons.history_rounded,
            const Color(0xFF455A64),
            subtitle: 'All-Time Automated Decisions',
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    int value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      width: 220,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: color,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}