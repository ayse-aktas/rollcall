import 'package:flutter/material.dart';
import 'package:rollcall/view/login/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'view/student/student_home_page.dart';
import 'view/teacher/teacher_home_page.dart';
import 'view/admin/admin_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vytqqwrcmmjuutysxwxl.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_kb2fFjGqeOYNIydlStdKVQ_umyYTxUl',
  );

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/ogrenci-anasayfa': (context) => const StudentHomePage(),
        '/ogretmen-anasayfa': (context) => const TeacherHomePage(),
        '/admin-panel': (context) => const AdminPage(),
      },
    );
  }
}
