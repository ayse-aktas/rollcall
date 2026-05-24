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
import 'view/teacher/pages/teacher_analytics_page.dart';
import 'view/admin/admin_page.dart';
import 'view/splash/splash_page.dart';
import 'view/login/forgot_password_page.dart';
import 'view/login/reset_password_page.dart';
import 'view/login/support_form_page.dart';

import 'core/utils/logger.dart';

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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _setupNotifications();

  AppLogger.i('🚀 Uygulama başlatıldı: Supabase ve Firebase hazır.');

  runApp(const MyApp());
}

Future<void> _setupNotifications() async {
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Bildirim İzni İste
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // 2. 'all' kanalına abone ol (Hocanın attığı bildirimler için)
    await messaging.subscribeToTopic("all");

    // 3. Android için ön plan bildirim önceliğini ayarla
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  } catch (e) {
    AppLogger.e('Firebase Messaging Hatası: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/login': (context) => const LoginPage(),
        '/forgot-password': (context) => const ForgotPasswordPage(),
        '/reset-password': (context) => const ResetPasswordPage(),
        '/ogrenci-anasayfa': (context) => const StudentHomePage(),
        '/ogretmen-anasayfa': (context) => const TeacherHomePage(),
        '/ogretmen-ders-detay': (context) => const CourseStudentsPage(),
        '/ogretmen-analiz': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
          return TeacherAnalyticsPage(course: args);
        },
        '/admin-panel': (context) => const AdminPage(),
        '/support': (context) => const SupportFormPage(),
      },
    );
  }
}
