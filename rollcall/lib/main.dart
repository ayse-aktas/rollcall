import 'package:flutter/material.dart';
import 'package:rollcall/view/login/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'view/student/student_home_page.dart';
import 'view/teacher/teacher_home_page.dart';
import 'view/admin/admin_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:
        'https://vytqqwrcmmjuutysxwxl.supabase.co', // ← Settings → API → Project URL
    anonKey: 'sb_secret_GLWXhzyDqkM4dHddbpwLmg_1we_reFl',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
