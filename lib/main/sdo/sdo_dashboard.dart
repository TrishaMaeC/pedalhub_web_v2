import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/bike_inventory_widget.dart';
import 'package:pedalhub_admin/widgets/bike_reports_maintenance_widget.dart';
import 'package:pedalhub_admin/widgets/bike_tracking_map.dart';
import 'package:pedalhub_admin/login_page.dart';

class SDODashboard extends StatefulWidget {
  const SDODashboard({super.key});

  @override
  State<SDODashboard> createState() => _SDODashboardState();
}

class _SDODashboardState extends State<SDODashboard> {
  final supabase = Supabase.instance.client;
  final _inventoryKey = GlobalKey<BikeInventoryWidgetState>();
  final _reportsKey = GlobalKey<BikeReportsMaintenanceWidgetState>();

  String? userCampus;
  bool isLoadingCampus = true;

  @override
  void initState() {
    super.initState();
    _loadUserCampus();
  }

  Future<void> _loadUserCampus() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('campus')
          .eq('id', userId)
          .single();

      setState(() {
        userCampus = (profile['campus'] as String).toLowerCase();
        isLoadingCampus = false;
      });
    } catch (e) {
      debugPrint('CAMPUS LOAD ERROR: $e');
      if (mounted) {
        setState(() => isLoadingCampus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refresh() async {
    _inventoryKey.currentState?.refresh();
    _reportsKey.currentState?.refresh();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await supabase.auth.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Header with logout button
          Stack(
            children: [
              const AppHeader(),
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  color: Colors.red,
                  iconSize: 28,
                  tooltip: 'Logout',
                  onPressed: _confirmLogout,
                ),
              ),
            ],
          ),

          // Main content
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFD32F2F),
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageTitle(),
                    const SizedBox(height: 28),

                    if (isLoadingCampus)
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFD32F2F)),
                        ),
                      )
                    else if (userCampus != null) ...[
                      // Bike Tracking Map
                      const BikeTrackingMap(),
                      const SizedBox(height: 28),

                      // Bike Inventory Widget
                      BikeInventoryWidget(
                        key: _inventoryKey,
                        campus: userCampus!,
                      ),
                      const SizedBox(height: 28),

                      // Bike Reports & Maintenance Widget
                      Container(
                        height: 800,
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
                        ),
                        child: BikeReportsMaintenanceWidget(
                          key: _reportsKey,
                          campus: userCampus!,
                        ),
                      ),
                    ] else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 80),
                          child: Column(
                            children: [
                              Icon(Icons.error_outline,
                                  size: 72, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'Unable to load campus information',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                  colors: [Color(0xFFD32F2F), Color(0xFFE57373)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_bike_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SDO Dashboard',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  userCampus != null
                      ? 'Campus: ${userCampus!.toUpperCase()}  •  Real-time Bike Tracking & Monitoring'
                      : 'Loading campus information...',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
          tooltip: 'Refresh',
          color: Colors.grey[600],
        ),
      ],
    );
  }
}