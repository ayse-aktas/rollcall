import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Wait a bit for the animation feel (optional)
    await Future.delayed(const Duration(milliseconds: 1000));
    
    final session = Supabase.instance.client.auth.currentSession;
    
    if (session == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      // User is logged in, fetch role
      final uid = session.user.id;
      final response = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', uid)
          .single();

      final role = response['role'] as String;

      if (!mounted) return;

      if (role == 'student') {
        Navigator.pushReplacementNamed(context, '/ogrenci-anasayfa');
      } else if (role == 'teacher') {
        Navigator.pushReplacementNamed(context, '/ogretmen-anasayfa');
      } else if (role == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin-panel');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_tethering_rounded,
                color: AppColors.primary,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'RollCall',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
