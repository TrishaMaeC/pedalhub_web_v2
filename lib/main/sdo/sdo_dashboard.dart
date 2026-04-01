import 'package:flutter/material.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/sdo_drawer.dart';
import 'package:pedalhub_admin/widgets/bike_tracking_map.dart';

class SDODashboard extends StatelessWidget {
  const SDODashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],

      // ✅ Drawer as widget
      drawer: const SDODrawer(),

      body: Column(
        children: [
          // ✅ Header image with burger icon INSIDE
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
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
              ),
            ],
          ),

          
          // Dashboard Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text(
                    'SDO Dashboard',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Real-time bike tracking and monitoring',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bike Tracking Map
                  const Expanded(
                    child: BikeTrackingMap(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}