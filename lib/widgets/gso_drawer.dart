import 'package:flutter/material.dart';

// ✅ DIRECT IMPORTS FROM lib/
import 'package:pedalhub_admin/main/gso/gso_dashboard.dart';
import 'package:pedalhub_admin/main/gso/for_release.dart';
import 'package:pedalhub_admin/main/gso/for_return.dart';
import 'package:pedalhub_admin/login_page.dart';
import 'package:pedalhub_admin/main/gso/bikes_slots_allocation.dart';
import 'package:pedalhub_admin/main/gso/termination_page.dart';
import 'package:pedalhub_admin/main/gso/reports_gso.dart';

class GsoDrawer extends StatelessWidget {
  const GsoDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.red.shade50,
              Colors.white,
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ================= DRAWER HEADER =================
            Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red.shade700,
                    Colors.red.shade500,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: -30,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.pedal_bike_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'GSO Alangilan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'PedalHub Portal',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ================= DASHBOARD =================
            _AnimatedDrawerItem(
              icon: Icons.dashboard_rounded,
              title: 'Dashboard',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GSODashboard(),
                  ),
                );
              },
            ),

            // ================= FOR RELEASE==========
            _AnimatedDrawerItem(
              icon: Icons.check_circle_outline_rounded,
              title: 'For Release',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ForReleasePage(),
                  ),
                );
              },
            ),

// ================= DASHBOARD =================
            _AnimatedDrawerItem(
              icon: Icons.assignment_return_rounded,
              title: 'Returns',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ForReturnPage(),
                  ),
                );
              },
            ),

            // ================= SLOTS =================
            _AnimatedDrawerItem(
              icon: Icons.directions_bike_rounded,
              title: 'Bike Management',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BikeManagementPage(),
                  ),
                );
              },
            ),

// ================= DASHBOARD =================
            _AnimatedDrawerItem(
              icon: Icons.gavel_rounded,
              title: 'Terminations',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TerminationPage(),
                  ),
                );
              },
            ),
            
_AnimatedDrawerItem(
  icon: Icons.build_rounded,
  title: 'Reports & Maintenance',
  onTap: () {
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const BikeReportsMaintenancePage(),
      ),
    );
  },
),
            // ================= LOGOUT =================
            _AnimatedDrawerItem(
              icon: Icons.logout_rounded,
              title: 'Logout',
              isLogout: true,
              onTap: () {
                Navigator.pop(context);
                
                // Show confirmation dialog
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.logout_rounded,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Logout',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      content: const Text(
                        'Are you sure you want to logout?',
                        style: TextStyle(fontSize: 16),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                                                  ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            
                            // Navigate to login page
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Logout',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ================= ANIMATED DRAWER ITEM =================
class _AnimatedDrawerItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isLogout;

  const _AnimatedDrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isLogout = false,
  });

  @override
  State<_AnimatedDrawerItem> createState() => _AnimatedDrawerItemState();
}

class _AnimatedDrawerItemState extends State<_AnimatedDrawerItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
          _controller.forward();
        },
        onExit: (_) {
          setState(() => _isHovered = false);
          _controller.reverse();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.translate(
                offset: Offset(_slideAnimation.value, 0),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    gradient: _isHovered
                        ? LinearGradient(
                            colors: widget.isLogout
                                ? [
                                    Colors.red.shade50,
                                    Colors.red.shade100,
                                  ]
                                : [
                                    Colors.red.shade50,
                                    Colors.red.shade100.withOpacity(0.5),
                                  ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    border: _isHovered
                        ? Border.all(
                            color: widget.isLogout
                                ? Colors.red.shade300
                                : Colors.red.shade200,
                            width: 1,
                          )
                        : null,
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ListTile(
                    leading: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? (widget.isLogout
                                ? Colors.red.shade600
                                : Colors.red.shade500)
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.icon,
                        color: _isHovered ? Colors.white : Colors.red.shade700,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            _isHovered ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isLogout
                            ? Colors.red.shade700
                            : (_isHovered
                                ? Colors.red.shade900
                                : Colors.grey.shade800),
                      ),
                    ),
                    trailing: AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: _isHovered ? 0.0 : -0.05,
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: _isHovered
                            ? Colors.red.shade700
                            : Colors.grey.shade400,
                      ),
                    ),
                    onTap: widget.onTap,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}