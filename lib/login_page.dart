// lib/login_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main/gso/gso_dashboard.dart';
import 'main/sdo/sdo_dashboard.dart';
import 'main/health/health_dashboard.dart';
import 'main/vice/vice_dashboard.dart';
import 'main/hrmo/hrmo_dashboard.dart';
import 'package:pedalhub_admin/main/super_admin/super_admin_dashboard.dart';
import 'package:pedalhub_admin/main/guidance/guidance_dashboard.dart';
import 'package:pedalhub_admin/main/fake_student_portal/student_portal.dart';
import 'package:pedalhub_admin/main/property_supply/property_supply_management.dart';
import 'dart:async';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  int _failedAttempts = 0;
  DateTime? _lockoutEndTime;
  static const int _maxAttempts = 5;
  static const int _lockoutDurationSeconds = 60;
  Timer? _lockoutTimer;
  String? _loginErrorMessage;

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        _loginErrorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authResponse =
          await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final userId = authResponse.user!.id;

      final roleResponse = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();

      final role = roleResponse['role'];

      if (!mounted) return;

      switch (role) {
        case 'GSO':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GSODashboard()),
          );
          break;
        case 'SDO':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SDODashboard()),
          );
          break;
        case 'HEALTH':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HealthDashboard()),
          );
          break;
        case 'VICE':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ViceChancellorDashboardPage()),
          );
          break;
        case 'PSO':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PropertySupplyDashboardPage()),
          );
          break;
        case 'HRMO':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const HrmoRenewalApprovalPage()),
          );
          break;
        case 'super_admin':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const SuperAdminDashboard()),
          );
          break;
        case 'DISCIPLINE':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const OsdDashboardPage()),
          );
          break;
        default:
          throw 'Unauthorized role';
      }
    } catch (e) {
      if (!mounted) return;

      _failedAttempts++;

      if (_failedAttempts < _maxAttempts) {
        setState(() {
          _loginErrorMessage =
              'Invalid email or password. Attempts left: ${_maxAttempts - _failedAttempts}';
        });
      } else {
        _lockoutEndTime = DateTime.now()
            .add(const Duration(seconds: _lockoutDurationSeconds));

        setState(() => _loginErrorMessage = null);

        _lockoutTimer?.cancel();
        _lockoutTimer =
            Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() {});
          if (!_isLockedOut) timer.cancel();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isLockedOut {
    if (_lockoutEndTime == null) return false;
    if (DateTime.now().isAfter(_lockoutEndTime!)) {
      _failedAttempts = 0;
      _lockoutEndTime = null;
      return false;
    }
    return true;
  }

  int get _remainingSeconds {
    if (_lockoutEndTime == null) return 0;
    final seconds =
        _lockoutEndTime!.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Header Image
          Image.asset(
            'assets/images/header.png',
            width: double.infinity,
            fit: BoxFit.cover,
          ),

          // Login Form
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'PedalHub Admin Login',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Email field
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon:
                              const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF1976D2), width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      TextField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon:
                              const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF1976D2), width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed:
                              (_isLoading || _isLockedOut) ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD32F2F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Text('Login',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),

                      // Error message
                      if (_loginErrorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loginErrorMessage!,
                          style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      // Lockout countdown
                      if (_isLockedOut) ...[
                        const SizedBox(height: 16),
                        Text(
                          '🔒 Account locked. Try again in $_remainingSeconds seconds.',
                          style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      // ── Divider ──
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(
                            child: Divider(color: Colors.grey[300])),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          child: Text('or',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400])),
                        ),
                        Expanded(
                            child: Divider(color: Colors.grey[300])),
                      ]),
                      const SizedBox(height: 16),

                      // ── Student Liability Portal Button ──
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StudentPortalPage(),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            side: const BorderSide(
                                color: Color(0xFF1565C0), width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.school_rounded,
                              size: 20),
                          label: const Text(
                            'Student Liability Portal',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}