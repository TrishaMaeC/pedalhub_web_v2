// lib/widgets/app_header.dart
import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/header.png',
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 120,
          color: Colors.grey[300],
          child: const Center(
            child: Text('Header Image Not Found'),
          ),
        );
      },
    );
  }
}