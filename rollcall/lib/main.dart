import 'package:flutter/material.dart';
import 'package:rollcall/view/login/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'view/student/pages/student_home_page.dart';
import 'view/teacher/pages/teacher_home_page.dart';
import 'view/teacher/pages/course_students_page.dart';
import 'view/admin/admin_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vytqqwrcmmjuutysxwxl.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_kb2fFjGqeOYNIydlStdKVQ_umyYTxUl',
  );

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Firebase ve Bildirimlerin Hazırlanması
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _setupNotifications();

  runApp(const MyApp());
}

Future<void> _setupNotifications() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // 1. Bildirim İzni İste
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // 2. 'all' kanalına abone ol (Hocanın attığı bildirimler için)
  await messaging.subscribeToTopic("all");

  // 3. Android için ön plan bildirim önceliğini ayarla
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
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
        '/ogretmen-ders-detay': (context) => const CourseStudentsPage(),
        '/admin-panel': (context) => const AdminPage(),
      },
    );
  }
}
