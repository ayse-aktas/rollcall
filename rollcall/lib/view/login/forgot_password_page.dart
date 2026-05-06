import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/logger.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _schoolNoController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  Future<void> _sendResetCode() async {
    final schoolNo = _schoolNoController.text.trim();
    if (schoolNo.isEmpty) {
      setState(() => _errorMessage = 'Lütfen okul numaranızı girin.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // 1. Okul numarasından e-postayı bulalım
      final userData = await Supabase.instance.client
          .from('users')
          .select('email')
          .eq('school_no', schoolNo)
          .maybeSingle();

      if (userData == null) {
        setState(() => _errorMessage = 'Bu okul numarasına ait bir kullanıcı bulunamadı.');
        return;
      }

      final email = userData['email'] as String;

      // 2. Sıfırlama e-postası gönder
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      setState(() {
        _successMessage = 'Sıfırlama kodu $email adresine gönderildi.';
      });

      // 3. Kod girme ekranına yönlendir
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pushNamed(
            context,
            '/reset-password',
            arguments: {'email': email, 'school_no': schoolNo},
          );
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Kod gönderilirken bir hata oluştu.');
      AppLogger.e('Reset Password Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Şifremi Unuttum',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Okul numaranızı girin, şifre sıfırlama kodunu kayıtlı e-posta adresinize gönderelim.',
              style: TextStyle(color: Color(0xFF6F767E), fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 32),
            const Text(
              'OKUL NUMARASI',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1D1F), letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _schoolNoController,
              decoration: InputDecoration(
                hintText: 'G221210036',
                hintStyle: const TextStyle(color: Color(0xFF9A9FA5), fontSize: 15),
                prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF6F767E), size: 22),
                filled: true,
                fillColor: const Color(0xFFEFF3F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            if (_successMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_successMessage!, style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendResetCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E60D2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Kod Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
