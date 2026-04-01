import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lnbdudfuqemarczocjcm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxuYmR1ZGZ1cWVtYXJjem9jamNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY0MDI3MzksImV4cCI6MjA4MTk3ODczOX0.kgbxMMibojYuJpq2jikjh0NJ-TtkZI-oCBY4uS51YBQ',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}
